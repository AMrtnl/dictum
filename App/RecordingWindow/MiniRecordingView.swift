import AppKit
import QuartzCore

/// Small black capsule with a centred, mirrored waveform.
final class MiniRecordingView: RecordingWindowView {
    private static let capsuleSize = CGSize(width: 86, height: 30)
    private static let margin = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
    private static let barCount = 11
    private static let barWidth: CGFloat = 2.5
    private static let barStep: CGFloat = 5
    private static let maxBarHeight: CGFloat = 16

    private let bars = (0..<barCount).map { _ in CALayer() }

    init() {
        let half = Self.barCount / 2
        super.init(
            size: NSSize(
                width: Self.capsuleSize.width + Self.margin.left + Self.margin.right,
                height: Self.capsuleSize.height + Self.margin.top + Self.margin.bottom
            ),
            historyLength: half + 1
        )

        let capsule = makeSurface(
            frame: CGRect(origin: CGPoint(x: Self.margin.left, y: Self.margin.bottom), size: Self.capsuleSize),
            cornerRadius: Self.capsuleSize.height / 2,
            shadowRadius: 8
        )
        capsule.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(capsule)

        let span = CGFloat(Self.barCount - 1) * Self.barStep + Self.barWidth
        let originX = (Self.capsuleSize.width - span) / 2
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            bar.position = CGPoint(
                x: originX + CGFloat(index) * Self.barStep + Self.barWidth / 2,
                y: Self.capsuleSize.height / 2
            )
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
            capsule.addSublayer(bar)
        }
    }

    override func levelsDidChange() {
        let half = Self.barCount / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - half)
            let taper = 1 - 0.55 * pow(CGFloat(distance) / CGFloat(half), 2)
            let height = CGFloat(levels[distance]) * Self.maxBarHeight * taper
            bar.bounds.size.height = max(Self.barWidth, height)
        }
    }

    override func modeDidChange() {
        guard mode == .processing else {
            stopAnimations()
            if mode == .idle { withoutAnimation { levelsDidChange() } }
            return
        }
        // Bars settle to dots, then a wave ripples out from the centre.
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
}
