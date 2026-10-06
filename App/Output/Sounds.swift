import AppKit

/// Short system sounds for start / stop / nothing-heard, preloaded once.
enum Sounds {
    private static let start = NSSound(named: "Tink")
    private static let stop = NSSound(named: "Pop")
    private static let empty = NSSound(named: "Basso")

    static func playStart() { play(start) }
    static func playStop() { play(stop) }
    static func playEmpty() { play(empty) }

    private static func play(_ sound: NSSound?) {
        guard AppSettings.shared.playSounds, let sound else { return }
        sound.stop()
        sound.volume = 0.35
        sound.play()
    }
}
