import AVFoundation
import CoreAudio
import os

/// Records the microphone as 16 kHz mono while a dictation is held.
/// The engine exists only between `start` and `stop`, so the mic (and its
/// orange indicator) is off the rest of the time.
final class AudioRecorder {
    struct Take {
        let url: URL
        let duration: TimeInterval
        /// Loudest 30 Hz level window, 0…1; near zero means nothing was said.
        let peakLevel: Float
    }

    enum RecorderError: LocalizedError {
        case noInput

        var errorDescription: String? { "No microphone is available." }
    }

    nonisolated static let sampleRate = 16_000.0
    nonisolated static let maxDuration: TimeInterval = 10 * 60

    private var engine: AVAudioEngine?
    private var sink: CaptureSink?

    var isRecording: Bool { engine != nil }

    /// - Parameter onLevel: called on the main thread at most 30 times a second.
    func start(deviceUID: String?, onLevel: @escaping @MainActor (Float) -> Void) throws {
        stopEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, let device = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0,
              let sink = CaptureSink(inputFormat: format, onLevel: onLevel)
        else { throw RecorderError.noInput }

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(into: sink))
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.sink = sink
    }

    /// Stops recording and writes the take to a temporary 16-bit WAV file.
    func stop() -> Take? {
        guard let sink else { return nil }
        stopEngine()
        let (samples, peak) = sink.finish()
        guard !samples.isEmpty else { return nil }
        let url = Paths.takes.appending(path: "\(UUID().uuidString).wav")
        do {
            try FileManager.default.createDirectory(at: Paths.takes, withIntermediateDirectories: true)
            try WAV.write(samples, sampleRate: Int(Self.sampleRate), to: url)
        } catch {
            return nil
        }
        return Take(url: url, duration: Double(samples.count) / Self.sampleRate, peakLevel: peak)
    }

    func cancel() {
        stopEngine()
    }

    /// Built outside the main actor: the block runs on the realtime audio thread.
    nonisolated private static func tap(into sink: CaptureSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if sink != nil { sink = nil }
    }
}

/// Runs on the audio thread: converts each buffer to 16 kHz mono, accumulates it,
/// and reports a throttled level to the main thread.
nonisolated private final class CaptureSink: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double
    private let onLevel: @MainActor (Float) -> Void
    private let lock = OSAllocatedUnfairLock()
    private var samples: [Float] = []
    private var peak: Float = 0
    private var windowLevel: Float = 0
    private var lastReport: UInt64 = 0

    private static let reportInterval: UInt64 = 33_000_000  // ns, ~30 Hz
    private static let maxSamples = Int(AudioRecorder.sampleRate * AudioRecorder.maxDuration)

    init?(inputFormat: AVAudioFormat, onLevel: @escaping @MainActor (Float) -> Void) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output)
        else { return nil }
        self.converter = converter
        self.outputFormat = output
        self.ratio = AudioRecorder.sampleRate / inputFormat.sampleRate
        self.onLevel = onLevel
        samples.reserveCapacity(Int(AudioRecorder.sampleRate) * 30)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        let frames = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))

        var sumOfSquares: Float = 0
        for sample in frames { sumOfSquares += sample * sample }
        let rms = frames.isEmpty ? 0 : (sumOfSquares / Float(frames.count)).squareRoot()
        let level = Self.normalized(rms)

        let now = DispatchTime.now().uptimeNanoseconds
        let report: Float? = lock.withLockUnchecked {
            if samples.count < Self.maxSamples { samples.append(contentsOf: frames) }
            windowLevel = max(windowLevel, level)
            guard now - lastReport >= Self.reportInterval else { return nil }
            lastReport = now
            let value = windowLevel
            peak = max(peak, value)
            windowLevel = 0
            return value
        }
        if let report {
            let onLevel = self.onLevel
            DispatchQueue.main.async { onLevel(report) }
        }
    }

    func finish() -> ([Float], Float) {
        lock.withLock { (samples, max(peak, windowLevel)) }
    }

    /// Maps RMS to 0…1 on a -55…-10 dBFS scale, which reads well for speech.
    private static func normalized(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db + 55) / 45, 0), 1)
    }
}

enum WAV {
    static func write(_ samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + payload)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(payload)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        try data.write(to: url)
    }
}
