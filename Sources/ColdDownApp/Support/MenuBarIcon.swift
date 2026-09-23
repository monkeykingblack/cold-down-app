import AppKit
import SwiftUI

/// The filled menu-bar fan glyph, still, tinted by the hottest temperature (same colour scale as the dashboard).
/// One image per colour step is rendered once and cached.
@MainActor
enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    /// - Parameter colorful: false returns a template image that the menu bar draws in its own colour
    ///   (white on a dark menu bar, black on a light one).
    static func image(for celsius: Double?, colorful: Bool) -> NSImage {
        guard colorful else { return monochrome }
        let color = NSColor(Dashboard.temperatureColor(celsius))
        let key = color.description
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "Cold Down")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false  // keep the colour instead of the menu bar's monochrome rendering
        cache[key] = image
        return image
    }

    private static let monochrome: NSImage = {
        let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "Cold Down")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
