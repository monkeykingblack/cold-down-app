// Renders Cold Down's app icon into Sources/ColdDownApp/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift Scripts/generate-app-icon.swift
// The fan is drawn from plain Bézier paths (SF Symbols may not be used in app icons).
import AppKit

let brandBlue = NSColor(srgbRed: 0.11, green: 0.42, blue: 0.93, alpha: 1)

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Sources/ColdDownApp/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int, fanOnly: Bool = false) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with a soft shadow margin.
    let inset = size * 0.0977
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = body.width * 0.2237
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if !fanOnly {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.025, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(squircle); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    if !fanOnly { ctx.addPath(squircle); ctx.clip() }
    // Solid brand blue (no gradient), which also suits a layered Liquid Glass version.
    if !fanOnly {
        ctx.setFillColor(brandBlue.cgColor)
        ctx.fill(body)
    }

    // Fan in the same style as the menu-bar glyph: four broad, rounded, slightly swept blades around a ring hub.
    // Drawn from our own paths (SF Symbols may not be used in app icons).
    let center = CGPoint(x: body.midX, y: body.midY)
    let length = body.width * 0.36          // hub centre → blade tip

    /// One blade pointing along +y in local coordinates, leaning counter-clockwise like the glyph.
    func blade() -> CGPath {
        let path = CGMutablePath()
        let L = length
        path.move(to: CGPoint(x: -L * 0.10, y: L * 0.16))
        // Leading edge sweeps out to a broad, rounded tip that leans left.
        path.addCurve(to: CGPoint(x: -L * 0.58, y: L * 0.78),
                      control1: CGPoint(x: -L * 0.34, y: L * 0.28),
                      control2: CGPoint(x: -L * 0.66, y: L * 0.52))
        path.addCurve(to: CGPoint(x: L * 0.10, y: L * 1.00),
                      control1: CGPoint(x: -L * 0.50, y: L * 1.04),
                      control2: CGPoint(x: -L * 0.14, y: L * 1.08))
        // Trailing edge returns to the hub with a gentle curve.
        path.addCurve(to: CGPoint(x: L * 0.12, y: L * 0.16),
                      control1: CGPoint(x: L * 0.34, y: L * 0.90),
                      control2: CGPoint(x: L * 0.30, y: L * 0.40))
        path.closeSubpath()
        return path
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for i in 0..<4 {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(i) * .pi / 2 + .pi / 4)
        ctx.addPath(blade())
        ctx.fillPath()
        ctx.restoreGState()
    }
    // Ring hub: white disc with a brand-blue hole, like the glyph.
    let hub = length * 0.24
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    let hole = hub * 0.45
    ctx.setFillColor(fanOnly ? NSColor.clear.cgColor : brandBlue.cgColor)
    if fanOnly { ctx.setBlendMode(.clear) }
    ctx.fillEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
    ctx.setBlendMode(.normal)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: iconset.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: iconset.deletingLastPathComponent().appendingPathComponent("Contents.json"))
// Separate transparent fan layer for building a layered (Liquid Glass) icon in Icon Composer.
let design = root.appendingPathComponent("Design/AppIcon")
try FileManager.default.createDirectory(at: design, withIntermediateDirectories: true)
try render(1024, fanOnly: true).write(to: design.appendingPathComponent("fan-layer-1024.png"))
print("Wrote \(images.count) icon images to \(iconset.path) and the fan layer to \(design.path)")
