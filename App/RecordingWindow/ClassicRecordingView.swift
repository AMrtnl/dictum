import AppKit
import QuartzCore

/// Wide card: a long mirrored waveform above a bar with the mode name and the
/// stop / cancel key hints. Drag its edges to resize: the waveform gains bars
/// as it widens and grows taller as the card does.
final class ClassicRecordingView: RecordingWindowView {
    private static let defaultCardSize = CGSize(width: 434, height: 136)
    private static let margin = NSEdgeInsets(top: 22, left: 20, bottom: 14, right: 20)
    private static let barWidth: CGFloat = 1.5
    private static let barStep: CGFloat = 3.75
    private static let waveformInset: CGFloat = 20
    private static let footerInset: CGFloat = 12
    private static let footerHeight: CGFloat = 38
    private static let footerFont = NSFont.systemFont(ofSize: 14)
    private static let dim = NSColor.white.withAlphaComponent(0.5)
    private static let collapseSize: CGFloat = 22

    private let card: CALayer
    private let footer = CALayer()
    private var bars: [CALayer] = []
    private let micIcon = CALayer()
    private let spinner = makeSpinner(diameter: 13, color: dim)
    private let modeLabel: CATextLayer
    private let hints = CALayer()
    private let stopHint = CALayer()
    private let collapseIcon = CALayer()
    private var maxBarHeight: CGFloat = 18
    /// Narrowest card that still fits the footer without overlap.
    private let minimumCardWidth: CGFloat

    /// - Parameter stopKeys: key caps for the dictation shortcut, e.g. ["⌥", "Space"].
    init(stopKeys: [String]) {
        let midY = Self.footerHeight / 2
        modeLabel = makeTextLayer("Dictation", font: Self.footerFont, color: Self.dim, x: 38, midY: midY)
        card = makeSurface(
            frame: CGRect(origin: CGPoint(x: Self.margin.left, y: Self.margin.bottom), size: Self.defaultCardSize),
            cornerRadius: 22,
            shadowRadius: 14
        )

        // Right-aligned hints, laid out right to left inside `hints`: [Stop ⌥ Space]  Cancel esc
        var x: CGFloat = 0
        var placed: [(CALayer, CALayer)] = []
        func place(_ sublayer: CALayer, in parent: CALayer, gap: CGFloat) {
            x -= sublayer.frame.width
            sublayer.frame.origin.x = x
            placed.append((sublayer, parent))
            x -= gap
        }
        place(makeKeycap("esc", x: 0, midY: midY), in: hints, gap: 8)
        place(makeTextLayer("Cancel", font: Self.footerFont, color: Self.dim, x: 0, midY: midY), in: hints, gap: 18)
        for key in stopKeys.reversed() {
            place(makeKeycap(key, x: 0, midY: midY), in: stopHint, gap: 4)
        }
        x -= 4
        place(makeTextLayer("Stop", font: Self.footerFont, color: Self.dim, x: 0, midY: midY), in: stopHint, gap: 0)
        let hintsWidth = -x
        for (sublayer, parent) in placed {
            sublayer.frame.origin.x += hintsWidth  // shift into the group's positive coordinates
            parent.addSublayer(sublayer)
        }
        let longestLabel = textSize("Transcribing…", font: Self.footerFont).width
        minimumCardWidth = 2 * Self.footerInset + 38 + longestLabel + 24 + hintsWidth + 9

        super.init(
            size: NSSize(
                width: Self.defaultCardSize.width + Self.margin.left + Self.margin.right,
                height: Self.defaultCardSize.height + Self.margin.top + Self.margin.bottom
            ),
            historyLength: 1
        )
        layer?.addSublayer(card)

        footer.cornerRadius = 11
        footer.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        card.addSublayer(footer)

        micIcon.frame = CGRect(x: 14, y: midY - 8, width: 16, height: 16)
        micIcon.contentsGravity = .resizeAspect
        micIcon.contents = Self.symbolImage("mic.fill", color: Self.dim)
        footer.addSublayer(micIcon)

        spinner.position = CGPoint(x: micIcon.frame.midX, y: midY)
        spinner.opacity = 0
        footer.addSublayer(spinner)
        footer.addSublayer(modeLabel)

        hints.frame = CGRect(x: 0, y: 0, width: hintsWidth, height: Self.footerHeight)
        stopHint.frame = hints.bounds
        hints.addSublayer(stopHint)
        footer.addSublayer(hints)

        collapseIcon.contentsGravity = .resizeAspect
        collapseIcon.opacity = 0.45
        collapseIcon.contents = Self.symbolImage("arrow.down.right.and.arrow.up.left", color: .white)
        card.addSublayer(collapseIcon)

        withoutAnimation { layoutSurface() }
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
        hints.frame.origin.x = footer.bounds.width - 9 - hints.frame.width
        collapseIcon.frame = collapseFrame(in: size).insetBy(dx: 3, dy: 3)

        // Waveform: centred in the space above the footer, as many bars as fit.
        let top = Self.footerInset + Self.footerHeight
        let midY = top + (size.height - top) * 0.45
        maxBarHeight = max(12, (size.height - top) * 0.21)
        let width = size.width - 2 * Self.waveformInset
        var count = max(31, Int((width - Self.barWidth) / Self.barStep) + 1)
        if count.isMultiple(of: 2) { count -= 1 }
        resizeBars(to: count)
        setHistoryLength(count / 2 + 1)
        let step = (width - Self.barWidth) / CGFloat(count - 1)
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: Self.waveformInset + CGFloat(index) * step + Self.barWidth / 2, y: midY)
        }
        levelsDidChange()
    }

    private func resizeBars(to count: Int) {
        while bars.count > count { bars.removeLast().removeFromSuperlayer() }
        while bars.count < count {
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
            card.addSublayer(bar)
            bars.append(bar)
        }
    }

    private func collapseFrame(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 34, y: size.height - 34, width: Self.collapseSize, height: Self.collapseSize)
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

    override func levelsDidChange() {
        guard mode != .processing else { return }
        let half = bars.count / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - half)
            let edge = CGFloat(distance) / CGFloat(max(half, 1))
            let level = distance < levels.count ? CGFloat(levels[distance]) : 0
            bar.bounds.size.height = max(Self.barWidth, level * maxBarHeight * (1 - edge * edge))
        }
    }

    override func modeDidChange() {
        let processing = mode == .processing
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        micIcon.opacity = processing ? 0 : 1
        spinner.opacity = processing ? 1 : 0
        stopHint.opacity = mode == .recording ? 1 : 0
        if processing {
            for bar in bars { bar.bounds.size.height = Self.barWidth }
        }
        CATransaction.commit()

        updateModeLabel()
        if processing { startSpinning(spinner) } else { stopAnimations() }
    }

    override func labelsDidChange() {
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
            modeLabel.frame.size.width = textSize(text, font: Self.footerFont).width
        }
    }

    override func stopAnimations() {
        spinner.removeAllAnimations()
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
