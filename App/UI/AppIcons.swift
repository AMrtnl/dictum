import AppKit
import UniformTypeIdentifiers

/// Icons of the apps dictations went into, looked up once each.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// The app's icon, found by bundle ID or else by name; a generic app icon if neither works.
    static func icon(for bundleID: String?, name: String? = nil) -> NSImage {
        let key = bundleID ?? name ?? ""
        if let cached = cache[key] { return cached }
        let url = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? name.flatMap(applicationURL(named:))
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        cache[key] = icon
        return icon
    }

    private static func applicationURL(named name: String) -> URL? {
        ["/Applications", "/System/Applications", "/System/Applications/Utilities",
         NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0).appending(path: "\(name).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
