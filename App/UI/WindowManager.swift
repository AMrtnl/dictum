import AppKit
import SwiftUI

/// Opens Dictum's few windows. AppKit-managed so a menu-bar-only app can bring them
/// to the front reliably; each window is released when closed, freeing its memory.
final class WindowManager: NSObject, NSWindowDelegate {
    /// `home`, `settings` and `history` are pages of the one main window.
    enum Kind { case home, settings, history, onboarding }

    private enum WindowID { case main, onboarding }

    static let shared = WindowManager()

    private var windows: [WindowID: NSWindow] = [:]

    func show(_ kind: Kind) {
        let id: WindowID
        switch kind {
        case .onboarding: id = .onboarding
        case .home: id = .main; MainNavigation.shared.page = .home
        case .settings: id = .main; MainNavigation.shared.page = .configuration
        case .history: id = .main; MainNavigation.shared.page = .history
        }
        let window = windows[id] ?? make(id)
        windows[id] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: Kind) {
        windows[kind == .onboarding ? .onboarding : .main]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        if id == .onboarding { AppSettings.shared.hasCompletedOnboarding = true }
        // A menu-bar app stays active after its last window closes, leaving no app to
        // paste into; hiding hands focus back to the app the user was working in.
        if windows.isEmpty {
            DispatchQueue.main.async { NSApp.hide(nil) }
        }
    }

    private func make(_ id: WindowID) -> NSWindow {
        let window: NSWindow
        switch id {
        case .main:
            window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView()))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.title = "Dictum"
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 940, height: 660))
            window.setFrameAutosaveName("DictumMain")
        case .onboarding:
            let controller = NSHostingController(rootView: OnboardingView())
            controller.sizingOptions = .preferredContentSize
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = "Welcome to Dictum"
            window.titleVisibility = .hidden
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        if id == .onboarding || !window.setFrameUsingName("DictumMain") { window.center() }
        return window
    }
}

#if DEBUG
extension WindowManager {
    /// Renders each window's content offscreen to PNGs for design review, in light and dark:
    /// `open Dictum.app --args -snapshotUI /path/to/dir`
    func snapshot(to directory: URL) {
        let views: [(String, AnyView)] = [
            ("onboarding", AnyView(OnboardingView())),
            ("main", AnyView(MainWindowView().frame(width: 940, height: 660))),
            ("home", AnyView(HomeView().frame(width: 700, height: 640))),
            ("modes", AnyView(ModesPage().frame(width: 700, height: 360))),
            ("vocabulary", AnyView(VocabularyView().frame(width: 700, height: 420))),
            ("configuration", AnyView(ConfigurationPage().frame(width: 700, height: 980))),
            ("sound", AnyView(SoundPage().frame(width: 700, height: 300))),
            ("models", AnyView(ModelSettings().frame(width: 700, height: 640))),
            ("history", AnyView(HistoryPage().frame(width: 700, height: 420))),
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
