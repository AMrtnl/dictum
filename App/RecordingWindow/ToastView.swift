import AppKit
import QuartzCore

/// A short message ("No speech detected") in its own little window, for when the small
/// window isn't there to show it: the large window and the None style.
final class ToastView: RecordingWindowView {
    private static let margin: CGFloat = 12
    private static let maximumWidth: CGFloat = 420
    private let bubble = MessageBubble()

    override var surfaceFrame: CGRect {
        bounds.insetBy(dx: Self.margin, dy: Self.margin)
    }

    init(_ message: String, symbol: String = "exclamationmark.circle.fill") {
        let size = bubble.set(message, symbol: symbol, maximumWidth: Self.maximumWidth)
        super.init(size: NSSize(width: size.width + 2 * Self.margin, height: size.height + 2 * Self.margin),
                   historyLength: 1)
        withoutAnimation {
            bubble.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            bubble.layer.opacity = 1
        }
        layer?.addSublayer(bubble.layer)
    }
}
