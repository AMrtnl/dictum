import AppKit
import QuartzCore

/// Wide card: a long waveform above a bar with the mode name and key hints that
/// follow the state (Start ⌥Space · Stop ⌥Space  Cancel esc · Cancel esc). Drag its
/// edges to resize: the waveform gains bars as it widens and grows taller as the card does.
final class ClassicRecordingView: RecordingWindowView {
    private static let defaultCardSize = CGSize(width: 434, height: 136)
    private static let margin = NSEdgeInsets(top: 22, left: 20, bottom: 14, right: 20)
    private static let waveformInset: CGFloat = 22
    private static let footerInset: CGFloat = 12
    private static let footerHeight: CGFloat = 38
    private static let footerFont = NSFont.systemFont(ofSize: 14)
    private static let dim = NSColor.white.withAlphaComponent(0.5)
    private static let live = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
    private static let collapseSize: CGFloat = 22
    private static let hintGap: CGFloat = 18

    private let card: CALayer
    private let footer = CALayer()
    private let waveform: Waveform
    private let dots = ProcessingDots(diameter: 3, spacing: 9)
    private let micIcon = CALayer()
    /// Hands-free: a breathing red dot in place of the microphone.
    private let liveDot = CALayer()
    private let spinner = makeSpinner(diameter: 13, color: dim)
    private let modeLabel: CATextLayer
    private let startHint: CALayer
    private let stopHint: CALayer
    private let cancelHint: CALayer
    private let collapseIcon = CALayer()
    /// Narrowest card that still fits the footer without overlap.
    private let minimumCardWidth: CGFloat

    /// - Parameter stopKeys: key caps for the dictation shortcut, e.g. ["⌥", "Space"].
    init(stopKeys: [String], style: WaveformStyle = .conveyor) {
        waveform = style.make(style.metrics(for: .classic))
        let midY = Self.footerHeight / 2
        modeLabel = makeTextLayer("Dictation", font: Self.footerFont, color: Self.dim, x: 38, midY: midY)
        modeLabel.truncationMode = .end
        startHint = Self.makeHint("Start", keys: stopKeys, midY: midY)
        stopHint = Self.makeHint("Stop", keys: stopKeys, midY: midY)
        cancelHint = Self.makeHint("Cancel", keys: ["esc"], midY: midY)
        card = makeSurface(
            frame: CGRect(origin: CGPoint(x: Self.margin.left, y: Self.margin.bottom), size: Self.defaultCardSize),
            cornerRadius: 22,
            shadowRadius: 14
        )
        let longestLabel = ["Transcribing…", "Rewriting…", "Dictation", "Rewrite"]
            .map { textSize($0, font: Self.footerFont).width }.max() ?? 0
        let recordingHints = stopHint.frame.width + Self.hintGap + cancelHint.frame.width
        minimumCardWidth = 2 * Self.footerInset + 38 + longestLabel + 24 + recordingHints + 9

        super.init(
            size: NSSize(
                width: Self.defaultCardSize.width + Self.margin.left + Self.margin.right,
                height: Self.defaultCardSize.height + Self.margin.top + Self.margin.bottom
            ),
            historyLength: 1
        )
        layer?.addSublayer(card)
        card.addSublayer(waveform.layer)
        card.addSublayer(dots.layer)

        footer.cornerRadius = 11
        footer.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        card.addSublayer(footer)

        micIcon.frame = CGRect(x: 14, y: midY - 8, width: 16, height: 16)
        micIcon.contentsGravity = .resizeAspect
        micIcon.contents = Self.symbolImage("mic.fill", color: Self.dim)
        footer.addSublayer(micIcon)

        liveDot.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
        liveDot.cornerRadius = 4.5
        liveDot.backgroundColor = Self.live.cgColor
        liveDot.position = CGPoint(x: micIcon.frame.midX, y: midY)
        liveDot.opacity = 0
        footer.addSublayer(liveDot)

        spinner.position = CGPoint(x: micIcon.frame.midX, y: midY)
        spinner.opacity = 0
        footer.addSublayer(spinner)
        footer.addSublayer(modeLabel)
        for hint in [startHint, stopHint, cancelHint] { footer.addSublayer(hint) }

        collapseIcon.contentsGravity = .resizeAspect
        collapseIcon.opacity = 0.45
        collapseIcon.contents = Self.symbolImage("arrow.down.right.and.arrow.up.left", color: .white)
        card.addSublayer(collapseIcon)

        withoutAnimation {
            layoutSurface()
            applyMode(animated: false)
        }
    }

    // MARK: Geometry

    override var surfaceFrame: CGRect {
        CGRect(x: Self.margin.left, y: Self.margin.bottom,
               width: bounds.width - Self.margin.left - Self.margin.right,
               height: bounds.height - Self.margin.top - Self.margin.bottom)
    }

    override var isResizable: Bool { true }
    override var minimumSurfaceSize: CGSize { CGSize(width: max(360, minimumCardWidth), height: 132) }
    override var maximumSurfaceSize: CGSize { CGSize(width: 1200, height: 420) }

    override func layoutSurface() {
        let size = surfaceFrame.size
        card.frame = surfaceFrame
        updateShadowPath(card)

        footer.frame = CGRect(x: Self.footerInset, y: Self.footerInset,
                              width: size.width - 2 * Self.footerInset, height: Self.footerHeight)
        // Hints hug the right end; Stop sits left of Cancel, Start (idle) takes Cancel's place.
        let right = footer.bounds.width - 9
        cancelHint.frame.origin.x = right - cancelHint.frame.width
        stopHint.frame.origin.x = cancelHint.frame.minX - Self.hintGap - stopHint.frame.width
        startHint.frame.origin.x = right - startHint.frame.width
        layoutModeLabel()
        collapseIcon.frame = collapseFrame(in: size).insetBy(dx: 3, dy: 3)

        // Waveform: centred in the band between the footer and the collapse control's row.
        let bottom = Self.footerInset + Self.footerHeight
        let top = size.height - 32
        let height = max(22, min((top - bottom) * 0.72, 200))
        let rect = CGRect(x: Self.waveformInset, y: (bottom + top) / 2 - height / 2,
                          width: size.width - 2 * Self.waveformInset, height: height)
        waveform.layout(in: rect)
        dots.layout(in: CGRect(x: rect.minX, y: rect.midY - 4, width: rect.width, height: 8))
    }

    private func collapseFrame(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 34, y: size.height - 34, width: Self.collapseSize, height: Self.collapseSize)
    }

    /// The mode name gets whatever room the visible hints leave; it truncates rather than overlaps.
    private func layoutModeLabel() {
        let hintsLeft = switch mode {
        case .idle: startHint.frame.minX
        case .recording: stopHint.frame.minX
        case .processing: cancelHint.frame.minX
        }
        let text = (modeLabel.string as? String) ?? ""
        modeLabel.frame.size.width = max(0, min(textSize(text, font: Self.footerFont).width, hintsLeft - 16 - modeLabel.frame.minX))
    }

    // MARK: Collapse control

    private var collapseRect: CGRect {
        collapseFrame(in: surfaceFrame.size)
            .offsetBy(dx: surfaceFrame.minX, dy: surfaceFrame.minY)
            .insetBy(dx: -4, dy: -4)
    }

    override func control(at point: NSPoint) -> (() -> Void)? {
        collapseRect.contains(point) ? onToggleSize : nil
    }

    override func hoverChanged(at point: NSPoint?) {
        let over = point.map(collapseRect.contains) ?? false
        withoutAnimation { collapseIcon.opacity = over ? 0.9 : 0.45 }
    }

    // MARK: State

    override func levelPushed(_ level: Float) {
        guard mode == .recording else { return }
        waveform.push(level, animated: window?.isVisible == true)
    }

    override func resetLevelsDidHappen() {
        waveform.reset()
    }

    override func modeDidChange() {
        applyMode(animated: window?.isVisible == true)
    }

    override func labelsDidChange() {
        updateModeLabel()
    }

    override func lockDidChange() {
        applyMode(animated: window?.isVisible == true)
    }

    private func applyMode(animated: Bool) {
        let processing = mode == .processing
        let live = mode == .recording && isLocked
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        CATransaction.setDisableActions(!animated)
        micIcon.opacity = processing || live ? 0 : 1
        spinner.opacity = processing ? 1 : 0
        startHint.opacity = mode == .idle ? 1 : 0
        stopHint.opacity = mode == .recording ? 1 : 0
        cancelHint.opacity = mode == .idle ? 0 : 1
        waveform.layer.opacity = processing ? 0 : (mode == .idle ? 0.6 : 1)
        CATransaction.commit()

        updateLiveDot(visible: live)
        if mode != .recording { waveform.reset() }
        if processing {
            startSpinning(spinner)
            dots.start()
        } else {
            spinner.removeAllAnimations()
            dots.stop()
        }
        updateModeLabel()
    }

    private func updateModeLabel() {
        let text = switch mode {
        case .idle: "Ready"
        case .recording: modeTitle
        case .processing: processingLabel
        }
        withoutAnimation {
            modeLabel.string = text
            layoutModeLabel()
        }
    }

    /// The live dot breathes slowly (30 fps cap) while recording hands-free.
    private func updateLiveDot(visible: Bool) {
        if visible, liveDot.animation(forKey: "breathe") == nil {
            withoutAnimation { liveDot.opacity = 1 }
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.35
            breathe.duration = 0.9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            liveDot.add(breathe, forKey: "breathe")
        } else if !visible {
            liveDot.removeAnimation(forKey: "breathe")
            withoutAnimation { liveDot.opacity = 0 }
        }
    }

    override func stopAnimations() {
        spinner.removeAllAnimations()
        dots.stop()
        liveDot.removeAnimation(forKey: "breathe")
    }

    // MARK: Pieces

    /// "Stop ⌥ Space": a label and key caps, laid out left to right in a group sized to fit.
    private static func makeHint(_ title: String, keys: [String], midY: CGFloat) -> CALayer {
        let group = CALayer()
        var x: CGFloat = 0
        let label = makeTextLayer(title, font: footerFont, color: dim, x: 0, midY: midY)
        group.addSublayer(label)
        x = label.frame.maxX + 8
        for (index, key) in keys.enumerated() {
            let cap = makeKeycap(key, x: x, midY: midY)
            group.addSublayer(cap)
            x = cap.frame.maxX + (index == keys.count - 1 ? 0 : 4)
        }
        group.frame = CGRect(x: 0, y: 0, width: x, height: footerHeight)
        return group
    }

    private static func symbolImage(_ name: String, color: NSColor) -> Any? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            )?
            .layerContents(forContentsScale: 2)
    }
}
