// Renders Dictum's app icon into an .appiconset (or a single PNG preview).
// Usage: swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset [style]
//        swift Scripts/make-icon.swift preview.png <style>        (one 1024 px PNG)
// Styles: pill (default), aurora, monogram.
import AppKit

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let style = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "pill"

/// Apple-style continuous-corner squircle (superellipse) on the 1024 icon grid.
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, cx = rect.midX, cy = rect.midY
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / exponent), c)
        let y = cy + b * copysign(pow(abs(s), 2 / exponent), s)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func gradient(_ colors: [NSColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray,
               locations: locations)!
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Centre-weighted waveform bars, like the recording window.
func bars(_ ctx: CGContext, centre: CGPoint, height: CGFloat, width: CGFloat, gap: CGFloat,
          heights: [CGFloat], colour: (Int) -> CGColor) {
    let total = CGFloat(heights.count) * width + CGFloat(heights.count - 1) * gap
    var x = centre.x - total / 2
    for (index, h) in heights.enumerated() {
        let rect = CGRect(x: x, y: centre.y - height * h / 2, width: width, height: height * h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        ctx.setFillColor(colour(index))
        ctx.fillPath()
        x += width + gap
    }
}

func drawIcon(_ ctx: CGContext) {
    let shape = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    switch style {
    case "aurora":
        ctx.drawLinearGradient(gradient([rgb(0x24252C), rgb(0x07070A)]), start: CGPoint(x: 512, y: 924),
                               end: CGPoint(x: 512, y: 100), options: [])
        let palette = [rgb(0x4DD9FF), rgb(0x6F73FF), rgb(0xC45CF2), rgb(0xFF6699), rgb(0xFFB24D)]
        let heights: [CGFloat] = [0.22, 0.4, 0.62, 0.86, 1.0, 0.84, 0.6, 0.38, 0.2]
        bars(ctx, centre: CGPoint(x: 512, y: 512), height: 470, width: 46, gap: 26, heights: heights) { index in
            let t = CGFloat(index) / CGFloat(heights.count - 1) * CGFloat(palette.count - 1)
            let i = min(Int(t), palette.count - 2)
            return (palette[i].blended(withFraction: t - CGFloat(i), of: palette[i + 1]) ?? palette[i]).cgColor
        }

    case "monogram":
        ctx.drawLinearGradient(gradient([rgb(0xFF7A45), rgb(0xF0386B), rgb(0x8B3DFF)], [0, 0.55, 1]),
                               start: CGPoint(x: 160, y: 900), end: CGPoint(x: 880, y: 120), options: [])
        // A bold "D" whose bowl is a waveform.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 300, y: 270, width: 64, height: 484), cornerWidth: 32, cornerHeight: 32,
                           transform: nil))
        ctx.fillPath()
        let heights: [CGFloat] = [0.98, 0.94, 0.86, 0.74, 0.56, 0.32]
        var x: CGFloat = 400
        for h in heights {
            let height = 484 * h
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 512 - height / 2, width: 46, height: height),
                               cornerWidth: 23, cornerHeight: 23, transform: nil))
            ctx.fillPath()
            x += 62
        }

    default:  // "pill": the sleeping/recording capsule on a deep, glowing gradient
        ctx.drawLinearGradient(gradient([rgb(0x5B6CFF), rgb(0x7B3FE4), rgb(0x1A1033)], [0, 0.45, 1]),
                               start: CGPoint(x: 220, y: 924), end: CGPoint(x: 820, y: 100), options: [])
        ctx.drawRadialGradient(gradient([NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)]),
                               startCenter: CGPoint(x: 330, y: 820), startRadius: 0,
                               endCenter: CGPoint(x: 330, y: 820), endRadius: 520, options: [])
        let capsule = CGRect(x: 182, y: 382, width: 660, height: 260)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.addPath(CGPath(roundedRect: capsule, cornerWidth: 130, cornerHeight: 130, transform: nil))
        ctx.setFillColor(rgb(0x050507).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        // Glassy rim along the top of the capsule.
        ctx.addPath(CGPath(roundedRect: capsule.insetBy(dx: 3, dy: 3), cornerWidth: 127, cornerHeight: 127, transform: nil))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(6)
        ctx.strokePath()
        let heights: [CGFloat] = [0.2, 0.42, 0.7, 0.94, 1.0, 0.78, 0.52, 0.3, 0.16]
        bars(ctx, centre: CGPoint(x: 512, y: 512), height: 170, width: 26, gap: 22, heights: heights) { _ in
            NSColor.white.cgColor
        }
    }

    // Hairline highlight along the tile edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if target.pathExtension == "png" {
    try render(pixels: 1024).write(to: target)
    print("wrote", target.path)
    exit(0)
}

try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: target.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: target.appending(path: "Contents.json"))
let catalog = target.deletingLastPathComponent().appending(path: "Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog, atomically: true, encoding: .utf8)
}
print("wrote", target.path)
