import AVFoundation
import Observation

/// Sound's "Test Microphone": opens the chosen input for a few seconds and reports how loud
/// it hears you, so you can check the microphone without dictating. Nothing is recorded,
/// and the microphone closes after 8 seconds or when the page goes away.
@Observable
final class MicrophoneTester {
    private(set) var level: Float = 0
    private(set) var isRunning = false
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func start(deviceUID: String?) {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, let device = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var id = device
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.tap { [weak self] level in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                // Rise fast, fall slowly, like a real meter.
                self.level = level > self.level ? level : self.level * 0.7 + level * 0.3
            }
        })
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        self.engine = engine
        isRunning = true
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        level = 0
    }

    /// Built outside the main actor: the block runs on the audio thread.
    nonisolated private static func tap(_ report: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let decibels = 20 * log10(max((sum / Float(count)).squareRoot(), 1e-6))
            report(min(max((decibels + 55) / 45, 0), 1))  // room noise ≈ 0, loud speech ≈ 1
        }
    }
}
