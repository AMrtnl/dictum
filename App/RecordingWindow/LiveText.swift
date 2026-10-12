import AppKit
import QuartzCore

/// One line of what is being said, newest words on the right. The last few words of the
/// stretch still being spoken are dimmer (amber in Rewrite): the model may still revise them. Once the text is wider than the line, it glides left as words arrive and the
/// oldest ones fade out under the left edge.
final class LiveTextLine {
    /// Clips the text; its frame is set by the host.
    let layer = CALayer()
    private let text = CATextLayer()
    private let edgeFade = CAGradientLayer()
    private let font: NSFont
    private var string = NSAttributedString()
    private(set) var textWidth: CGFloat = 0

    static let rewriteTint = NSColor(red: 1, green: 0.8, blue: 0.36, alpha: 1)
    /// Older text is dropped past this many characters; it is long gone under the left edge.
    private static let keep = 240
    /// Words at the end of the stretch still being spoken that are drawn dimmer.
    private static let unsettledWords = 3

    init(font: NSFont) {
        self.font = font
        layer.masksToBounds = true
        text.anchorPoint = CGPoint(x: 0, y: 0.5)
        text.contentsScale = 2
        text.truncationMode = .none
        text.isWrapped = false
        layer.addSublayer(text)
        edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
    }

    var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) + 2 }

    /// Updates the words; `final` shows the finished transcript, all solid, with a cross-fade.
    func set(committed: String, tail: String, rewrite: Bool, final: Bool = false) {
        let solid = NSColor.white.withAlphaComponent(0.92)
        let dim = rewrite ? Self.rewriteTint.withAlphaComponent(0.8) : NSColor.white.withAlphaComponent(0.48)
        let joined = [committed, tail].filter { !$0.isEmpty }.joined(separator: " ")
        var head = committed.count
        var shown = joined
        if joined.count > Self.keep {  // drop whole words from the front
            var cut = joined.index(joined.endIndex, offsetBy: -Self.keep)
            if let space = joined[cut...].firstIndex(of: " ") { cut = joined.index(after: space) }
            head -= joined.distance(from: joined.startIndex, to: cut)
            shown = "… " + joined[cut...]
            head += 2
        }
        let attributed = NSMutableAttributedString(string: shown, attributes: [.font: font, .foregroundColor: solid])
        if !final, !tail.isEmpty {
            // Only the last few words: a stretch can be long, and its start rarely changes.
            let tailWords = tail.split(separator: " ")
            let unsettled = tailWords.suffix(Self.unsettledWords).joined(separator: " ").count
            head = max(head, shown.count - unsettled)
            let start = max(0, min(shown.count, head))
            let range = NSRange(shown.index(shown.startIndex, offsetBy: start)..., in: shown)
            attributed.addAttribute(.foregroundColor, value: dim, range: range)
        }
        guard attributed != string else { return }
        let previousWidth = textWidth
        let reworded = attributed.string != string.string
        string = attributed
        textWidth = ceil(attributed.size().width)
        if final, reworded {  // a rewrite: cross-fade to the new words
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            text.add(fade, forKey: "contents")
        }
        withoutAnimation {
            text.string = attributed
            text.bounds = CGRect(x: 0, y: 0, width: textWidth + 2, height: lineHeight)
        }
        if textWidth != previousWidth || final { place(animated: true) }
    }

    func clear() {
        string = NSAttributedString()
        textWidth = 0
        withoutAnimation {
            text.string = nil
            text.removeAllAnimations()
            text.position = CGPoint(x: 0, y: layer.bounds.midY)
            layer.mask = nil
        }
    }

    /// Call after changing `layer.frame`; `animated` keeps a glide in progress going.
    func layout(animated: Bool = false) {
        withoutAnimation { edgeFade.frame = layer.bounds }
        place(animated: animated)
    }

    /// Left-aligned while it fits; past that the newest word sits at the right edge.
    private func place(animated: Bool) {
        let width = layer.bounds.width
        let overflowing = textWidth > width
        let target = CGPoint(x: overflowing ? width - textWidth : 0, y: layer.bounds.midY)
        let from = text.presentation()?.position ?? text.position
        withoutAnimation {
            text.position = target
            if overflowing {
                let fade = min(28, width * 0.15) / max(width, 1)
                edgeFade.locations = [0, NSNumber(value: Double(fade)), 1]
                layer.mask = edgeFade
            } else {
                layer.mask = nil
            }
        }
        guard animated, from != target, layer.superlayer != nil else { return text.removeAnimation(forKey: "glide") }
        let glide = CABasicAnimation(keyPath: "position")
        glide.fromValue = NSValue(point: from)
        glide.toValue = NSValue(point: target)
        glide.duration = 0.45
        glide.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        glide.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        text.add(glide, forKey: "glide")
    }
}
