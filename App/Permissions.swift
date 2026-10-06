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
    }

    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
