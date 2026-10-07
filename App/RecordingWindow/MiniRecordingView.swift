import AppKit
import QuartzCore

/// The small window, superwhisper-style. At rest it sleeps as a thin translucent
/// pill hugging a screen edge or corner; hovering grows it into a toolbar
/// (✦ Rewrite, Settings, Expand); while dictating it is a black capsule with a
/// centred, mirrored waveform. Shapes morph with Core Animation, in the window server.
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
    private static let activeSize = CGSize(width: 86, height: 30)
    private static let buttonSize: CGFloat = 34
    private static let buttonGap: CGFloat = 12
    private static let barCount = 11
    private static let barWidth: CGFloat = 2.5
    private static let barStep: CGFloat = 5
    private static let maxBarHeight: CGFloat = 16
    private static let tooltipFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private let capsule = CALayer()
    private let hoverPad = CALayer()
    /// Zero-size layers pinned to the capsule's centre: their contents grow from the
    /// middle as the capsule morphs, instead of sliding with its corner.
    private let barRow = CALayer()
    private let buttonRow = CALayer()
    private let bars = (0..<barCount).map { _ in CALayer() }
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
    private static let windowSize = NSSize(width: toolbarSize.width + 2 * margin,
                                           height: toolbarSize.height + 2 * margin + tooltipZone)

    init() {
        super.init(size: Self.windowSize, historyLength: Self.barCount / 2 + 1)
        // A nearly invisible pad widens the hover target around the thin sleeping pill.
        hoverPad.backgroundColor = NSColor.white.withAlphaComponent(0.004).cgColor
        layer?.addSublayer(hoverPad)

        capsule.borderWidth = 1
        capsule.shadowColor = NSColor.black.cgColor
        capsule.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(capsule)

        for row in [barRow, buttonRow] {
            row.bounds = .zero
            capsule.addSublayer(row)
        }
        let span = CGFloat(Self.barCount - 1) * Self.barStep + Self.barWidth
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            bar.position = CGPoint(x: -span / 2 + CGFloat(index) * Self.barStep + Self.barWidth / 2, y: 0)
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
            barRow.addSublayer(bar)
        }

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
            button.icon.contents = Self.symbol(symbol)
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

        apply(.active, animated: false)
    }

    // MARK: Geometry

    override var snapsToAnchors: Bool { true }
    override var edgeMargin: CGFloat { Self.margin }
    override var surfaceFrame: CGRect { capsule.frame }

    override var preferredSize: NSSize { Self.windowSize }

    private static func size(of visual: Visual) -> CGSize {
        switch visual {
        case .sleep: sleepSize
        case .toolbar: toolbarSize
        case .active: activeSize
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
        for row in [barRow, buttonRow] { row.position = CGPoint(x: capsule.bounds.midX, y: capsule.bounds.midY) }
        hoverPad.frame = capsule.frame.insetBy(dx: -10, dy: -9)
        if hoveredButton != nil { positionTooltip() }
    }

    /// Snapped to another edge: glide the shape to that side of the window.
    override func anchorDidChange() {
        apply(visual, animated: window?.isVisible == true)
    }

    // MARK: States

    private func apply(_ next: Visual, animated: Bool) {
        visual = next
        let size = Self.size(of: next)
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
            for row in [barRow, buttonRow] { spring(row, "position", NSValue(point: centre), animated) }
            spring(buttonRow, "transform", CATransform3DMakeScale(next == .toolbar ? 1 : 0.7, next == .toolbar ? 1 : 0.7, 1), animated)
            hoverPad.frame = frame.insetBy(dx: -10, dy: -9)
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
        fade(buttonRow, to: next == .toolbar ? 1 : 0, animated: animated)
        for (index, button) in buttons.enumerated() {
            button.icon.opacity = iconOpacity(index)
        }
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
            withoutAnimation { levelsDidChange() }
        case .processing:
            apply(.active, animated: false)
            startWave()
        }
    }

    override func labelsDidChange() {
        withoutAnimation { buttons[0].icon.opacity = iconOpacity(0) }
        if hoveredButton != nil { positionTooltip() }
    }

    private func iconOpacity(_ index: Int) -> Float {
        index == 0 && !rewriteOn ? 0.5 : 1
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

    override func levelsDidChange() {
        guard visual == .active, mode == .recording else { return }
        let half = Self.barCount / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - half)
            let taper = 1 - 0.55 * pow(CGFloat(distance) / CGFloat(half), 2)
            let height = CGFloat(levels[distance]) * Self.maxBarHeight * taper
            bar.bounds.size.height = max(Self.barWidth, height)
        }
    }

    /// Processing: bars settle to dots, then a wave ripples out from the centre.
    private func startWave() {
        withoutAnimation {
            for bar in bars { bar.bounds.size.height = Self.barWidth }
        }
        let now = CACurrentMediaTime()
        let half = Self.barCount / 2
        for (index, bar) in bars.enumerated() {
            let wave = CABasicAnimation(keyPath: "bounds.size.height")
            wave.fromValue = Self.barWidth
            wave.toValue = Self.maxBarHeight * 0.55
            wave.duration = 0.42
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wave.beginTime = now + Double(abs(index - half)) * 0.07
            wave.fillMode = .backwards
            wave.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            bar.add(wave, forKey: "wave")
        }
    }

    override func stopAnimations() {
        for bar in bars { bar.removeAnimation(forKey: "wave") }
    }

    private static func symbol(_ name: String) -> Any? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            )?
            .layerContents(forContentsScale: 2)
    }
}
