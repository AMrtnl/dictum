import AppKit

/// Borderless, non-activating floating panel that hosts a recording window view.
/// It never becomes key or main, so focus stays in the app the text will be
/// pasted into, even while the user moves or resizes it.
final class RecordingPanel: NSPanel {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    /// Screen edge or corner a snapping panel is attached to.
    enum Anchor: String, CaseIterable {
        case topLeft, top, topRight, bottomLeft, bottom, bottomRight

        var isTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isRight: Bool { self == .topRight || self == .bottomRight }

        /// Persisted per style, so the small window comes back where it was snapped.
        static func saved(for style: String) -> Anchor {
            UserDefaults.standard.string(forKey: "panelAnchor.\(style)").flatMap(Anchor.init) ?? .bottom
        }
    }

    let content: RecordingWindowView

    /// Gap between a snapped surface and the screen edge.
    private static let snapInset: CGFloat = 10
    private var visibilityGeneration = 0
    /// UserDefaults key for where (and how big) the user left this style; nil = fixed and click-through (toasts).
    private let frameKey: String?
    private let style: String?
    private var shrinkWork: DispatchWorkItem?
    private var pointerMonitors: [Any] = []

    /// - Parameters:
    ///   - positionKey: the style name; enables dragging and remembers the position.
    ///   - anchor: for click-through panels (toasts), the edge to appear at.
    init(content: RecordingWindowView, positionKey: String? = nil, anchor: Anchor? = nil) {
        self.content = content
        self.frameKey = positionKey.map { "panelFrame.\($0)" }
        self.style = positionKey
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Click-through until the pointer is over the visible window (see followPointer()).
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = positionKey != nil
        // NSApp.hide() (after closing Settings) must not take the indicator with it.
        canHide = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = content

        if content.isResizable, let saved = savedFrame {
            setContentSize(clamped(saved.size))
        }
        if content.snapsToAnchors || anchor != nil {
            content.anchor = anchor ?? positionKey.map(Anchor.saved) ?? .bottom
            content.onPreferredSizeChange = { [weak self] in self?.fitContent() }
            setContentSize(content.preferredSize)
        }
    }

    private var isAnchored: Bool { content.snapsToAnchors || frameKey == nil }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// - Parameter rect: for toasts, the screen rect to centre on (where the large window is).
    func show(centredOn rect: NSRect? = nil) {
        visibilityGeneration += 1
        if let rect {
            setFrameOrigin(NSPoint(x: rect.midX - frame.width / 2, y: rect.midY - frame.height / 2))
            if !isVisible { alphaValue = 0 }
        } else if !isVisible {
            if isAnchored {
                setFrame(anchoredFrame(size: content.preferredSize, on: screenUnderMouse()), display: false)
            } else {
                moveToRememberedOrDefaultPosition()
            }
            alphaValue = 0
        } else if content.snapsToAnchors, let target = screenUnderMouse(), target != screen {
            // Always shown: follow the pointer to the screen being worked on.
            setFrame(anchoredFrame(size: content.preferredSize, on: target), display: true)
        }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        watchPointer(true)
    }

    func hide() {
        visibilityGeneration += 1
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() during the fade-out wins.
                guard let self, self.visibilityGeneration == generation else { return }
                self.orderOut(nil)
                self.watchPointer(false)
                self.content.stopAnimations()
            }
        }
    }

    // MARK: - Moving and resizing

    /// Follows the mouse until it is released: moves the panel, or resizes it from `edges`.
    func track(_ event: NSEvent, resizing edges: Edges, minimum: NSSize, maximum: NSSize) {
        let start = NSEvent.mouseLocation
        let startFrame = frame
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            let dx = now.x - start.x
            let dy = now.y - start.y
            var target = startFrame
            if edges.isEmpty {
                target.origin.x += dx
                target.origin.y += dy
            } else {
                if edges.contains(.right) {
                    target.size.width = min(max(startFrame.width + dx, minimum.width), maximum.width)
                }
                if edges.contains(.left) {
                    target.size.width = min(max(startFrame.width - dx, minimum.width), maximum.width)
                    target.origin.x = startFrame.maxX - target.width
                }
                if edges.contains(.top) {
                    target.size.height = min(max(startFrame.height + dy, minimum.height), maximum.height)
                }
                if edges.contains(.bottom) {
                    target.size.height = min(max(startFrame.height - dy, minimum.height), maximum.height)
                    target.origin.y = startFrame.maxY - target.height
                }
            }
            setFrame(target, display: true)
            if next.type == .leftMouseUp { break }
        }
        defer { followPointer() }
        guard frame != startFrame else { return }
        if content.snapsToAnchors && edges.isEmpty {
            snapToNearestAnchor()
        } else {
            rememberFrame()
        }
    }

    // MARK: - Click-through

    /// While shown, follows the pointer so the window takes the mouse only over its visible
    /// part. Mouse-moved monitors cost nothing while the mouse is still and need no permission.
    private func watchPointer(_ on: Bool) {
        guard frameKey != nil else { return }  // toasts never take the mouse
        if on, pointerMonitors.isEmpty {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.followPointer() }
            }) {
                pointerMonitors.append(global)
            } else {
                ignoresMouseEvents = false  // can't follow the pointer: stay usable rather than click-through
                return
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
                MainActor.assumeIsolated { self?.followPointer() }
                return event
            }) {
                pointerMonitors.append(local)
            }
            followPointer()
        } else if !on {
            pointerMonitors.forEach(NSEvent.removeMonitor)
            pointerMonitors = []
            ignoresMouseEvents = true
        }
    }

    /// Takes the mouse while the pointer is over the visible window; otherwise lets clicks
    /// and hovers through to whatever is underneath.
    private func followPointer() {
        let point = NSEvent.mouseLocation
        let inside = isVisible && content.interactiveFrame.offsetBy(dx: frame.minX, dy: frame.minY).contains(point)
        guard ignoresMouseEvents == inside else { return }
        ignoresMouseEvents = !inside
        let local = content.convert(convertPoint(fromScreen: point), from: nil)
        content.hoverChanged(at: inside ? local : nil)
    }

    // MARK: - Anchoring

    /// Thirds of the screen pick left / centre / right; halves pick top / bottom.
    private func snapToNearestAnchor() {
        let surface = content.surfaceFrame.offsetBy(dx: frame.minX, dy: frame.minY)
        let centre = NSPoint(x: surface.midX, y: surface.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? self.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let top = centre.y > area.midY
        let anchor: Anchor = if centre.x < area.minX + area.width / 3 {
            top ? .topLeft : .bottomLeft
        } else if centre.x > area.maxX - area.width / 3 {
            top ? .topRight : .bottomRight
        } else {
            top ? .top : .bottom
        }
        if let style { UserDefaults.standard.set(anchor.rawValue, forKey: "panelAnchor.\(style)") }
        content.anchor = anchor
        let target = anchoredFrame(size: content.preferredSize, on: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        }
    }

    /// Follows the content's preferred size, keeping the anchored edge still: grows at
    /// once (so a morph animation has room) and shrinks once the animation has played.
    private func fitContent() {
        let target = anchoredFrame(size: content.preferredSize, on: screen ?? screenUnderMouse())
        shrinkWork?.cancel()
        let grown = frame.union(target)
        if grown != frame { setFrame(grown, display: true) }
        guard grown != target else { return }
        let work = DispatchWorkItem { [weak self] in self?.setFrame(target, display: true) }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The frame that puts the content's surface `snapInset` from the chosen screen edge/corner.
    private func anchoredFrame(size: NSSize, on screen: NSScreen?, anchor: Anchor? = nil) -> NSRect {
        guard let area = (screen ?? NSScreen.main)?.visibleFrame else { return NSRect(origin: frame.origin, size: size) }
        let anchor = anchor ?? content.anchor
        let surface = content.surfaceFrame
        let bounds = content.bounds
        let inset = Self.snapInset
        let x = anchor.isLeft ? area.minX + inset - surface.minX
            : anchor.isRight ? area.maxX - inset + (bounds.maxX - surface.maxX) - size.width
            : area.midX - size.width / 2
        let y = anchor.isTop ? area.maxY - inset + (bounds.maxY - surface.maxY) - size.height
            : area.minY + inset - surface.minY
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    static func resetPositions() {
        for style in RecordingWindowStyle.allCases {
            UserDefaults.standard.removeObject(forKey: "panelFrame.\(style.rawValue)")
            UserDefaults.standard.removeObject(forKey: "panelAnchor.\(style.rawValue)")
        }
    }

    private var savedFrame: NSRect? {
        guard let frameKey, let saved = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        return NSRectFromString(saved)
    }

    private func rememberFrame() {
        guard let frameKey else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    private func clamped(_ size: NSSize) -> NSSize {
        let margins = NSSize(width: content.bounds.width - content.surfaceFrame.width,
                             height: content.bounds.height - content.surfaceFrame.height)
        return NSSize(
            width: min(max(size.width, content.minimumSurfaceSize.width + margins.width),
                       content.maximumSurfaceSize.width + margins.width),
            height: min(max(size.height, content.minimumSurfaceSize.height + margins.height),
                        content.maximumSurfaceSize.height + margins.height))
    }

    /// Where the user last left it if that spot is still on a screen; otherwise the corner
    /// or edge the small window is snapped to, so expanding grows out of the same spot.
    private func moveToRememberedOrDefaultPosition() {
        if let saved = savedFrame {
            let rect = NSRect(origin: saved.origin, size: frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect.insetBy(dx: 40, dy: 20)) }) {
                setFrameOrigin(saved.origin)
                return
            }
        }
        let anchor = Anchor.saved(for: RecordingWindowStyle.mini.rawValue)
        setFrame(anchoredFrame(size: frame.size, on: screenUnderMouse(), anchor: anchor), display: false)
    }
}
