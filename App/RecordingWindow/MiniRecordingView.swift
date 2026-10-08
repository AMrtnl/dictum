import AppKit
import QuartzCore

/// The small window, superwhisper-style. At rest it sleeps as a thin translucent
/// pill hugging a screen edge or corner; hovering grows it into a toolbar
/// (✦ Rewrite, Home, Expand); while dictating it is a black capsule with a live
/// waveform, and while transcribing a glow runs along a row of dots. Messages
/// ("No speech detected") appear in a bubble beside the pill. Shapes morph with
/// Core Animation, in the window server.
final class MiniRecordingView: RecordingWindowView {
    private enum Visual { case sleep, toolbar, active }

    private struct Button {
        let highlight = CALayer()
        let icon = CALayer()
        var tooltip: () -> String
        var action: () -> Void
    }

    private static let margin: CGFloat = 12
    private static let tooltipZone: CGFloat = 38
    private static let sleepSize = CGSize(width: 56, height: 12)
    private static let toolbarSize = CGSize(width: 150, height: 44)
    private static let activeSize = CGSize(width: 120, height: 34)
    private static let lockedActiveSize = CGSize(width: 138, height: 34)
    private static let buttonSize: CGFloat = 34
    private static let buttonGap: CGFloat = 12
    /// Clear of the capsule's rounded ends, so bars never touch the curve.
    private static let waveformSize = CGSize(width: 84, height: 18)
    private static let messageWidth: CGFloat = 400
    private static let rewriteTint = NSColor(red: 1, green: 0.8, blue: 0.36, alpha: 1)
    private static let tooltipFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private let capsule = CALayer()
    /// Clips the waveform to the capsule's shape (the capsule itself can't clip: it casts the shadow).
    private let clip = CALayer()
    private let hoverPad = CALayer()
    /// Zero-size layers pinned to the capsule's centre: their contents grow from the
    /// middle as the capsule morphs, instead of sliding with its corner.
    private let barRow = CALayer()
    private let buttonRow = CALayer()
    private let waveform: Waveform
    private let dots = ProcessingDots(diameter: 4, spacing: 8)
    private let message = MessageBubble()
    private var messageVisible = false
    /// Red "live" dot shown while recording hands-free.
    private let lockDot = CALayer()
    private var buttons: [Button] = []
    private let tooltip = CALayer()
    private let tooltipLabel = CATextLayer()
    private var visual: Visual = .active
    private var hoveredButton: Int?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var hoverPoll: Timer?

    /// One fixed window size for every state, so morphs are pure layer animation and
    /// the window never resizes under them. Its transparent part lets clicks through.
    private static let windowSize = NSSize(width: max(toolbarSize.width, messageWidth) + 2 * margin,
                                           height: toolbarSize.height + 2 * margin + tooltipZone)

    init(style: WaveformStyle = .conveyor) {
        waveform = style.make(style.metrics(for: .mini))
        super.init(size: Self.windowSize, historyLength: 1)
        // A nearly invisible pad widens the hover target around the thin sleeping pill.
        hoverPad.backgroundColor = NSColor.white.withAlphaComponent(0.004).cgColor
        layer?.addSublayer(hoverPad)

        capsule.borderWidth = 1
        capsule.shadowColor = NSColor.black.cgColor
        capsule.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(capsule)

        clip.masksToBounds = true
        capsule.addSublayer(clip)
        for row in [barRow, buttonRow] { row.bounds = .zero }
        clip.addSublayer(barRow)
        capsule.addSublayer(buttonRow)
        barRow.addSublayer(waveform.layer)
        waveform.layout(in: CGRect(x: -Self.waveformSize.width / 2, y: -Self.waveformSize.height / 2,
                                   width: Self.waveformSize.width, height: Self.waveformSize.height))
        lockDot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        lockDot.cornerRadius = 3
        lockDot.backgroundColor = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1).cgColor
        lockDot.opacity = 0
        barRow.addSublayer(lockDot)
        // Processing: a glow running along a row of dots, in place of the waveform.
        dots.layout(in: CGRect(x: -38, y: -4, width: 76, height: 8))
        barRow.addSublayer(dots.layer)

        buttons = [
            Button(tooltip: { [unowned self] in rewriteOn ? "Rewrite on" : "Rewrite off" },
                   action: { [unowned self] in onToggleRewrite?() }),
            Button(tooltip: { "Open Dictum" }, action: { [unowned self] in onOpenSettings?() }),
            Button(tooltip: { "Expand window" }, action: { [unowned self] in onToggleSize?() }),
        ]
        let symbols = ["sparkle", "waveform", "arrow.up.left.and.arrow.down.right"]
        for (index, (button, symbol)) in zip(buttons, symbols).enumerated() {
            let centre = CGPoint(x: CGFloat(index - 1) * (Self.buttonSize + Self.buttonGap), y: 0)
            button.highlight.bounds = CGRect(x: 0, y: 0, width: Self.buttonSize, height: Self.buttonSize)
            button.highlight.position = centre
            button.highlight.cornerRadius = Self.buttonSize / 2
            button.highlight.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            button.highlight.opacity = 0
            button.icon.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            button.icon.position = centre
            button.icon.contentsGravity = .resizeAspect
            button.icon.contents = Self.symbol(symbol, color: .white)
            buttonRow.addSublayer(button.highlight)
            buttonRow.addSublayer(button.icon)
        }

        tooltip.cornerRadius = 9
        tooltip.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
        tooltip.borderWidth = 1
        tooltip.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        tooltip.opacity = 0
        tooltipLabel.font = Self.tooltipFont
        tooltipLabel.fontSize = Self.tooltipFont.pointSize
        tooltipLabel.foregroundColor = NSColor.white.withAlphaComponent(0.88).cgColor
        tooltipLabel.contentsScale = 2
        tooltip.addSublayer(tooltipLabel)
        layer?.addSublayer(tooltip)
        layer?.addSublayer(message.layer)
        updateRewriteIcon()

        apply(.active, animated: false)
    }

    // MARK: Geometry

    override var snapsToAnchors: Bool { true }
    override var edgeMargin: CGFloat { Self.margin }
    override var surfaceFrame: CGRect { capsule.frame }

    override var preferredSize: NSSize { Self.windowSize }

    private func size(of visual: Visual) -> CGSize {
        switch visual {
        case .sleep: Self.sleepSize
        case .toolbar: Self.toolbarSize
        case .active: isLocked && mode == .recording ? Self.lockedActiveSize : Self.activeSize
        }
    }

    /// The surface hugs the anchored side of the window; any extra room (tooltips) is on the inner side.
    private func anchoredRect(_ size: CGSize) -> CGRect {
        let x = anchor.isLeft ? Self.margin
            : anchor.isRight ? bounds.width - Self.margin - size.width
            : (bounds.width - size.width) / 2
        let y = anchor.isTop ? bounds.height - Self.margin - size.height : Self.margin
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    override func layoutSurface() {
        capsule.frame = anchoredRect(capsule.bounds.size)
        updateShadowPath(capsule)
        clip.frame = capsule.bounds
        clip.cornerRadius = capsule.cornerRadius
        for row in [barRow, buttonRow] { row.position = CGPoint(x: capsule.bounds.midX, y: capsule.bounds.midY) }
        hoverPad.frame = capsule.frame.insetBy(dx: -10, dy: -9)
        if hoveredButton != nil { positionTooltip() }
        if messageVisible { message.layer.position = messagePosition(for: capsule.frame) }
    }

    /// Snapped to another edge: glide the shape to that side of the window.
    override func anchorDidChange() {
        apply(visual, animated: window?.isVisible == true)
    }

    // MARK: States

    private func apply(_ next: Visual, animated: Bool) {
        visual = next
        let size = size(of: next)
        let frame = anchoredRect(size)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        // Geometry: one spring for shape, corners, shadow and the centred rows, set
        // explicitly so every property moves on the same curve.
        withoutAnimation {
            spring(capsule, "bounds", NSValue(rect: CGRect(origin: .zero, size: size)), animated)
            spring(capsule, "position", NSValue(point: CGPoint(x: frame.midX, y: frame.midY)), animated)
            spring(capsule, "cornerRadius", size.height / 2, animated)
            spring(capsule, "shadowPath",
                   CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: size.height / 2,
                          cornerHeight: size.height / 2, transform: nil), animated)
            spring(clip, "bounds", NSValue(rect: CGRect(origin: .zero, size: size)), animated)
            spring(clip, "position", NSValue(point: centre), animated)
            spring(clip, "cornerRadius", size.height / 2, animated)
            for row in [barRow, buttonRow] { spring(row, "position", NSValue(point: centre), animated) }
            spring(buttonRow, "transform", CATransform3DMakeScale(next == .toolbar ? 1 : 0.7, next == .toolbar ? 1 : 0.7, 1), animated)
            let locked = next == .active && isLocked && mode == .recording
            spring(waveform.layer, "transform", CATransform3DMakeTranslation(locked ? 8 : 0, 0, 0), animated)
            spring(lockDot, "position", NSValue(point: CGPoint(x: -size.width / 2 + 15, y: 0)), animated)
            hoverPad.frame = frame.insetBy(dx: -10, dy: -9)
            if messageVisible { spring(message.layer, "position", NSValue(point: messagePosition(for: frame)), animated) }
        }

        // Colours and fades: eased, quick; contents fade in a beat after the shape starts growing.
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.22 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setDisableActions(!animated)
        switch next {
        case .sleep:
            // Translucent and outlined, like superwhisper's resting pill.
            capsule.backgroundColor = NSColor(white: 0.1, alpha: 0.62).cgColor
            capsule.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            capsule.shadowOpacity = 0.18
            capsule.shadowRadius = 3
        case .toolbar:
            capsule.backgroundColor = NSColor(white: 0.04, alpha: 0.9).cgColor
            capsule.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            capsule.shadowOpacity = 0.35
            capsule.shadowRadius = 10
        case .active:
            capsule.backgroundColor = NSColor.black.cgColor
            capsule.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            capsule.shadowOpacity = 0.35
            capsule.shadowRadius = 8
        }
        fade(barRow, to: next == .active ? 1 : 0, animated: animated)
        updateLockDot(visible: next == .active && isLocked && mode == .recording)
        fade(buttonRow, to: next == .toolbar ? 1 : 0, animated: animated)
        if next == .toolbar, messageVisible { hideMessage() }  // the toolbar's tooltips take that spot
        if next != .toolbar {
            hoveredButton = nil
            tooltip.opacity = 0
        }
        CATransaction.commit()
        updateButtonHighlights()

        hoverPoll?.invalidate()
        hoverPoll = nil
        if next == .toolbar { startHoverPoll() }
    }

    /// Sets `value` and, if animated, springs to it from wherever the layer is on screen
    /// right now — so an interrupted morph (hover off mid-grow) reverses smoothly.
    private func spring(_ layer: CALayer, _ keyPath: String, _ value: Any, _ animated: Bool) {
        let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        layer.setValue(value, forKeyPath: keyPath)
        guard animated else {
            layer.removeAnimation(forKey: keyPath)
            return
        }
        let animation = CASpringAnimation(perceptualDuration: 0.42, bounce: 0.16)
        animation.keyPath = keyPath
        animation.fromValue = from
        animation.toValue = value
        layer.add(animation, forKey: keyPath)
    }

    /// Appearing contents wait a beat for the shape; disappearing ones go at once.
    private func fade(_ layer: CALayer, to opacity: Float, animated: Bool) {
        guard animated, opacity > 0, layer.opacity == 0 else {
            layer.opacity = opacity
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = opacity
        animation.duration = 0.2
        animation.beginTime = CACurrentMediaTime() + 0.08
        animation.fillMode = .backwards
        layer.add(animation, forKey: "fadeIn")
        withoutAnimation { layer.opacity = opacity }
    }

    override func modeDidChange() {
        expandWork?.cancel()
        expandWork = nil
        collapseWork?.cancel()
        collapseWork = nil
        switch mode {
        case .idle:
            stopAnimations()
            apply(.sleep, animated: window?.isVisible == true)
        case .recording:
            stopAnimations()
            apply(.active, animated: window?.isVisible == true)
        case .processing:
            apply(.active, animated: window?.isVisible == true)
            startProcessing()
        }
    }

    override func labelsDidChange() {
        updateRewriteIcon()
        if hoveredButton != nil { positionTooltip() }
    }

    /// ✦ is amber when Rewrite is on, dimmed white when it's off.
    private func updateRewriteIcon() {
        withoutAnimation {
            buttons[0].icon.contents = Self.symbol("sparkle", color: rewriteOn ? Self.rewriteTint : .white)
            buttons[0].icon.opacity = rewriteOn ? 1 : 0.5
        }
    }

    // MARK: Messages

    /// Shows a short message in a bubble on the inner side of the pill (above it when the
    /// pill sits at the bottom of the screen), whatever the pill is doing.
    func showMessage(_ text: String, symbol: String?) {
        let size = message.set(text, symbol: symbol, maximumWidth: Self.messageWidth)
        let wasVisible = messageVisible
        messageVisible = true
        withoutAnimation {
            message.layer.bounds = CGRect(origin: .zero, size: size)
            message.layer.position = messagePosition(for: capsule.frame)
        }
        if !wasVisible || message.layer.opacity < 1 { message.setVisible(true, rise: anchor.isTop ? -1 : 1) }
    }

    func hideMessage() {
        guard messageVisible else { return }
        messageVisible = false
        message.setVisible(false, rise: 0)
    }

    private func messagePosition(for surface: CGRect) -> CGPoint {
        let size = message.layer.bounds.size
        let x = min(max(surface.midX, size.width / 2 + 4), bounds.width - size.width / 2 - 4)
        let y = anchor.isTop ? surface.minY - 8 - size.height / 2 : surface.maxY + 8 + size.height / 2
        return CGPoint(x: x, y: y)
    }

    // MARK: Hover

    private var hoverRect: CGRect {
        visual == .sleep ? capsule.frame.insetBy(dx: -10, dy: -9) : capsule.frame.insetBy(dx: -6, dy: -6)
    }

    override func hoverChanged(at point: NSPoint?) {
        guard mode == .idle else { return }
        if let point, hoverRect.contains(point) {
            collapseWork?.cancel()
            collapseWork = nil
            if visual == .sleep, expandWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, mode == .idle else { return }
                    expandWork = nil
                    apply(.toolbar, animated: true)
                }
                expandWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
            setHoveredButton(visual == .toolbar ? buttonIndex(at: point) : nil)
        } else {
            expandWork?.cancel()
            expandWork = nil
            setHoveredButton(nil)
            guard visual == .toolbar, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                collapseWork = nil
                if mode == .idle { apply(.sleep, animated: true) }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    /// Exit events can be missed over the transparent part of the window, so while the
    /// toolbar is open the pointer is also checked a few times a second.
    private func startHoverPoll() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.hoverChanged(at: self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        hoverPoll = timer
    }

    private func buttonIndex(at point: NSPoint) -> Int? {
        buttons.firstIndex { button in
            buttonRow.convert(button.highlight.frame, to: layer).insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func setHoveredButton(_ index: Int?) {
        guard index != hoveredButton else { return }
        hoveredButton = index
        updateButtonHighlights()
        if index == nil {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            tooltip.opacity = 0
            CATransaction.commit()
        } else {
            positionTooltip()
        }
    }

    private func updateButtonHighlights() {
        withoutAnimation {
            for (index, button) in buttons.enumerated() {
                button.highlight.opacity = visual == .toolbar && hoveredButton == index ? 1 : 0
            }
        }
    }

    /// Tooltip on the side away from the screen edge, centred on the hovered button.
    private func positionTooltip() {
        guard let index = hoveredButton else { return }
        let text = buttons[index].tooltip()
        let textSize = textSize(text, font: Self.tooltipFont)
        let size = CGSize(width: textSize.width + 24, height: textSize.height + 12)
        let buttonFrame = buttonRow.convert(buttons[index].highlight.frame, to: layer)
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, 4), bounds.width - size.width - 4)
        let target = capsule.convert(capsule.bounds, to: layer)
        let y = anchor.isTop ? target.minY - 8 - size.height : target.maxY + 8
        withoutAnimation {
            tooltipLabel.string = text
            tooltipLabel.frame = CGRect(x: 12, y: 6, width: textSize.width, height: textSize.height)
            tooltip.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        tooltip.opacity = 1
        CATransaction.commit()
    }

    override func control(at point: NSPoint) -> (() -> Void)? {
        guard visual == .toolbar, let index = buttonIndex(at: point) else { return nil }
        return buttons[index].action
    }

    // MARK: Waveform

    override func lockDidChange() {
        guard visual == .active else { return }
        apply(.active, animated: window?.isVisible == true)
    }

    /// The live dot breathes slowly (30 fps cap) while hands-free.
    private func updateLockDot(visible: Bool) {
        if visible, lockDot.animation(forKey: "breathe") == nil {
            lockDot.opacity = 1
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.35
            breathe.duration = 0.9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            lockDot.add(breathe, forKey: "breathe")
        } else if !visible {
            lockDot.removeAnimation(forKey: "breathe")
            lockDot.opacity = 0
        }
    }

    override func levelPushed(_ level: Float) {
        guard visual == .active, mode == .recording else { return }
        waveform.push(level, animated: window?.isVisible == true)
    }

    override func resetLevelsDidHappen() {
        waveform.reset()
    }

    /// Processing: the waveform hands over to a glow running along a row of dots.
    private func startProcessing() {
        let visible = window?.isVisible == true
        CATransaction.begin()
        CATransaction.setAnimationDuration(visible ? 0.18 : 0)
        CATransaction.setDisableActions(!visible)
        waveform.layer.opacity = 0
        CATransaction.commit()
        dots.start()
        if visible {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            dots.layer.add(fade, forKey: "fadeIn")
        }
    }

    override func stopAnimations() {
        dots.stop()
        withoutAnimation {
            waveform.reset()
            waveform.layer.opacity = 1
        }
    }

    private static func symbol(_ name: String, color: NSColor) -> Any? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            )?
            .layerContents(forContentsScale: 2)
    }
}
