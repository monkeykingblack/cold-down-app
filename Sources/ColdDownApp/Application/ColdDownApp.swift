import AppKit
import SwiftUI
import ThermalCore

@MainActor
final class ColdDownAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminating = false

    /// Monitoring runs from launch, independent of whether the main window is open.
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    /// Defers quitting until built-in fans have been handed back to macOS (bounded by a timeout).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct ColdDownApplication: App {
    @NSApplicationDelegateAdaptor(ColdDownAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Cold Down", id: AppModel.mainWindowID) {
            RootView()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
        // The tabs replace the title; hiding it keeps them from being pushed into the toolbar overflow menu.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Real menu items for tab shortcuts (invisible in-window buttons would also swallow mouse clicks).
            CommandGroup(before: .toolbar) {
                ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button(tab.rawValue) { appDelegate.model.destination = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
            }
        }

        MenuBarExtra {
            MenuBarContentView().environment(appDelegate.model)
        } label: {
            MenuBarLabel().environment(appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let presentation = MenuBarPresentation(
            snapshot: model.snapshot,
            showTemperature: model.preferences.showTemperatureInMenuBar
        )
        let needsAttention = model.snapshot.overallMode == .safetyFallback
        Label {
            // Monospaced digits keep the status item from changing width as the temperature changes.
            if !presentation.label.isEmpty { Text(presentation.label).monospacedDigit() }
        } icon: {
            if needsAttention {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                // Tinted teal → red with the hottest temperature (see MenuBarIcon).
                Image(nsImage: MenuBarIcon.image(
                    for: model.snapshot.sensors.hottestReading?.valueCelsius, colorful: model.colorfulMenuBarIcon
                ))
            }
        }
        .accessibilityLabel(presentation.label.isEmpty ? "Cold Down" : "Cold Down, hottest \(presentation.label)")
    }
}
