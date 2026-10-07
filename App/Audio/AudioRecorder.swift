import AVFoundation
import CoreAudio
import os

/// Records the microphone as 16 kHz mono while a dictation runs. The engine exists
/// only between `start` and `stop`, so the mic (and its orange indicator) is off the
/// rest of the time. Audio streams to a WAV file as it arrives, so a long hands-free
/// dictation costs disk, not memory, and a crash still leaves the audio behind.
final class AudioRecorder {
    struct Take {
        let url: URL
        let duration: TimeInterval
        /// Loudest 30 Hz level window, 0…1; near zero means nothing was said.
        let peakLevel: Float
    }

    enum RecorderError: LocalizedError {
        case noInput, file

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone is available."
            case .file: "Could not create the recording file."
            }
        }
    }

    nonisolated static let sampleRate = 16_000.0
    nonisolated static let maxDuration: TimeInterval = 60 * 60

    private var engine: AVAudioEngine?
    private var sink: CaptureSink?

    var isRecording: Bool { engine != nil }

    /// - Parameters:
    ///   - onLevel: called on the main thread at most 30 times a second.
    ///   - onLimit: called on the main thread if the take reaches `maxDuration`.
    func start(deviceUID: String?, onLevel: @escaping @MainActor (Float) -> Void,
               onLimit: @escaping @MainActor () -> Void = {}) throws {
        stopEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, let device = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw RecorderError.noInput }
        try FileManager.default.createDirectory(at: Paths.takes, withIntermediateDirectories: true)
        let url = Paths.takes.appending(path: "\(UUID().uuidString).wav")
        guard let sink = CaptureSink(inputFormat: format, file: url, onLevel: onLevel, onLimit: onLimit)
        else { throw RecorderError.file }

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(into: sink))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            _ = sink.finish()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        self.engine = engine
        self.sink = sink
    }

    /// Stops recording and finalises the WAV file.
    func stop() -> Take? {
        guard let sink else { return nil }
        stopEngine()
        let (count, peak) = sink.finish()
        guard count > 0 else {
            try? FileManager.default.removeItem(at: sink.url)
            return nil
        }
        return Take(url: sink.url, duration: Double(count) / Self.sampleRate, peakLevel: peak)
    }

    func cancel() {
        guard let sink else { return }
        stopEngine()
        _ = sink.finish()
        try? FileManager.default.removeItem(at: sink.url)
    }

    /// Built outside the main actor: the block runs on the realtime audio thread.
    nonisolated private static func tap(into sink: CaptureSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        sink = nil
    }
}

/// Runs on the audio thread: converts each buffer to 16 kHz mono 16-bit, hands it to a
/// background queue that appends it to the WAV file, and reports a throttled level.
nonisolated private final class CaptureSink: @unchecked Sendable {
    let url: URL
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double
    private let onLevel: @MainActor (Float) -> Void
    private let onLimit: @MainActor () -> Void
    private let handle: FileHandle
    private let writer = DispatchQueue(label: "ch.martinoli.dictum.wav-writer", qos: .userInitiated)
    private let lock = OSAllocatedUnfairLock()
    private var pending = Data()
    private var count = 0
    private var peak: Float = 0
    private var windowLevel: Float = 0
    private var lastReport: UInt64 = 0
    private var finished = false

    private static let reportInterval: UInt64 = 33_000_000  // ns, ~30 Hz
    private static let flushBytes = 32_000  // ~1 s of audio per disk write
    private static let maxSamples = Int(AudioRecorder.sampleRate * AudioRecorder.maxDuration)

    init?(inputFormat: AVAudioFormat, file: URL, onLevel: @escaping @MainActor (Float) -> Void,
          onLimit: @escaping @MainActor () -> Void) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: output),
              FileManager.default.createFile(atPath: file.path, contents: WAV.header(dataBytes: 0)),
              let handle = try? FileHandle(forWritingTo: file)
        else { return nil }
        _ = try? handle.seekToEnd()
        self.url = file
        self.converter = converter
        self.outputFormat = output
        self.ratio = AudioRecorder.sampleRate / inputFormat.sampleRate
        self.onLevel = onLevel
        self.onLimit = onLimit
        self.handle = handle
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
        var pcm = Data(count: frames.count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for (i, sample) in frames.enumerated() {
                sumOfSquares += sample * sample
                out[i] = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
            }
        }
        let rms = frames.isEmpty ? 0 : (sumOfSquares / Float(frames.count)).squareRoot()
        let level = Self.normalized(rms)

        let now = DispatchTime.now().uptimeNanoseconds
        let (report, flush, hitLimit): (Float?, Data?, Bool) = lock.withLockUnchecked {
            guard !finished else { return (nil, nil, false) }
            var hitLimit = false
            if count < Self.maxSamples {
                pending.append(pcm)
                count += frames.count
                hitLimit = count >= Self.maxSamples
            }
            var flush: Data?
            if pending.count >= Self.flushBytes {
                flush = pending
                pending = Data()
            }
            windowLevel = max(windowLevel, level)
            guard now - lastReport >= Self.reportInterval else { return (nil, flush, hitLimit) }
            lastReport = now
            let value = windowLevel
            peak = max(peak, value)
            windowLevel = 0
            return (value, flush, hitLimit)
        }
        if let flush {
            let handle = self.handle
            writer.async { try? handle.write(contentsOf: flush) }
        }
        if let report {
            let onLevel = self.onLevel
            DispatchQueue.main.async { onLevel(report) }
        }
        if hitLimit {
            let onLimit = self.onLimit
            DispatchQueue.main.async { onLimit() }
        }
    }

    /// Writes what's left, fixes the WAV header sizes, closes the file.
    func finish() -> (samples: Int, peak: Float) {
        let (rest, total, loudest): (Data, Int, Float) = lock.withLock {
            let rest = pending
            pending = Data()
            finished = true
            return (rest, count, max(peak, windowLevel))
        }
        let handle = self.handle
        writer.sync {
            try? handle.write(contentsOf: rest)
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: WAV.header(dataBytes: total * 2))
            try? handle.close()
        }
        return (total, loudest)
    }

    /// Maps RMS to 0…1 on a -55…-10 dBFS scale, which reads well for speech.
    private static func normalized(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db + 55) / 45, 0), 1)
    }
}

nonisolated enum WAV {
    /// 44-byte header for 16 kHz mono 16-bit PCM.
    static func header(dataBytes: Int, sampleRate: Int = Int(AudioRecorder.sampleRate)) -> Data {
        var data = Data(capacity: 44)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(dataBytes))
        return data
    }
}
