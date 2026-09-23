import AppKit
import SwiftUI
import ThermalCore

/// Tabbed main window: a custom tab bar in the title bar (⌘1–⌘4 live in the View menu, see ColdDownApp).
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.destination {
            case .overview: OverviewView()
            case .fans: FansView()
            case .sensors: SensorsView()
            case .settings: SettingsView()
            }
        }
        // Fixed size: the layout is designed for exactly this canvas (the scene uses .contentSize resizability).
        .frame(width: AppModel.windowSize.width, height: AppModel.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbarContent }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.root)
        // The main window's lifetime drives the Dock icon: closing it leaves Cold Down in the menu bar only.
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemStatus()
        }
        .task { model.start() }
    }

    /// Tabs sit in the title bar. The window title is hidden (see ColdDownApp) so they always have room, and on
    /// macOS 26 the shared glass background is turned off so each tab highlights on its own under the pointer.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { TabBar(selection: $model.destination) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { TabBar(selection: $model.destination) }
        }
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
