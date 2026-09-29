import SwiftUI
import ThermalCore

/// The cooler as a full-width card with its controls inline; nothing to select.
struct FansView: View {
    @Environment(AppModel.self) private var model
    @State private var highlightedFanID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Dashboard.spacing) {
                    if model.snapshot.fans.isEmpty {
                        DashboardCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("No cooler detected", systemImage: "snowflake.slash").font(.headline)
                                Text("Connect a Flydigi BS-series cooler over USB or Bluetooth.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(model.snapshot.fans) { fan in
                        FanControlCard(fan: fan, profile: model.profile(for: fan), highlighted: highlightedFanID == fan.id)
                            .id(fan.id)
                            // A container, so the card's ID does not replace its controls' own IDs.
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(AccessibilityID.fanCard(fan.id))
                    }
                }
                .padding(14)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { reveal(model.selectedFanID, with: proxy) }
            .onChange(of: model.selectedFanID) { _, fanID in reveal(fanID, with: proxy) }
        }
    }

    /// Scrolls to the card picked on the Overview or in the popover and briefly outlines it.
    private func reveal(_ fanID: String?, with proxy: ScrollViewProxy) {
        guard let fanID, model.snapshot.fans.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(fanID, anchor: .top) }
        highlightedFanID = fanID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if highlightedFanID == fanID { highlightedFanID = nil }
        }
    }
}
