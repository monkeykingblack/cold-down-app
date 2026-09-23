import SwiftUI
import ThermalCore

/// The one attention message, shown as a notice icon (with a popover) in the window toolbar and the menu-bar popover.
struct StatusBanner: Equatable {
    enum Severity { case critical, warning, info }
    enum Action { case openSettings, approveHelper, dismissRecovery }

    /// Identifies *this* message; dismissing hides it until the situation changes to a different message.
    let id: String
    let severity: Severity
    let message: String
    let action: Action?

    /// Safety warnings (critical temperature, fallback) cannot be dismissed; everything else can.
    var dismissible: Bool { severity != .critical && id != "safety" }

    var title: String {
        switch id {
        case "critical": "Critical temperature"
        case "safety": "Safety fallback"
        case "recovery": "Recovered from an unexpected quit"
        default: "Fan control"
        }
    }

    @MainActor
    static func current(for model: AppModel) -> StatusBanner? {
        guard let banner = candidate(for: model) else { return nil }
        return banner.dismissible && model.dismissedBanners.contains(banner.id) ? nil : banner
    }

    @MainActor
    private static func candidate(for model: AppModel) -> StatusBanner? {
        let decision = model.snapshot.lastDecision
        if decision?.band == .critical {
            return StatusBanner(id: "critical", severity: .critical, message: decision?.reason ?? "Critical temperature. Fans are under macOS control.", action: nil)
        }
        if model.snapshot.overallMode == .safetyFallback {
            return StatusBanner(id: "safety", severity: .warning, message: decision?.reason ?? "Safety fallback is active.", action: nil)
        }
        if model.recoveredFromUncleanExit {
            return StatusBanner(
                id: "recovery",
                severity: .info,
                message: "Cold Down quit unexpectedly last time, so fans were returned to Auto. Your manual speeds are still saved.",
                action: .dismissRecovery
            )
        }
        let hasBuiltInFans = model.snapshot.fans.contains { $0.kind == .builtIn }
        guard hasBuiltInFans, model.helperDisplayStatus != .available else { return nil }
        if model.helperDisplayStatus == .requiresApproval {
            return StatusBanner(
                id: "helper.requiresApproval",
                severity: .info,
                message: "Turn on the Cold Down helper in Login Items to control built-in fans.",
                action: .approveHelper
            )
        }
        let severity: Severity = model.helperDisplayStatus == .notResponding ? .warning : .info
        return StatusBanner(
            id: "helper.\(model.helperDisplayStatus)",
            severity: severity,
            message: model.helperDisplayStatus.explanation,
            action: .openSettings
        )
    }

    var tint: Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }

    var symbol: String { severity == .info ? "info.circle.fill" : "exclamationmark.triangle.fill" }
}

/// Top-right toolbar icon that only exists while there is a message; clicking it shows the message in a popover.
struct NoticeToolbarButton: View {
    @EnvironmentObject private var model: AppModel
    let banner: StatusBanner
    var openSettings: () -> Void
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: banner.symbol)
                .foregroundStyle(banner.tint)
                .symbolRenderingMode(.hierarchical)
        }
        .help(banner.title)
        .accessibilityLabel("\(banner.title) notice")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Label(banner.title, systemImage: banner.symbol)
                    .font(.headline)
                    .foregroundStyle(banner.tint)
                Text(banner.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if banner.dismissible {
                        Button("Dismiss") { showing = false; model.dismiss(banner) }
                    }
                    Spacer()
                    switch banner.action {
                    case .approveHelper:
                        Button("Approve…") { showing = false; model.helperRegistration.openApprovalSettings() }
                            .keyboardShortcut(.defaultAction)
                    case .openSettings:
                        Button("Open Settings") { showing = false; openSettings() }
                            .keyboardShortcut(.defaultAction)
                    case .dismissRecovery, nil:
                        EmptyView()
                    }
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }
}
