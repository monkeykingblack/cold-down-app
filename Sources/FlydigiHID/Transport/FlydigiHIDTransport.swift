import Foundation
import IOKit.hid
import ThermalCore

/// IOHIDManager transport for Flydigi BS-series coolers (USB or Bluetooth HID).
///
/// Ported from THRM's hidapi transport (internal/device): match by vendor/product only, write 25-byte output
/// reports with ID 0x02, read input reports (ID 0x01). 0xEF status pushes are kept as live telemetry and never
/// queued as transaction replies.
public final class FlydigiHIDTransport: FlydigiReportTransport, @unchecked Sendable {
    public static let vendorID = 0x37D7
    /// BS2 0x1001, BS2 Pro 0x1002, BS3 0x1003, BS3 Pro 0x1004 (THRM device.go).
    public static let productIDs = [0x1004, 0x1003, 0x1002, 0x1001]

    private let manager: IOHIDManager
    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var productID: Int?
    private var status: FlydigiStatus?
    private var buffer: [Data] = []
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Data, Error>)] = []
    private var cancelledWaiterIDs: Set<UUID> = []
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private let inputBufferLength = 64
    private let maximumBufferedReports = 32

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer = .allocate(capacity: inputBufferLength)
        inputBuffer.initialize(repeating: 0, count: inputBufferLength)
        let matching = Self.productIDs.map { productID -> [String: Any] in
            [kIOHIDVendorIDKey as String: Self.vendorID, kIOHIDProductIDKey as String: productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.attached, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            ThermalLog.hid.error("IOHIDManagerOpen failed: \(result, privacy: .public)")
        }
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deinitialize(count: inputBufferLength)
        inputBuffer.deallocate()
    }

    public func isConnected() async -> Bool { lock.withLock { device != nil } }
    public func latestStatus() async -> FlydigiStatus? { lock.withLock { status } }
    public func connectedProductID() async -> Int? { lock.withLock { productID } }

    public func send(_ report: Data) async throws {
        guard let device = lock.withLock({ device }) else { throw ThermalControlError.disconnected }
        let result = report.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(FlydigiPacketCodec.reportID),
                bytes.bindMemory(to: UInt8.self).baseAddress!, report.count
            )
        }
        guard result == kIOReturnSuccess else { throw ThermalControlError.unavailable("Flydigi output report failed") }
    }

    public func nextReport() async throws -> Data {
        try Task.checkCancellation()
        if let first = lock.withLock({ buffer.isEmpty ? nil : buffer.removeFirst() }) { return first }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if cancelledWaiterIDs.remove(waiterID) != nil { return true }
                    waiters.append((waiterID, continuation))
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: { [self] in
            let continuation: CheckedContinuation<Data, Error>? = lock.withLock {
                guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
                    cancelledWaiterIDs.insert(waiterID)
                    return nil
                }
                return waiters.remove(at: index).continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    public func discardPendingReports() async {
        lock.withLock { buffer.removeAll() }
    }

    /// A cooler can expose several HID collections; only one accepts our 24-byte output report.
    private static func acceptsControlReports(_ device: IOHIDDevice) -> Bool {
        // Some Bluetooth stacks omit the size property; accept those rather than never attaching.
        guard let size = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int else { return true }
        return size >= FlydigiPacketCodec.reportLength - 1
    }

    private func didAttach(_ newDevice: IOHIDDevice) {
        guard Self.acceptsControlReports(newDevice), lock.withLock({ device == nil }) else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            newDevice, inputBuffer, inputBufferLength, Self.inputReport, context
        )
        let result = IOHIDDeviceOpen(newDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            ThermalLog.hid.error("Could not open Flydigi device: \(result, privacy: .public)")
            if result == kIOReturnNotPermitted { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            return
        }
        let product = IOHIDDeviceGetProperty(newDevice, kIOHIDProductIDKey as CFString) as? Int
        lock.withLock {
            device = newDevice
            productID = product
            status = nil
        }
    }

    private func didRemove(_ removedDevice: IOHIDDevice) {
        let pending: [CheckedContinuation<Data, Error>] = lock.withLock {
            guard device === removedDevice else { return [] }
            device = nil
            productID = nil
            status = nil
            let copy = waiters.map(\.continuation)
            waiters.removeAll()
            cancelledWaiterIDs.removeAll()
            buffer.removeAll()
            return copy
        }
        pending.forEach { $0.resume(throwing: ThermalControlError.disconnected) }
    }

    private func didReceive(_ bytes: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let data = Data(bytes: bytes, count: length)
        if let frame = try? FlydigiPacketCodec.decode(data), let pushed = FlydigiStatus(frame: frame) {
            lock.withLock { status = pushed }
            return
        }
        let waiter: CheckedContinuation<Data, Error>? = lock.withLock {
            if waiters.isEmpty {
                if buffer.count >= maximumBufferedReports { buffer.removeFirst() }
                buffer.append(data)
                return nil
            }
            return waiters.removeFirst().continuation
        }
        waiter?.resume(returning: data)
    }

    private static let attached: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<FlydigiHIDTransport>.fromOpaque(context).takeUnretainedValue().didAttach(device)
    }

    private static let removed: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<FlydigiHIDTransport>.fromOpaque(context).takeUnretainedValue().didRemove(device)
    }

    private static let inputReport: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<FlydigiHIDTransport>.fromOpaque(context).takeUnretainedValue().didReceive(report, length: length)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }; return try body()
    }
}
