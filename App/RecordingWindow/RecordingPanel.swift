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

    let content: RecordingWindowView

    private static let bottomInset: CGFloat = 8
    private var visibilityGeneration = 0
    /// UserDefaults key for where (and how big) the user left this style; nil = fixed and click-through (toasts).
    private let frameKey: String?

    init(content: RecordingWindowView, positionKey: String? = nil) {
        self.content = content
        self.frameKey = positionKey.map { "panelFrame.\($0)" }
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
        ignoresMouseEvents = positionKey == nil
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        visibilityGeneration += 1
        if !isVisible {
            moveToRememberedOrDefaultPosition()
            alphaValue = 0
        }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
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
        if frame != startFrame { rememberFrame() }
    }

    static func resetPositions() {
        for style in RecordingWindowStyle.allCases {
            UserDefaults.standard.removeObject(forKey: "panelFrame.\(style.rawValue)")
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

    /// Where the user last left it if that spot is still on a screen, else bottom-centre
    /// of the screen under the pointer, above the Dock.
    private func moveToRememberedOrDefaultPosition() {
        if let saved = savedFrame {
            let rect = NSRect(origin: saved.origin, size: frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect.insetBy(dx: 40, dy: 20)) }) {
                setFrameOrigin(saved.origin)
                return
            }
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return }
        let area = screen.visibleFrame
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + Self.bottomInset))
    }
}
