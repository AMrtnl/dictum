import AppKit
import SwiftUI

/// Opens Dictum's few windows. AppKit-managed so a menu-bar-only app can bring them
/// to the front reliably; each window is released when closed, freeing its memory.
final class WindowManager: NSObject, NSWindowDelegate {
    enum Kind { case settings, onboarding, history }

    static let shared = WindowManager()

    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind) {
        let window = windows[kind] ?? make(kind)
        windows[kind] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key else { return }
        windows[kind] = nil
        if kind == .onboarding { AppSettings.shared.hasCompletedOnboarding = true }
        // A menu-bar app stays active after its last window closes, leaving no app to
        // paste into; hiding hands focus back to the app the user was working in.
        if windows.isEmpty {
            DispatchQueue.main.async { NSApp.hide(nil) }
        }
    }

    private func make(_ kind: Kind) -> NSWindow {
        let window: NSWindow
        switch kind {
        case .settings:
            window = NSWindow(contentViewController: SettingsTabs())
            window.styleMask = [.titled, .closable]
        case .onboarding:
            window = NSWindow(contentViewController: hosting(OnboardingView()))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = "Welcome to Dictum"
            window.titleVisibility = .hidden
        case .history:
            window = NSWindow(contentViewController: hosting(HistoryView()))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.title = "History"
            window.setContentSize(NSSize(width: 620, height: 560))
            window.minSize = NSSize(width: 460, height: 360)
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func hosting(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        return controller
    }
}

#if DEBUG
extension WindowManager {
    /// Renders each window's content offscreen to PNGs for design review, in light and dark:
    /// `open Dictum.app --args -snapshotUI /path/to/dir`
    func snapshot(to directory: URL) {
        let views: [(String, AnyView)] = [
            ("onboarding", AnyView(OnboardingView())),
            ("settings-general", AnyView(GeneralSettings().frame(width: 540))),
            ("settings-recording", AnyView(RecordingSettings().frame(width: 540))),
            ("settings-models", AnyView(ModelSettings().frame(width: 540))),
            ("settings-history", AnyView(HistorySettings().frame(width: 540))),
            ("settings-about", AnyView(AboutSettings().frame(width: 540))),
            ("history", AnyView(HistoryView().frame(width: 620, height: 480))),
        ]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view) in views {
                let host = NSHostingView(rootView: view)
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let suffix = appearance == .darkAqua ? "dark" : "light"
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: directory.appending(path: "\(name)-\(suffix).png"))
                }
                window.orderOut(nil)
            }
        }
    }
}
#endif

/// Classic toolbar-tab preferences window; each tab is a SwiftUI form.
private final class SettingsTabs: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        add("General", "gearshape", GeneralSettings())
        add("Recording", "waveform", RecordingSettings())
        add("Models", "cpu", ModelSettings())
        add("History", "clock.arrow.circlepath", HistorySettings())
        add("About", "info.circle", AboutSettings())
    }

    private func add(_ title: String, _ symbol: String, _ view: some View) {
        let host = NSHostingController(rootView: view.frame(width: 540).fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = .preferredContentSize
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }
}
