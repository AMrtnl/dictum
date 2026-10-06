import AppKit
import QuartzCore

/// A short message in the recording window's spot: "No speech detected", etc.
final class ToastView: RecordingWindowView {
    override var surfaceFrame: CGRect {
        bounds.insetBy(dx: Self.margin.left, dy: Self.margin.bottom)
    }

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let height: CGFloat = 34
    private static let margin = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    init(_ message: String, symbol: String = "exclamationmark.circle.fill") {
        let textWidth = min(textSize(message, font: Self.font).width, 420)
        let capsuleSize = CGSize(width: textWidth + 54, height: Self.height)
        super.init(
            size: NSSize(
                width: capsuleSize.width + Self.margin.left + Self.margin.right,
                height: capsuleSize.height + Self.margin.top + Self.margin.bottom
            ),
            historyLength: 1
        )
        let capsule = makeSurface(
            frame: CGRect(origin: CGPoint(x: Self.margin.left, y: Self.margin.bottom), size: capsuleSize),
            cornerRadius: Self.height / 2,
            shadowRadius: 8
        )
        capsule.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(capsule)

        let icon = CALayer()
        icon.frame = CGRect(x: 14, y: (Self.height - 15) / 2, width: 15, height: 15)
        icon.contentsGravity = .resizeAspect
        icon.contents = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white.withAlphaComponent(0.8)]))
            )?
            .layerContents(forContentsScale: 2)
        capsule.addSublayer(icon)

        let label = makeTextLayer(message, font: Self.font, color: .white.withAlphaComponent(0.9),
                                  x: 36, midY: Self.height / 2)
        label.frame.size.width = textWidth
        label.truncationMode = .end
        capsule.addSublayer(label)
    }
}
