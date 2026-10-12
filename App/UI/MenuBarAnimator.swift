import AppKit
import Observation

/// The menu bar icon while dictating: a small live waveform in the chosen style, then a row
/// of pulsing dots while transcribing. Dictation draws it as a template image (it follows
/// the menu bar's light or dark look); Rewrite adds an amber ✦ and tints it amber. Aurora
/// keeps its colours either way.
///
/// The waveform is the recording window's own Core Animation style, rendered into a small
/// bitmap ~20 times a second — only while a dictation is on screen.
@Observable
final class MenuBarAnimator {
    static let shared = MenuBarAnimator()

    /// nil: the regular symbol.
    private(set) var image: NSImage?

    @ObservationIgnored private var waveform: Waveform?
    @ObservationIgnored private var style: WaveformStyle = .conveyor
    @ObservationIgnored private var rewrite = false
    @ObservationIgnored private var processing = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var frame = 0
    @ObservationIgnored private var dirty = false

    private static let height: CGFloat = 18
    private static let waveSize = CGSize(width: 34, height: 14)
    private static let sparkWidth: CGFloat = 12
    private static let amber = NSColor(red: 1, green: 0.76, blue: 0.3, alpha: 1)

    private init() {}

    func start(style: WaveformStyle, rewrite: Bool) {
        guard AppSettings.shared.animateMenuBar else { return stop() }
        self.style = style
        self.rewrite = rewrite
        processing = false
        let waveform = style.make(style.metrics(for: .mini))
        waveform.layout(in: CGRect(origin: .zero, size: Self.waveSize))
        self.waveform = waveform
        dirty = true
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    func push(level: Float) {
        guard let waveform, !processing else { return }
        withoutAnimation { waveform.push(min(max(level, 0), 1), animated: false) }
        dirty = true
    }

    func startProcessing() {
        guard timer != nil else { return }
        processing = true
        dirty = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        waveform = nil
        processing = false
        if image != nil { image = nil }
    }

    private func tick() {
        frame += 1
        guard dirty || processing else { return }
        dirty = false
        image = render()
    }

    // MARK: Drawing

    private func render() -> NSImage {
        let spark = rewrite ? Self.sparkWidth : 0
        let size = CGSize(width: spark + Self.waveSize.width, height: Self.height)
        let colourful = style == .aurora && !processing
        let template = !rewrite && !colourful
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return NSImage() }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        do {
            if rewrite {
                Self.sparkle?.draw(in: CGRect(x: 0, y: (Self.height - 10) / 2, width: 10, height: 10))
            }
            let area = CGRect(x: spark, y: (Self.height - Self.waveSize.height) / 2,
                              width: Self.waveSize.width, height: Self.waveSize.height)
            context.saveGState()
            context.beginTransparencyLayer(in: area, auxiliaryInfo: nil)
            if processing {
                drawDots(in: area, context: context)
            } else if let waveform {
                context.translateBy(x: area.minX, y: area.minY)
                waveform.layer.render(in: context)
                context.translateBy(x: -area.minX, y: -area.minY)
            }
            if !colourful {  // one colour: black for the template, amber for Rewrite
                context.setBlendMode(.sourceIn)
                context.setFillColor((rewrite ? Self.amber : .black).cgColor)
                context.fill(area)
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = template
        return image
    }

    /// Five dots with a glow travelling left to right, like the windows' processing row.
    private func drawDots(in area: CGRect, context: CGContext) {
        let count = 5
        let step: CGFloat = 6
        let diameter: CGFloat = 3.2
        let start = area.midX - CGFloat(count - 1) * step / 2
        let phase = Double(frame % 24) / 24 * Double(count + 2) - 1
        for index in 0..<count {
            let glow = max(0, 1 - abs(Double(index) - phase) / 1.5)
            let d = diameter * (1 + 0.35 * glow)
            context.setFillColor(NSColor.white.withAlphaComponent(0.35 + 0.65 * glow).cgColor)
            context.fillEllipse(in: CGRect(x: start + CGFloat(index) * step - d / 2, y: area.midY - d / 2,
                                           width: d, height: d))
        }
    }

    private static let sparkle: NSImage? = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
        .withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [amber]))
        )
}
