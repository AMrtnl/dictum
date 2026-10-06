import Foundation

/// Where Dictum keeps its Python runtime, models, socket and logs.
enum Paths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Dictum", directoryHint: .isDirectory)
    }()

    static let runtime = support.appending(path: "runtime", directoryHint: .isDirectory)
    static let python = runtime.appending(path: "bin/python")
    static let models = support.appending(path: "models", directoryHint: .isDirectory)
    static let huggingFaceHome = support.appending(path: "hf", directoryHint: .isDirectory)
    static let history = support.appending(path: "history.json")

    /// Unix socket paths are limited to 104 bytes; fall back to /tmp for long home paths.
    static let socket: String = {
        let preferred = support.appending(path: "helper.sock").path
        return preferred.utf8.count < 100 ? preferred : "/tmp/dictum-\(getuid()).sock"
    }()

    static let logs: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Logs/Dictum", directoryHint: .isDirectory)
    }()

    static let takes = FileManager.default.temporaryDirectory.appending(path: "Dictum", directoryHint: .isDirectory)

    static func logFile(_ name: String) -> FileHandle? {
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let url = logs.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
