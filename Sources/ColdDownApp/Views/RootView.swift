import AppKit
import SwiftUI
import ThermalCore

/// Tabbed main window: a custom tab bar in the title bar (⌘1–⌘4 live in the View menu, see ColdDownApp).
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// SwiftUI keeps a `Window` scene's content alive after its window closes, and the model publishes every
    /// couple of seconds, so the whole page went on laying out and animating with nothing on screen — about a
    /// fifth of a core, measured. Dropping the content while the window is away leaves just the menu bar.
    /// Everything it shows lives in the model or `@AppStorage`, so nothing is lost by rebuilding it.
    @State private var windowVisible = true

    var body: some View {
        Group {
            if windowVisible {
                destination
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        // Fixed size: the layout is designed for exactly this canvas (the scene uses .contentSize resizability).
        .frame(width: AppModel.windowSize.width, height: AppModel.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbarContent }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.root)
        // The main window's lifetime drives the Dock icon: closing it leaves Cold Down in the menu bar only.
        .onAppear {
            windowVisible = true
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            windowVisible = false
            NSApp.setActivationPolicy(.accessory)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemStatus()
        }
        .task { model.start() }
    }

    /// `@Observable` models hand out bindings through `@Bindable`, which does not sit well inside a
    /// `@ToolbarContentBuilder`; writing the binding out is plainer than restructuring the toolbar.
    private var destinationBinding: Binding<AppTab> {
        Binding(get: { model.destination }, set: { model.destination = $0 })
    }

    @ViewBuilder
    private var destination: some View {
        switch model.destination {
        case .overview: OverviewView()
        case .fans: FansView()
        case .sensors: SensorsView()
        case .settings: SettingsView()
        }
    }

    /// Tabs sit in the title bar. The window title is hidden (see ColdDownApp) so they always have room, and on
    /// macOS 26 the shared glass background is turned off so each tab highlights on its own under the pointer.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // `sharedBackgroundVisibility` exists only in the macOS 26 SDK, so the runtime `#available` check
        // needs a compile-time gate too: older SDKs (Xcode 16 and earlier) do not declare the symbol at all.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { TabBar(selection: destinationBinding) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { TabBar(selection: destinationBinding) }
        }
        #else
        ToolbarItem(placement: .principal) { TabBar(selection: destinationBinding) }
        #endif
        ToolbarItem(placement: .primaryAction) { notice }
    }

    /// Present only while there is something to tell the user; nothing in the window moves when it appears.
    @ViewBuilder
    private var notice: some View {
        if let banner = StatusBanner.current(for: model) {
            NoticeToolbarButton(banner: banner) { model.destination = .settings }
        }
    }
}

/// The tab bar uses the same segmented control as the fan mode switches.
private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        PillSegmentedControl(
            label: "Section",
            options: AppTab.allCases.map { .init(value: $0, title: $0.rawValue, symbol: $0.symbol) },
            selection: $selection,
            identifier: AccessibilityID.tabs
        )
    }
}
