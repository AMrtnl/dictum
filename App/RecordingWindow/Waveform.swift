import AppKit
import QuartzCore

enum WaveformStyle: String, CaseIterable, Identifiable {
    case conveyor, ripple, wave, equalizer, ribbon, aurora, dotMatrix

    var id: Self { self }

    var title: String {
        switch self {
        case .conveyor: "Conveyor"
        case .ripple: "Ripple"
        case .wave: "Wave"
        case .equalizer: "Equalizer"
        case .ribbon: "Ribbon"
        case .aurora: "Aurora"
        case .dotMatrix: "Dot Matrix"
        }
    }

    var summary: String {
        switch self {
        case .conveyor: "Bars travel from right to left, like a conveyor belt."
        case .ripple: "New sound appears in the middle and ripples outward."
        case .wave: "Layered sine waves that swell with your voice."
        case .equalizer: "Bouncing bars, like a music visualizer."
        case .ribbon: "A flowing ribbon that scrolls from right to left."
        case .aurora: "A glowing spectrum; sparks rise off the loudest moments."
        case .dotMatrix: "An LED dot display; lit columns travel right to left."
        }
    }

    enum Host { case mini, classic }

    /// Bar sizes per window: thin and dense in the wide Classic card, a little bolder in Mini.
    func metrics(for host: Host) -> Waveform.Metrics {
        switch (self, host) {
        case (.equalizer, .mini): Waveform.Metrics(barWidth: 3, barStep: 6.5)
        case (.equalizer, .classic): Waveform.Metrics(barWidth: 3, barStep: 7)
        case (.aurora, .mini): Waveform.Metrics(barWidth: 2, barStep: 3.2)
        case (.aurora, .classic): Waveform.Metrics(barWidth: 2, barStep: 3.4)
        case (.dotMatrix, .mini): Waveform.Metrics(barWidth: 2.2, barStep: 3.9)
        case (.dotMatrix, .classic): Waveform.Metrics(barWidth: 2.4, barStep: 4.6)
        case (_, .mini): Waveform.Metrics(barWidth: 2.2, barStep: 4.2)
        case (_, .classic): Waveform.Metrics(barWidth: 1.6, barStep: 3.75)
        }
    }

    func make(_ metrics: Waveform.Metrics) -> Waveform {
        switch self {
        case .conveyor: ConveyorWaveform(metrics)
        case .ripple: RippleWaveform(metrics)
        case .wave: SineWaveform(metrics)
        case .equalizer: EqualizerWaveform(metrics)
        case .ribbon: RibbonWaveform(metrics)
        case .aurora: AuroraWaveform(metrics)
        case .dotMatrix: DotMatrixWaveform(metrics)
        }
    }
}

/// Draws live audio levels (0…1, ~30 per second) inside a recording window.
///
/// Every style is plain Core Animation layers: an update is a handful of property
/// writes, and the short linear animation between updates is interpolated by the
/// window server, so motion looks smooth without the app drawing at display rate.
/// No masks or filters, so `CALayer.render(in:)` (used for preview videos) matches the app.
class Waveform {
    struct Metrics {
        var barWidth: CGFloat
        var barStep: CGFloat
        /// Fraction of the area's height the loudest sound reaches.
        var reach: CGFloat = 1
    }

    let layer = CALayer()
    let metrics: Metrics
    private(set) var size: CGSize = .zero
    /// Seconds between updates; also the length of the in-between animation.
    static let interval: CFTimeInterval = 1.0 / 30

    init(_ metrics: Metrics) {
        self.metrics = metrics
        layer.masksToBounds = false
    }

    /// Lays the waveform out in `rect` (the host's coordinates).
    func layout(in rect: CGRect) {
        size = rect.size
        withoutAnimation {
            layer.frame = rect
            didLayout()
        }
    }

    func push(_ level: Float, animated: Bool) {}
    func reset() {}
    func didLayout() {}

    /// Height of the drawing area's centre line.
    var midY: CGFloat { size.height / 2 }
    var halfHeight: CGFloat { size.height / 2 * metrics.reach }

    /// Animates `keyPath` linearly from its on-screen value over one update interval.
    func glide(_ layer: CALayer, _ keyPath: String, to value: Any, animated: Bool) {
        if animated, let from = layer.presentation()?.value(forKeyPath: keyPath) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = value
            animation.duration = Self.interval * 1.1
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: keyPath)
        }
        layer.setValue(value, forKeyPath: keyPath)
    }

    static func makeBar(width: CGFloat, color: NSColor = .white) -> CALayer {
        let bar = CALayer()
        bar.bounds = CGRect(x: 0, y: 0, width: width, height: width)
        bar.cornerRadius = width / 2
        bar.backgroundColor = color.cgColor
        return bar
    }

    /// 0 at the edges, 1 across the middle; smooth.
    static func edgeFade(_ x: CGFloat, width: CGFloat, band: CGFloat = 0.18) -> CGFloat {
        let t = min(x, width - x) / max(width * band, 1)
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

// MARK: - Conveyor

/// Bars enter on the right and travel left. Between updates the strip slides one
/// step, so the belt moves continuously instead of jumping bar by bar.
final class ConveyorWaveform: Waveform {
    private let strip = CALayer()
    private var bars: [CALayer] = []
    private var levels: [Float] = []

    override init(_ metrics: Metrics) {
        super.init(metrics)
        layer.addSublayer(strip)
    }

    override func didLayout() {
        let count = Int(size.width / metrics.barStep) + 2
        while bars.count < count {
            let bar = Self.makeBar(width: metrics.barWidth)
            strip.addSublayer(bar)
            bars.append(bar)
        }
        while bars.count > count { bars.removeLast().removeFromSuperlayer() }
        levels = Array(levels.prefix(count)) + [Float](repeating: 0, count: max(0, count - levels.count))
        strip.frame = CGRect(origin: .zero, size: size)
        for (index, bar) in bars.enumerated() {
            let x = size.width - metrics.barWidth / 2 - CGFloat(index) * metrics.barStep
            bar.position = CGPoint(x: x, y: midY)
            bar.opacity = Float(Self.edgeFade(x, width: size.width))
        }
        apply()
    }

    override func push(_ level: Float, animated: Bool) {
        levels.removeLast()
        levels.insert(level, at: 0)
        withoutAnimation { apply() }
        guard animated else { return }
        // Data moved one slot left; start one step back to the right and slide in.
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = metrics.barStep
        slide.toValue = 0
        slide.duration = Self.interval * 1.1
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(slide, forKey: "slide")
    }

    override func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { apply() }
    }

    private func apply() {
        for (bar, level) in zip(bars, levels) {
            bar.bounds.size.height = max(metrics.barWidth, CGFloat(level) * halfHeight * 2)
        }
    }
}

// MARK: - Ripple

/// New sound appears in the middle and ripples toward both edges (the original style).
final class RippleWaveform: Waveform {
    private var bars: [CALayer] = []
    private var levels: [Float] = []

    override func didLayout() {
        var count = max(7, Int((size.width - metrics.barWidth) / metrics.barStep) + 1)
        if count.isMultiple(of: 2) { count -= 1 }
        while bars.count < count {
            let bar = Self.makeBar(width: metrics.barWidth)
            layer.addSublayer(bar)
            bars.append(bar)
        }
        while bars.count > count { bars.removeLast().removeFromSuperlayer() }
        let half = count / 2 + 1
        levels = Array(levels.prefix(half)) + [Float](repeating: 0, count: max(0, half - levels.count))
        let step = (size.width - metrics.barWidth) / CGFloat(max(count - 1, 1))
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: metrics.barWidth / 2 + CGFloat(index) * step, y: midY)
        }
        apply()
    }

    override func push(_ level: Float, animated: Bool) {
        levels.removeLast()
        levels.insert(level, at: 0)
        withoutAnimation { apply() }
    }

    override func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { apply() }
    }

    private func apply() {
        let half = bars.count / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - half)
            let edge = CGFloat(distance) / CGFloat(max(half, 1))
            let level = distance < levels.count ? CGFloat(levels[distance]) : 0
            bar.bounds.size.height = max(metrics.barWidth, level * halfHeight * 2 * (1 - 0.7 * edge * edge))
        }
    }
}

// MARK: - Wave

/// Three layered sine waves travelling right to left; their amplitude follows the voice
/// and tapers to nothing at the edges, so the shape breathes in the middle.
final class SineWaveform: Waveform {
    private let waves: [(layer: CAShapeLayer, cycles: CGFloat, speed: CGFloat, gain: CGFloat)]
    private var level: CGFloat = 0
    private var phase: CGFloat = 0

    override init(_ metrics: Metrics) {
        let specs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [  // cycles, speed, gain, alpha, width
            (1.6, 5.0, 1.0, 0.95, 1.8), (2.4, 7.0, 0.7, 0.55, 1.4), (3.3, 9.5, 0.45, 0.32, 1.1),
        ]
        waves = specs.map { cycles, speed, gain, alpha, width in
            let shape = CAShapeLayer()
            shape.fillColor = nil
            shape.strokeColor = NSColor.white.withAlphaComponent(alpha).cgColor
            shape.lineWidth = width
            shape.lineCap = .round
            return (shape, cycles, speed, gain)
        }
        super.init(metrics)
        for wave in waves.reversed() { layer.addSublayer(wave.layer) }
    }

    override func didLayout() {
        for wave in waves { wave.layer.frame = CGRect(origin: .zero, size: size) }
        draw(animated: false)
    }

    override func push(_ level: Float, animated: Bool) {
        let target = CGFloat(level)
        self.level += (target - self.level) * (target > self.level ? 0.55 : 0.18)
        phase += CGFloat(Self.interval)
        draw(animated: animated)
    }

    override func reset() {
        level = 0
        draw(animated: false)
    }

    private func draw(animated: Bool) {
        let points = 72
        for wave in waves {
            let path = CGMutablePath()
            let amplitude = max(level, 0.015) * halfHeight * wave.gain
            for i in 0...points {
                let t = CGFloat(i) / CGFloat(points)
                let x = t * size.width
                let envelope = pow(sin(.pi * t), 2)
                let y = midY + amplitude * envelope * sin(2 * .pi * wave.cycles * t + phase * wave.speed)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            glide(wave.layer, "path", to: path, animated: animated)
        }
    }
}

// MARK: - Equalizer

/// Bars bounce independently around the voice level: quick to rise, slow to fall.
final class EqualizerWaveform: Waveform {
    private var bars: [CALayer] = []
    private var heights: [CGFloat] = []

    override func didLayout() {
        let count = max(5, Int((size.width + metrics.barStep - metrics.barWidth) / metrics.barStep))
        while bars.count < count {
            let bar = Self.makeBar(width: metrics.barWidth)
            layer.addSublayer(bar)
            bars.append(bar)
        }
        while bars.count > count { bars.removeLast().removeFromSuperlayer() }
        heights = [CGFloat](repeating: 0, count: count)
        let span = CGFloat(count - 1) * metrics.barStep
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: (size.width - span) / 2 + CGFloat(index) * metrics.barStep, y: midY)
        }
        apply(animated: false)
    }

    override func push(_ level: Float, animated: Bool) {
        let count = bars.count
        for index in 0..<count {
            let centre = 1 - 0.55 * pow(abs(CGFloat(index) - CGFloat(count - 1) / 2) / (CGFloat(count) / 2), 2)
            let target = CGFloat(level) * CGFloat.random(in: 0.35...1) * centre
            heights[index] += (target - heights[index]) * (target > heights[index] ? 0.7 : 0.22)
        }
        apply(animated: animated)
    }

    override func reset() {
        heights = heights.map { _ in 0 }
        apply(animated: false)
    }

    private func apply(animated: Bool) {
        for (bar, height) in zip(bars, heights) {
            let bounds = CGRect(x: 0, y: 0, width: metrics.barWidth, height: max(metrics.barWidth, height * halfHeight * 2))
            glide(bar, "bounds", to: NSValue(rect: bounds), animated: animated)
        }
    }
}

// MARK: - Ribbon

/// A mirrored, filled envelope of the recent levels that scrolls right to left like a
/// tape, outlined top and bottom. Smooth curve through the samples.
final class RibbonWaveform: Waveform {
    private let strip = CALayer()
    private let fill = CAShapeLayer()
    private let outline = CAShapeLayer()
    private var levels: [Float] = []
    private var step: CGFloat { metrics.barStep * 1.6 }

    override init(_ metrics: Metrics) {
        super.init(metrics)
        fill.fillColor = NSColor.white.withAlphaComponent(0.22).cgColor
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        outline.lineWidth = 1.3
        outline.lineJoin = .round
        strip.addSublayer(fill)
        strip.addSublayer(outline)
        layer.addSublayer(strip)
    }

    override func didLayout() {
        let count = Int(size.width / step) + 3
        levels = Array(levels.prefix(count)) + [Float](repeating: 0, count: max(0, count - levels.count))
        strip.frame = CGRect(origin: .zero, size: size)
        fill.frame = strip.bounds
        outline.frame = strip.bounds
        draw()
    }

    override func push(_ level: Float, animated: Bool) {
        levels.removeLast()
        levels.insert(level, at: 0)
        withoutAnimation { draw() }
        guard animated else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = step
        slide.toValue = 0
        slide.duration = Self.interval * 1.1
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(slide, forKey: "slide")
    }

    override func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { draw() }
    }

    private func draw() {
        let points: [CGPoint] = levels.enumerated().map { index, level in
            let x = size.width - CGFloat(index) * step
            let fade = Self.edgeFade(min(max(x, 0), size.width), width: size.width, band: 0.22)
            return CGPoint(x: x, y: max(0.6, CGFloat(level) * halfHeight * fade))
        }
        let upper = points.map { CGPoint(x: $0.x, y: midY + $0.y) }
        let lower = points.reversed().map { CGPoint(x: $0.x, y: midY - $0.y) }

        let lines = CGMutablePath()
        Self.appendCurve(through: upper, to: lines, moving: true)
        Self.appendCurve(through: lower, to: lines, moving: true)
        outline.path = lines

        let area = CGMutablePath()
        Self.appendCurve(through: upper, to: area, moving: true)
        Self.appendCurve(through: lower, to: area, moving: false)
        area.closeSubpath()
        fill.path = area
    }

    /// Catmull-Rom spline through `points`, appended as cubic Béziers.
    private static func appendCurve(through points: [CGPoint], to path: CGMutablePath, moving: Bool) {
        guard let first = points.first else { return }
        if moving { path.move(to: first) } else { path.addLine(to: first) }
        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

// MARK: - Aurora

/// A spectrum of bars along cyan → violet → pink → amber. Each bar has a white-hot core
/// and a soft neon halo, the colours drift while you speak, and sparks rise off the
/// loudest moments and fade.
final class AuroraWaveform: Waveform {
    private struct Spark {
        let layer = CALayer()
        var velocity = CGPoint.zero
        var life = 0
        var age = 0
    }

    private var halos: [CALayer] = []
    private var cores: [CAGradientLayer] = []
    private var sparks: [Spark] = []
    private var level: CGFloat = 0
    private var drift: CGFloat = 0
    private static let palette: [NSColor] = [
        NSColor(red: 0.30, green: 0.85, blue: 1.00, alpha: 1),
        NSColor(red: 0.45, green: 0.45, blue: 1.00, alpha: 1),
        NSColor(red: 0.80, green: 0.35, blue: 0.95, alpha: 1),
        NSColor(red: 1.00, green: 0.40, blue: 0.60, alpha: 1),
        NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1),
    ]

    override init(_ metrics: Metrics) {
        super.init(metrics)
        for _ in 0..<14 {
            let spark = Spark()
            spark.layer.bounds = CGRect(x: 0, y: 0, width: 2.2, height: 2.2)
            spark.layer.cornerRadius = 1.1
            spark.layer.backgroundColor = NSColor.white.cgColor
            spark.layer.opacity = 0
            sparks.append(spark)
        }
    }

    override func didLayout() {
        let count = max(9, Int(size.width / metrics.barStep))
        while cores.count < count {
            let halo = CALayer()
            halo.opacity = 0.26
            let core = CAGradientLayer()
            core.locations = [0, 0.5, 1]
            layer.addSublayer(halo)
            layer.addSublayer(core)
            halos.append(halo)
            cores.append(core)
        }
        while cores.count > count {
            halos.removeLast().removeFromSuperlayer()
            cores.removeLast().removeFromSuperlayer()
        }
        for spark in sparks where spark.layer.superlayer == nil { layer.addSublayer(spark.layer) }
        let span = CGFloat(count - 1) * metrics.barStep
        for index in 0..<count {
            let x = (size.width - span) / 2 + CGFloat(index) * metrics.barStep
            halos[index].position = CGPoint(x: x, y: midY)
            cores[index].position = CGPoint(x: x, y: midY)
        }
        apply(animated: false)
    }

    override func push(_ level: Float, animated: Bool) {
        let target = CGFloat(level)
        self.level += (target - self.level) * (target > self.level ? 0.5 : 0.16)
        drift += CGFloat(Self.interval) * (0.12 + 0.25 * self.level)
        apply(animated: animated)
        updateSparks(animated: animated)
    }

    override func reset() {
        level = 0
        for index in sparks.indices {
            sparks[index].life = 0
            sparks[index].layer.opacity = 0
        }
        apply(animated: false)
    }

    private func height(at index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(max(cores.count - 1, 1))
        let lens = pow(sin(.pi * t), 1.6)
        let ripple = 0.75 + 0.25 * sin(2 * .pi * (t * 3 - drift * 4))
        return max(metrics.barWidth, (0.04 + level) * halfHeight * 2 * lens * ripple)
    }

    private func apply(animated: Bool) {
        let count = cores.count
        for index in 0..<count {
            let t = CGFloat(index) / CGFloat(max(count - 1, 1))
            let colour = Self.colour(at: (t + drift).truncatingRemainder(dividingBy: 1))
            let hot = colour.blended(withFraction: 0.35 + 0.4 * level, of: .white) ?? colour
            let h = height(at: index)
            let core = CGRect(x: 0, y: 0, width: metrics.barWidth, height: h)
            let halo = CGRect(x: 0, y: 0, width: metrics.barWidth * 3.2, height: h + metrics.barWidth * 2)
            glide(cores[index], "bounds", to: NSValue(rect: core), animated: animated)
            glide(halos[index], "bounds", to: NSValue(rect: halo), animated: animated)
            withoutAnimation {
                cores[index].cornerRadius = metrics.barWidth / 2
                cores[index].colors = [colour.cgColor, hot.cgColor, colour.cgColor]
                halos[index].cornerRadius = halo.width / 2
                halos[index].backgroundColor = colour.cgColor
            }
        }
    }

    /// Sparks: born at the top of loud bars, drift up and sideways, fade out.
    private func updateSparks(animated: Bool) {
        let count = cores.count
        if level > 0.45, count > 0, Double.random(in: 0...1) < Double(level) * 0.5,
           let free = sparks.firstIndex(where: { $0.life == 0 }) {
            let index = Int.random(in: count / 5..<max(count * 4 / 5, count / 5 + 1))
            let top = midY + height(at: index) / 2
            sparks[free].life = Int.random(in: 14...24)
            sparks[free].age = 0
            sparks[free].velocity = CGPoint(x: CGFloat.random(in: -0.35...0.35), y: CGFloat.random(in: 0.35...0.8))
            withoutAnimation {
                sparks[free].layer.position = CGPoint(x: cores[index].position.x, y: top)
                sparks[free].layer.opacity = 1
            }
        }
        for index in sparks.indices where sparks[index].life > 0 {
            sparks[index].age += 1
            let progress = CGFloat(sparks[index].age) / CGFloat(sparks[index].life)
            let position = sparks[index].layer.position
            let next = CGPoint(x: position.x + sparks[index].velocity.x, y: position.y + sparks[index].velocity.y)
            glide(sparks[index].layer, "position", to: NSValue(point: next), animated: animated)
            withoutAnimation { sparks[index].layer.opacity = Float(max(0, 1 - progress)) }
            if sparks[index].age >= sparks[index].life { sparks[index].life = 0 }
        }
    }

    private static func colour(at position: CGFloat) -> NSColor {
        let scaled = position * CGFloat(palette.count - 1)
        let index = min(Int(scaled), palette.count - 2)
        let fraction = scaled - CGFloat(index)
        return palette[index].blended(withFraction: fraction, of: palette[index + 1]) ?? palette[index]
    }
}

// MARK: - Dot Matrix

/// An LED dot display: a faint grid of dots, with columns lit from the centre outward by
/// the voice, travelling right to left. Each column swaps between a few prebuilt paths,
/// so an update is pointer assignments, not drawing.
final class DotMatrixWaveform: Waveform {
    private let strip = CALayer()
    private let grid = CAShapeLayer()
    private var columns: [CAShapeLayer] = []
    private var litPaths: [CGPath] = []
    private var levels: [Float] = []
    private var rows = 5

    override init(_ metrics: Metrics) {
        super.init(metrics)
        grid.fillColor = NSColor.white.withAlphaComponent(0.1).cgColor
        strip.addSublayer(grid)
        layer.addSublayer(strip)
    }

    override func didLayout() {
        let pitch = metrics.barStep, dot = metrics.barWidth
        rows = max(3, Int(size.height / pitch))
        if rows.isMultiple(of: 2) { rows -= 1 }
        let count = Int(size.width / pitch) + 2
        strip.frame = CGRect(origin: .zero, size: size)
        let top = midY + CGFloat(rows / 2) * pitch

        // Prebuilt column paths for 0…(rows/2+1) lit "radius".
        litPaths = (0...(rows / 2 + 1)).map { radius in
            let path = CGMutablePath()
            for row in 0..<rows where abs(row - rows / 2) < radius {
                path.addEllipse(in: CGRect(x: -dot / 2, y: top - CGFloat(row) * pitch - dot / 2, width: dot, height: dot))
            }
            return path
        }
        let gridPath = CGMutablePath()
        for column in 0..<count {
            let x = size.width - pitch / 2 - CGFloat(column) * pitch
            for row in 0..<rows {
                gridPath.addEllipse(in: CGRect(x: x - dot / 2, y: top - CGFloat(row) * pitch - dot / 2, width: dot, height: dot))
            }
        }
        grid.frame = strip.bounds
        grid.path = gridPath

        while columns.count < count {
            let column = CAShapeLayer()
            column.fillColor = NSColor.white.cgColor
            strip.addSublayer(column)
            columns.append(column)
        }
        while columns.count > count { columns.removeLast().removeFromSuperlayer() }
        levels = Array(levels.prefix(count)) + [Float](repeating: 0, count: max(0, count - levels.count))
        for (index, column) in columns.enumerated() {
            let x = size.width - pitch / 2 - CGFloat(index) * pitch
            column.frame = CGRect(x: x, y: 0, width: 0, height: size.height)
            column.opacity = Float(Self.edgeFade(x, width: size.width, band: 0.12))
        }
        apply()
    }

    override func push(_ level: Float, animated: Bool) {
        levels.removeLast()
        levels.insert(level, at: 0)
        withoutAnimation { apply() }
        guard animated else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = metrics.barStep
        slide.toValue = 0
        slide.duration = Self.interval * 1.1
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(slide, forKey: "slide")
    }

    override func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        withoutAnimation { apply() }
    }

    private func apply() {
        let maxRadius = litPaths.count - 1
        for (column, level) in zip(columns, levels) {
            let radius = min(maxRadius, Int((CGFloat(level) * CGFloat(maxRadius) * metrics.reach).rounded()))
            column.path = litPaths[radius]
        }
    }
}
