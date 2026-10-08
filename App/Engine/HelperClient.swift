import Darwin
import Foundation

nonisolated struct HelperRequest: Encodable, Sendable {
    var id = 1
    var op: String
    var path: String?
    var language: String?
    var text: String?
    var model: String?
    var vocabulary: [String]?
    var rewrite: Bool?
    var asrIdle: Int?
    var rewriteIdle: Int?

    enum CodingKeys: String, CodingKey {
        case id, op, path, language, text, model, vocabulary, rewrite
        case asrIdle = "asr_idle", rewriteIdle = "rewrite_idle"
    }
}

/// Every line the helper sends: a progress event or a final response.
nonisolated struct HelperMessage: Decodable, Sendable {
    var ok: Bool?
    var error: String?
    var text: String?
    var applied: Bool?
    var seconds: Double?
    var language: String?
    var models: [String: String]?
    var rewrite: String?
    var event: String?
    var model: String?
    var phase: String?
    var fraction: Double?
}

enum HelperError: LocalizedError {
    case connect(Int32)
    case io(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .connect(let code): "Could not reach the speech engine (\(String(cString: strerror(code))))."
        case .io(let message): "Speech engine connection failed: \(message)"
        case .failed(let message): message
        }
    }
}

/// One request per Unix-socket connection: write a JSON line, read lines until the
/// final response. Blocking I/O, so it always runs off the main thread.
enum HelperClient {
    nonisolated static func send(
        _ request: HelperRequest,
        socketPath: String,
        timeout: TimeInterval?,
        onEvent: (@Sendable (HelperMessage) -> Void)? = nil
    ) async throws -> HelperMessage {
        try await Task.detached(priority: .userInitiated) {
            try roundTrip(request, socketPath: socketPath, timeout: timeout, onEvent: onEvent)
        }.value
    }

    nonisolated private static func roundTrip(
        _ request: HelperRequest,
        socketPath: String,
        timeout: TimeInterval?,
        onEvent: (@Sendable (HelperMessage) -> Void)?
    ) throws -> HelperMessage {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HelperError.connect(errno) }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            _ = socketPath.utf8CString.withUnsafeBytes { path in
                memcpy(buffer.baseAddress!, path.baseAddress!, min(path.count, capacity - 1))
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw HelperError.connect(errno) }

        if let timeout {
            var value = timeval(tv_sec: Int(timeout), tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        try payload.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let n = write(fd, bytes.baseAddress! + sent, bytes.count - sent)
                guard n > 0 else { throw HelperError.io(String(cString: strerror(errno))) }
                sent += n
            }
        }

        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let decoder = JSONDecoder()
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n == 0 { throw HelperError.io("the speech engine closed the connection") }
            if n < 0 {
                let code = errno
                throw HelperError.io(code == EAGAIN ? "timed out" : String(cString: strerror(code)))
            }
            pending.append(contentsOf: chunk[0..<n])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                let message = try decoder.decode(HelperMessage.self, from: line)
                if message.event != nil {
                    onEvent?(message)
                    continue
                }
                if message.ok == true { return message }
                throw HelperError.failed(message.error ?? "The speech engine reported an error.")
            }
        }
    }
}
