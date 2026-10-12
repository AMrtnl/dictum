import AppKit
import QuartzCore

/// While the small window is dragged: a ghost of its shape at each of the six spots it can
/// snap to, on every screen, with the one it would snap to right now lit up.
final class AnchorGuides {
    private var windows: [NSScreen: (NSWindow, [RecordingPanel.Anchor: CAShapeLayer])] = [:]
    private var lit: CAShapeLayer?

    /// - Parameters:
    ///   - surface: the size of the window's visible shape.
    ///   - inset: its gap from the screen edge once snapped.
    init(surface: CGSize, inset: CGFloat, cornerRadius: CGFloat) {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.layer = CALayer()
            view.wantsLayer = true
            window.contentView = view

            var ports: [RecordingPanel.Anchor: CAShapeLayer] = [:]
            let area = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            for anchor in RecordingPanel.Anchor.allCases {
                let x = anchor.isLeft ? area.minX + inset
                    : anchor.isRight ? area.maxX - inset - surface.width
                    : area.midX - surface.width / 2
                let y = anchor.isTop ? area.maxY - inset - surface.height : area.minY + inset
                let port = CAShapeLayer()
                port.frame = CGRect(x: x, y: y, width: surface.width, height: surface.height)
                port.path = CGPath(roundedRect: port.bounds.insetBy(dx: 0.75, dy: 0.75),
                                   cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                port.lineWidth = 1.5
                port.contentsScale = screen.backingScaleFactor
                Self.style(port, lit: false)
                view.layer?.addSublayer(port)
                ports[anchor] = port
            }
            windows[screen] = (window, ports)
        }
    }

    /// Orders the guides in just below `panel`, fading them in.
    func show(below panel: NSWindow) {
        for (window, _) in windows.values {
            window.alphaValue = 0
            window.order(.below, relativeTo: panel.windowNumber)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 1
            }
        }
    }

    func highlight(_ anchor: RecordingPanel.Anchor, on screen: NSScreen) {
        guard let port = windows[screen]?.1[anchor], port !== lit else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        if let lit { Self.style(lit, lit: false) }
        Self.style(port, lit: true)
        CATransaction.commit()
        lit = port
    }

    func close() {
        for (window, _) in windows.values {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    /// Dim and dashed at rest; filled and solid where the window will land.
    private static func style(_ port: CAShapeLayer, lit: Bool) {
        port.fillColor = NSColor.white.withAlphaComponent(lit ? 0.16 : 0.04).cgColor
        port.strokeColor = NSColor.white.withAlphaComponent(lit ? 0.85 : 0.35).cgColor
        port.lineDashPattern = lit ? nil : [5, 4]
        port.shadowColor = NSColor.black.cgColor
        port.shadowOpacity = lit ? 0.35 : 0
        port.shadowRadius = 8
        port.shadowOffset = .zero
    }
}
