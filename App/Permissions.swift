import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// Microphone and Accessibility status, re-read whenever Dictum becomes active
/// (the user may have just flipped a switch in System Settings).
@Observable
final class Permissions {
    enum Status { case granted, notAsked, denied }

    static let shared = Permissions()

    private(set) var microphone: Status = .notAsked
    private(set) var accessibility: Status = .notAsked

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Permissions.shared.refresh() }
        }
    }

    var allGranted: Bool { microphone == .granted && accessibility == .granted }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        accessibility = AXIsProcessTrusted() ? .granted : .notAsked
    }

    func requestMicrophone() async {
        if microphone == .denied {
            open("Privacy_Microphone")
            return
        }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func requestAccessibility() {
        // Shows the system prompt the first time; afterwards it just opens the pane.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // kAXTrustedCheckOptionPrompt
        if !AXIsProcessTrustedWithOptions(options) {
            open("Privacy_Accessibility")
        }
        refresh()
        watchAccessibility()
    }

    /// macOS can keep an outdated Accessibility entry for an app that has been rebuilt or
    /// reinstalled: it looks switched on but doesn't count. Removing Dictum's entry and
    /// asking again fixes it (only Dictum's own entry is touched).
    func resetAccessibility() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "ch.martinoli.dictum"]
        try? reset.run()
        reset.waitUntilExit()
        requestAccessibility()
    }

    /// The user flips the switch in System Settings while Dictum stays in the background,
    /// so poll briefly (once a second, for up to two minutes) until it takes effect.
    private func watchAccessibility() {
        watchTimer?.invalidate()
        watchDeadline = Date().addingTimeInterval(120)
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Permissions.shared.pollAccessibility() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var watchDeadline = Date.distantPast

    private func pollAccessibility() {
        refresh()
        if accessibility == .granted || Date() > watchDeadline {
            watchTimer?.invalidate()
            watchTimer = nil
        }
    }

    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
