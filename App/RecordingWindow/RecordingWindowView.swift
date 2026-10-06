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
        didSet { if anchor != oldValue { withoutAnimation { layoutSurface() } } }
    }
    /// Distance from the window's edge to the surface on the anchored sides (shadow room).
    var edgeMargin: CGFloat { 12 }
    /// The window size this style wants right now; the panel follows it (grow now, shrink later).
    var preferredSize: NSSize { bounds.size }
    var onPreferredSizeChange: (() -> Void)?

    func push(level: Float) {
        levels.removeLast()
        levels.insert(min(max(level, 0), 1), at: 0)
        withoutAnimation { levelsDidChange() }
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { levelsDidChange() }
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
    func layoutSurface() {}
    /// Pointer position over the view (nil when it leaves), for hover effects.
    func hoverChanged(at point: NSPoint?) {}
    func modeDidChange() {}
    func labelsDidChange() {}
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
