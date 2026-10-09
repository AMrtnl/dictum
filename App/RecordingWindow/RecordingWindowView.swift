import AppKit
import QuartzCore

enum RecordingWindowStyle: String, CaseIterable, Identifiable {
    case classic, mini, none

    static let defaultsKey = "recordingWindowStyle"

    static var current: Self {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init) ?? .mini
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .mini: "Mini"
        case .none: "None"
        }
    }

    var summary: String {
        switch self {
        case .classic: "A large card with the waveform and key hints. Move it anywhere and resize it from its edges; ↘↖ switches to Mini."
        case .mini: "A small pill that snaps to a screen edge or corner. At rest it sleeps as a thin line; hover it for Rewrite, Home and Expand."
        case .none: "No window. The start and stop sounds tell you when Dictum is listening."
        }
    }
}

/// Base for the recording window styles. Everything is drawn with Core Animation
/// layers: the window server composites them, so a level update costs a few
/// dozen property writes in-process. (A SwiftUI version of the pill pulled in
/// ~130 MB of Metal buffers and 4–8 % CPU.)
class RecordingWindowView: NSView {
    /// `idle` is the resting state shown when "Always show" is on.
    enum Mode { case idle, recording, processing }

    var mode: Mode = .recording {
        didSet { if mode != oldValue { modeDidChange() } }
    }

    /// Hands-free recording: the shortcut was tapped, not held.
    var isLocked = false {
        didSet { if isLocked != oldValue { lockDidChange() } }
    }

    /// Whether Rewrite is the current default mode (Mini's ✦ button shows it).
    var rewriteOn = false {
        didSet { if rewriteOn != oldValue { labelsDidChange() } }
    }

    /// Text for styles that have room for it: the mode while recording, the step while processing.
    var modeTitle = "Dictation" {
        didSet { if modeTitle != oldValue { labelsDidChange() } }
    }
    var processingLabel = "Transcribing…" {
        didSet { if processingLabel != oldValue { labelsDidChange() } }
    }

    /// Newest first. Styles read it centre-out, so new sound appears in the
    /// middle and ripples toward the edges.
    private(set) var levels: [Float]

    init(size: NSSize, historyLength: Int) {
        levels = [Float](repeating: 0, count: historyLength)
        super.init(frame: NSRect(origin: .zero, size: size))
        layer = CALayer()  // layer-hosting: the subclass owns the whole tree
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Set by the controller for the window's own controls.
    var onToggleSize: (() -> Void)?
    var onToggleRewrite: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: Anchoring (styles that snap to screen edges)

    /// Whether the panel snaps this style to a screen edge or corner after a drag.
    var snapsToAnchors: Bool { false }
    /// Which screen edge/corner the panel is attached to; the surface hugs that side.
    var anchor: RecordingPanel.Anchor = .bottom {
        didSet { if anchor != oldValue { anchorDidChange() } }
    }

    func anchorDidChange() {
        withoutAnimation { layoutSurface() }
    }
    /// Distance from the window's edge to the surface on the anchored sides (shadow room).
    var edgeMargin: CGFloat { 12 }
    /// The window size this style wants right now; the panel follows it (grow now, shrink later).
    var preferredSize: NSSize { bounds.size }
    var onPreferredSizeChange: (() -> Void)?

    func push(level: Float) {
        let level = min(max(level, 0), 1)
        levels.removeLast()
        levels.insert(level, at: 0)
        withoutAnimation { levelsDidChange() }
        levelPushed(level)
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { levelsDidChange() }
        resetLevelsDidHappen()
    }

    /// For styles whose bar count follows their width; keeps the newest samples.
    func setHistoryLength(_ length: Int) {
        guard length != levels.count else { return }
        levels = Array(levels.prefix(length)) + [Float](repeating: 0, count: max(0, length - levels.count))
    }

    // MARK: Geometry

    /// The visible card or capsule, in view coordinates; the rest is shadow margin.
    var surfaceFrame: CGRect { bounds }
    /// Whether dragging the surface's edges resizes the window.
    var isResizable: Bool { false }
    /// The only part of the window that takes the mouse; clicks anywhere else in the
    /// (mostly transparent) window go to the app underneath. The surface, plus the resize band.
    var interactiveFrame: CGRect { surfaceFrame.insetBy(dx: isResizable ? -5 : -2, dy: isResizable ? -5 : -2) }
    var minimumSurfaceSize: CGSize { surfaceFrame.size }
    var maximumSurfaceSize: CGSize { surfaceFrame.size }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        withoutAnimation {
            layer?.frame = bounds
            layoutSurface()
        }
    }

    // MARK: Mouse: drag to move, drag an edge to resize, click controls

    /// A clickable control under `point` (view coordinates), if any.
    func control(at point: NSPoint) -> (() -> Void)? { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let action = control(at: point) {
            action()
            return
        }
        guard let panel = window as? RecordingPanel else { return }
        let margins = CGSize(width: bounds.width - surfaceFrame.width, height: bounds.height - surfaceFrame.height)
        panel.track(
            event,
            resizing: resizeEdges(at: point),
            minimum: NSSize(width: minimumSurfaceSize.width + margins.width, height: minimumSurfaceSize.height + margins.height),
            maximum: NSSize(width: maximumSurfaceSize.width + margins.width, height: maximumSurfaceSize.height + margins.height)
        )
    }

    /// Which surface edges are under `point`: a band 6 pt inside to 5 pt outside each edge.
    func resizeEdges(at point: NSPoint) -> RecordingPanel.Edges {
        guard isResizable else { return [] }
        let surface = surfaceFrame
        guard surface.insetBy(dx: -5, dy: -5).contains(point) else { return [] }
        var edges: RecordingPanel.Edges = []
        if point.x <= surface.minX + 6 { edges.insert(.left) }
        if point.x >= surface.maxX - 6 { edges.insert(.right) }
        if point.y <= surface.minY + 6 { edges.insert(.bottom) }
        if point.y >= surface.maxY - 6 { edges.insert(.top) }
        return edges
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        Self.cursor(for: resizeEdges(at: point)).set()
        hoverChanged(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        hoverChanged(at: nil)
    }

    private static func cursor(for edges: RecordingPanel.Edges) -> NSCursor {
        if edges.isEmpty { return .arrow }
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch edges {
            case [.top, .left]: .topLeft
            case [.top, .right]: .topRight
            case [.bottom, .left]: .bottomLeft
            case [.bottom, .right]: .bottomRight
            case [.top]: .top
            case [.bottom]: .bottom
            case [.left]: .left
            default: .right
            }
            return .frameResize(position: position, directions: .all)
        }
        if edges == [.left] || edges == [.right] { return .resizeLeftRight }
        if edges == [.top] || edges == [.bottom] { return .resizeUpDown }
        return .crosshair
    }

    // MARK: Subclass hooks

    func levelsDidChange() {}
    /// The newest level, for styles that draw with a `Waveform`.
    func levelPushed(_ level: Float) {}
    func resetLevelsDidHappen() {}
    func layoutSurface() {}
    /// Pointer position over the view (nil when it leaves), for hover effects.
    func hoverChanged(at point: NSPoint?) {}
    func modeDidChange() {}
    func labelsDidChange() {}
    func lockDidChange() {}
    func stopAnimations() {}

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        func apply(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.sublayers?.forEach(apply)
        }
        layer.map(apply)
    }
}

// MARK: - Layer helpers

func withoutAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

func textSize(_ string: String, font: NSFont) -> CGSize {
    let size = (string as NSString).size(withAttributes: [.font: font])
    return CGSize(width: ceil(size.width), height: ceil(size.height))
}

/// A one-line text layer sized to its string, vertically centred on `midY`.
func makeTextLayer(_ string: String, font: NSFont, color: NSColor, x: CGFloat, midY: CGFloat) -> CATextLayer {
    let label = CATextLayer()
    label.string = string
    label.font = font
    label.fontSize = font.pointSize
    label.foregroundColor = color.cgColor
    label.contentsScale = 2
    let size = textSize(string, font: font)
    label.frame = CGRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height)
    return label
}

/// A rounded key cap ("⌥", "Space", "esc") whose left edge is at `x`.
func makeKeycap(_ string: String, x: CGFloat, midY: CGFloat) -> CALayer {
    let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    let height: CGFloat = 22
    let width = max(height, textSize(string, font: font).width + 14)
    let cap = CALayer()
    cap.frame = CGRect(x: x, y: midY - height / 2, width: width, height: height)
    cap.cornerRadius = 5
    cap.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
    let label = makeTextLayer(string, font: font, color: .white.withAlphaComponent(0.88), x: 0, midY: height / 2)
    label.frame.origin.x = (width - label.frame.width) / 2
    cap.addSublayer(label)
    return cap
}

/// A rotating arc; the rotation runs in the window server, capped at 30 fps.
func makeSpinner(diameter: CGFloat, color: NSColor) -> CAShapeLayer {
    let spinner = CAShapeLayer()
    spinner.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    spinner.path = CGPath(ellipseIn: spinner.bounds.insetBy(dx: 1, dy: 1), transform: nil)
    spinner.fillColor = nil
    spinner.strokeColor = color.cgColor
    spinner.lineWidth = 1.5
    spinner.lineCap = .round
    spinner.strokeEnd = 0.75
    return spinner
}

func startSpinning(_ layer: CALayer) {
    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
    spin.fromValue = 0
    spin.toValue = -2 * Double.pi
    spin.duration = 0.9
    spin.repeatCount = .infinity
    spin.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
    layer.add(spin, forKey: "spin")
}

/// Dark floating surface with the shadow precomputed from its shape.
func makeSurface(frame: CGRect, cornerRadius: CGFloat, shadowRadius: CGFloat) -> CALayer {
    let surface = CALayer()
    surface.frame = frame
    surface.cornerRadius = cornerRadius
    surface.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
    surface.borderWidth = 1
    surface.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    surface.shadowColor = NSColor.black.cgColor
    surface.shadowOpacity = 0.35
    surface.shadowRadius = shadowRadius
    surface.shadowOffset = CGSize(width: 0, height: -shadowRadius / 3)
    updateShadowPath(surface)
    return surface
}

func updateShadowPath(_ surface: CALayer) {
    surface.shadowPath = CGPath(
        roundedRect: surface.bounds, cornerWidth: surface.cornerRadius, cornerHeight: surface.cornerRadius, transform: nil
    )
}

/// "Working on it": a row of dim dots with a glow travelling across them, left to right.
/// Each dot runs its own staggered keyframe animation in the window server (30 fps cap).
final class ProcessingDots {
    let layer = CALayer()
    private var dots: [CALayer] = []
    private let diameter: CGFloat
    private let spacing: CGFloat

    init(diameter: CGFloat, spacing: CGFloat) {
        self.diameter = diameter
        self.spacing = spacing
        layer.opacity = 0
    }

    /// Fills `rect` (the parent's coordinates) with as many dots as fit, centred.
    func layout(in rect: CGRect, maximumCount: Int = 64) {
        let count = max(3, min(maximumCount, Int((rect.width + spacing - diameter) / spacing)))
        withoutAnimation {
            layer.frame = rect
            if dots.count != count {
                dots.forEach { $0.removeFromSuperlayer() }
                dots = (0..<count).map { _ in
                    let dot = CALayer()
                    dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                    dot.cornerRadius = diameter / 2
                    dot.backgroundColor = NSColor.white.cgColor
                    dot.opacity = 0.22
                    layer.addSublayer(dot)
                    return dot
                }
            }
            let width = CGFloat(count - 1) * spacing
            for (index, dot) in dots.enumerated() {
                dot.position = CGPoint(x: rect.width / 2 - width / 2 + CGFloat(index) * spacing, y: rect.height / 2)
            }
        }
        if layer.opacity > 0 { start() }
    }

    func start() {
        layer.opacity = 1
        let now = CACurrentMediaTime()
        // The glow crosses the row in ~0.9 s whatever its length, then the row rests briefly.
        let travel = 0.9
        let period = travel + 0.45
        for (index, dot) in dots.enumerated() {
            dot.removeAllAnimations()
            let offset = travel * Double(index) / Double(max(1, dots.count - 1))
            let glow = CAKeyframeAnimation(keyPath: "opacity")
            glow.values = [0.22, 1, 0.22, 0.22]
            glow.keyTimes = [0, 0.16, 0.42, 1]
            glow.duration = period
            glow.repeatCount = .infinity
            glow.beginTime = now + offset
            glow.fillMode = .backwards
            glow.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            dot.add(glow, forKey: "glow")
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = [1, 1.35, 1, 1]
            grow.keyTimes = glow.keyTimes
            grow.duration = period
            grow.repeatCount = .infinity
            grow.beginTime = glow.beginTime
            grow.fillMode = .backwards
            grow.preferredFrameRateRange = glow.preferredFrameRateRange
            dot.add(grow, forKey: "grow")
        }
    }

    func stop() {
        withoutAnimation {
            layer.opacity = 0
            dots.forEach { $0.removeAllAnimations() }
        }
    }
}

/// A small dark bubble with an icon and one line of text: messages next to the pill.
final class MessageBubble {
    let layer = CALayer()
    private let icon = CALayer()
    private let label = CATextLayer()
    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let height: CGFloat = 30

    init() {
        layer.cornerRadius = Self.height / 2
        layer.backgroundColor = NSColor(white: 0.09, alpha: 0.96).cgColor
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.opacity = 0
        icon.contentsGravity = .resizeAspect
        layer.addSublayer(icon)
        label.font = Self.font
        label.fontSize = Self.font.pointSize
        label.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        label.contentsScale = 2
        label.truncationMode = .end
        layer.addSublayer(label)
    }

    /// Sets the message and returns the bubble's size (at most `maximumWidth` wide).
    func set(_ text: String, symbol: String?, maximumWidth: CGFloat) -> CGSize {
        let iconWidth: CGFloat = symbol == nil ? 0 : 22
        let textWidth = min(textSize(text, font: Self.font).width, maximumWidth - 28 - iconWidth)
        let size = CGSize(width: textWidth + 28 + iconWidth, height: Self.height)
        withoutAnimation {
            icon.contents = symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                    .withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                            .applying(NSImage.SymbolConfiguration(paletteColors: [.white.withAlphaComponent(0.75)]))
                    )?
                    .layerContents(forContentsScale: 2)
            }
            icon.frame = CGRect(x: 13, y: (Self.height - 14) / 2, width: 15, height: 14)
            label.string = text
            let textHeight = textSize(text, font: Self.font).height
            label.frame = CGRect(x: 14 + iconWidth, y: (Self.height - textHeight) / 2, width: textWidth, height: textHeight)
            layer.bounds = CGRect(origin: .zero, size: size)
            layer.shadowPath = CGPath(roundedRect: layer.bounds, cornerWidth: Self.height / 2,
                                      cornerHeight: Self.height / 2, transform: nil)
        }
        return size
    }

    /// Fades in with a small lift toward `rise` (+1 up, −1 down); fades out in place.
    func setVisible(_ visible: Bool, rise: CGFloat) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = visible ? 1 : 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = layer.opacity
        fade.duration = visible ? 0.22 : 0.16
        layer.add(fade, forKey: "fade")
        guard visible, from < 0.05 else { return }
        let lift = CASpringAnimation(perceptualDuration: 0.38, bounce: 0.2)
        lift.keyPath = "transform.translation.y"
        lift.fromValue = -6 * rise
        lift.toValue = 0
        layer.add(lift, forKey: "lift")
    }
}
