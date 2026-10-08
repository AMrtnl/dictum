import AppKit
import SwiftUI

/// Speech-like levels for previews — syllable bursts, short gaps, the odd pause — so the
/// styles can be shown moving without the microphone.
struct SyntheticSpeech {
    private var state: UInt64
    private var target: Float = 0
    private var remaining = 0
    private var level: Float = 0

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    private mutating func random() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
    }

    /// Feeds about `count` levels to `push`, ending mid-syllable so a still frame shows sound.
    mutating func prefill(_ count: Int, push: (Float) -> Void) {
        for index in 0..<(count + 120) {
            let level = next()
            push(level)
            if index >= count, level > 0.75 { return }
        }
    }

    /// The next level (0…1); call it 30 times a second, like the recorder does.
    mutating func next() -> Float {
        if remaining == 0 {
            let pick = random()
            if pick < 0.07 {  // a pause between phrases
                target = 0.02
                remaining = 10 + Int(random() * 14)
            } else if pick < 0.33 {  // between syllables
                target = 0.06
                remaining = 1 + Int(random() * 3)
            } else {  // a syllable
                target = 0.35 + random() * 0.65
                remaining = 3 + Int(random() * 6)
            }
        }
        remaining -= 1
        level += (target - level) * (target > level ? 0.6 : 0.35)
        return min(1, max(0, level + (random() - 0.5) * 0.06))
    }
}

/// One 30 Hz timer for every preview on screen; it only runs while a preview is in a window.
final class PreviewClock {
    static let shared = PreviewClock()
    private var subscribers: [ObjectIdentifier: () -> Void] = [:]
    private var timer: Timer?

    func add(_ owner: AnyObject, tick: @escaping () -> Void) {
        subscribers[ObjectIdentifier(owner)] = tick
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Waveform.interval, repeats: true) { _ in
            MainActor.assumeIsolated { PreviewClock.shared.fire() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func remove(_ owner: AnyObject) {
        subscribers[ObjectIdentifier(owner)] = nil
        if subscribers.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func fire() {
        subscribers.values.forEach { $0() }
    }
}

// MARK: - Waveform styles

/// A waveform style moving inside a pill drawn exactly like the small recording window's
/// (same layers and sizes), shown a little larger.
final class WaveformPreviewView: NSView {
    private static let pillSize = CGSize(width: 142, height: 36)
    private static let waveformSize = CGSize(width: 100, height: 18)
    private static let scale: CGFloat = 1.1

    private let pill = CALayer()
    private let clip = CALayer()
    private var waveform: Waveform
    private var speech: SyntheticSpeech
    private var style: WaveformStyle

    init(style: WaveformStyle, seed: UInt64) {
        self.style = style
        waveform = style.make(style.metrics(for: .mini))
        speech = SyntheticSpeech(seed: seed)
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true

        pill.bounds = CGRect(origin: .zero, size: Self.pillSize)
        pill.cornerRadius = Self.pillSize.height / 2
        pill.backgroundColor = NSColor.black.cgColor
        pill.borderWidth = 1
        pill.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.25
        pill.shadowRadius = 6
        pill.shadowOffset = CGSize(width: 0, height: -2)
        pill.shadowPath = CGPath(roundedRect: pill.bounds, cornerWidth: pill.cornerRadius,
                                 cornerHeight: pill.cornerRadius, transform: nil)
        pill.setAffineTransform(CGAffineTransform(scaleX: Self.scale, y: Self.scale))
        clip.frame = pill.bounds
        clip.cornerRadius = pill.cornerRadius
        clip.masksToBounds = true
        pill.addSublayer(clip)
        layer?.addSublayer(pill)
        install()
        // A moment of sound already on screen, so a still page isn't a row of flat lines.
        speech.prefill(40) { waveform.push($0, animated: false) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStyle(_ next: WaveformStyle) {
        guard next != style else { return }
        style = next
        waveform.layer.removeFromSuperlayer()
        waveform = next.make(next.metrics(for: .mini))
        install()
    }

    private func install() {
        clip.addSublayer(waveform.layer)
        waveform.layout(in: CGRect(x: (Self.pillSize.width - Self.waveformSize.width) / 2,
                                   y: (Self.pillSize.height - Self.waveformSize.height) / 2,
                                   width: Self.waveformSize.width, height: Self.waveformSize.height))
    }

    override func layout() {
        super.layout()
        withoutAnimation { pill.position = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            PreviewClock.shared.add(self) { [weak self] in self?.tick() }
        } else {
            PreviewClock.shared.remove(self)
        }
    }

    private func tick() {
        guard let window, window.isVisible, window.occlusionState.contains(.visible) else { return }
        waveform.push(speech.next(), animated: true)
    }
}

struct WaveformPreview: NSViewRepresentable {
    let style: WaveformStyle
    let seed: UInt64

    func makeNSView(context: Context) -> WaveformPreviewView {
        WaveformPreviewView(style: style, seed: seed)
    }

    func updateNSView(_ view: WaveformPreviewView, context: Context) {
        view.setStyle(style)
    }
}

/// Cards showing every waveform style moving, to pick one.
struct WaveformStylePicker: View {
    @Binding var selection: WaveformStyle
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(Array(WaveformStyle.allCases.enumerated()), id: \.element) { index, style in
                WaveformCard(style: style, seed: UInt64(index * 17 + 3), selected: selection == style) {
                    selection = style
                }
            }
        }
    }
}

private struct WaveformCard: View {
    let style: WaveformStyle
    let seed: UInt64
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                WaveformPreview(style: style, seed: seed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(style.title).font(.system(size: 13, weight: .semibold))
                        if style == .conveyor {
                            Text("Default")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(style.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) waveform")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Recording window styles

/// Pictures of the real recording windows (the same layers the app puts on screen),
/// rendered once per window and waveform style.
enum RecordingWindowThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(for style: RecordingWindowStyle, waveform: WaveformStyle) -> NSImage? {
        let key = "\(style.rawValue).\(waveform.rawValue)"
        if let cached = cache[key] { return cached }
        let view: RecordingWindowView
        switch style {
        case .classic: view = ClassicRecordingView(stopKeys: DictationController.keys(for: .pushToTalk), style: waveform)
        case .mini: view = MiniRecordingView(style: waveform)
        case .none: return nil
        }
        view.mode = .recording
        var speech = SyntheticSpeech(seed: 11)
        speech.prefill(70) { view.push(level: $0) }

        let crop = view.surfaceFrame.insetBy(dx: -8, dy: -8)
        let scale: CGFloat = 2
        guard let context = CGContext(
            data: nil, width: Int(crop.width * scale), height: Int(crop.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let root = view.layer else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        root.render(in: context)
        guard let cgImage = context.makeImage() else { return nil }
        let image = NSImage(cgImage: cgImage, size: crop.size)
        cache[key] = image
        return image
    }
}
