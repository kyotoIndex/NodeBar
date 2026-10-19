import Foundation
import Darwin

enum MonitorKind: String, Codable, Sendable {
    case node
    case group
}

struct MonitorSelection: Codable, Hashable, Identifiable, Sendable {
    let kind: MonitorKind
    let name: String

    var id: String { "\(kind.rawValue):\(name)" }
}

struct ProxyHistory: Codable, Sendable {
    let delay: Int
    let time: Date?

    private enum CodingKeys: String, CodingKey { case delay, time }

    init(delay: Int, time: Date?) {
        self.delay = delay
        self.time = time
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        delay = try values.decode(Int.self, forKey: .delay)
        guard delay >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .delay, in: values, debugDescription: "Negative delay")
        }
        let text = try values.decodeIfPresent(String.self, forKey: .time)
        time = text.flatMap(Self.parseTime)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(delay, forKey: .delay)
        if let time {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try values.encode(formatter.string(from: time), forKey: .time)
        }
    }

    private static func parseTime(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

struct MihomoProxy: Codable, Sendable {
    let name: String
    let type: String
    let now: String?
    let all: [String]?
    let history: [ProxyHistory]
    let alive: Bool?

    var isGroup: Bool {
        all != nil || now != nil ||
        ["selector", "fallback", "urltest", "loadbalance", "relay"].contains(type.lowercased())
    }
    var isSynthetic: Bool {
        ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(name.uppercased()) ||
        ["direct", "reject", "rejectdrop", "reject-drop", "pass", "compatible", "dns"].contains(type.lowercased())
    }

    init(name: String, type: String, now: String? = nil, all: [String]? = nil,
         history: [ProxyHistory] = [], alive: Bool? = nil) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.history = history
        self.alive = alive
    }

    private enum CodingKeys: String, CodingKey { case name, type, now, all, history, alive }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try values.decode(String.self, forKey: .type)
        now = try values.decodeIfPresent(String.self, forKey: .now)
        all = try values.decodeIfPresent([String].self, forKey: .all)
        history = try values.decodeIfPresent([ProxyHistory].self, forKey: .history) ?? []
        alive = try values.decodeIfPresent(Bool.self, forKey: .alive)
    }

    fileprivate func named(_ name: String) -> MihomoProxy {
        MihomoProxy(name: name, type: type, now: now, all: all, history: history, alive: alive)
    }
}

struct ResolvedMonitor: Sendable {
    let selection: MonitorSelection
    let terminalName: String
    let proxy: MihomoProxy
    let chain: [String]
}

enum MonitorResolution: Sendable {
    case resolved(ResolvedMonitor)
    case missing(String)
    case cycle([String])
}

struct ProxySnapshot: Codable, Sendable {
    let proxies: [String: MihomoProxy]

    init(proxies: [String: MihomoProxy]) {
        self.proxies = proxies.reduce(into: [:]) { $0[$1.key] = $1.value.named($1.key) }
    }

    private enum CodingKeys: String, CodingKey { case proxies }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try values.decode([String: MihomoProxy].self, forKey: .proxies)
        // The dictionary key is the controller's canonical lookup name.
        proxies = decoded.reduce(into: [:]) { $0[$1.key] = $1.value.named($1.key) }
    }

    var selectableNodes: [MihomoProxy] {
        sortedProxies.filter { !$0.isGroup && !$0.isSynthetic }
    }

    var selectableGroups: [MihomoProxy] { sortedProxies.filter(\.isGroup) }

    private var sortedProxies: [MihomoProxy] {
        proxies.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func resolve(_ selection: MonitorSelection) -> MonitorResolution {
        var name = selection.name
        var chain: [String] = []
        var visited: Set<String> = []

        while true {
            guard visited.insert(name).inserted else { return .cycle(chain + [name]) }
            chain.append(name)
            let proxy: MihomoProxy
            if let found = proxies[name] {
                proxy = found
            } else if name == "DIRECT" || name == "REJECT" {
                proxy = MihomoProxy(name: name, type: name == "DIRECT" ? "Direct" : "Reject")
            } else {
                return .missing(name)
            }

            if proxy.isGroup {
                guard let next = proxy.now, !next.isEmpty else { return .missing(name) }
                name = next
            } else {
                return .resolved(ResolvedMonitor(selection: selection, terminalName: name, proxy: proxy, chain: chain))
            }
        }
    }
}

enum NodeLabel {
    /// Read only regional-indicator pairs already present in a proxy name.
    static func flag(in name: String) -> String? {
        var first: Unicode.Scalar?
        for scalar in name.unicodeScalars {
            if (0x1F1E6...0x1F1FF).contains(scalar.value) {
                if let first { return String(first) + String(scalar) }
                first = scalar
            } else {
                first = nil
            }
        }
        return nil
    }

    static func shortName(_ name: String) -> String {
        if let flag = flag(in: name) { return flag }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "节点" : String(trimmed.prefix(8))
    }
}

enum LocalMihomoError: Error, Equatable, Sendable {
    case unavailable
    case timedOut
    case invalidResponse
}

/// The only transport is a local Unix domain socket. There is no network fallback.
struct LocalMihomoClient: Sendable {
    static var defaultSocketPath: String {
        "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
    }

    let path: String
    let timeout: TimeInterval
    private let maximumResponseBytes = 8 * 1_024 * 1_024

    init(path: String = LocalMihomoClient.defaultSocketPath, timeout: TimeInterval = 5) {
        self.path = path
        self.timeout = timeout.isFinite ? min(30, max(0.1, timeout)) : 5
    }

    func fetchSnapshot() throws -> ProxySnapshot {
        let response = try localGET("/proxies")
        guard response.status == 200 else { throw LocalMihomoError.unavailable }
        do {
            return try JSONDecoder().decode(ProxySnapshot.self, from: response.body)
        } catch {
            throw LocalMihomoError.invalidResponse
        }
    }

    struct HTTPResponse: Sendable {
        let status: Int
        let body: Data
    }

    /// Callers construct only fixed controller paths and percent-encoded components.
    func localGET(_ requestTarget: String) throws -> HTTPResponse {
        guard requestTarget.hasPrefix("/"), !requestTarget.utf8.contains(where: { $0 < 0x21 || $0 > 0x7e }) else {
            throw LocalMihomoError.invalidResponse
        }
        let request = Data("GET \(requestTarget) HTTP/1.0\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
        return try Self.parseResponse(readLocalResponse(request: request))
    }

    private static func parseResponse(_ response: Data) throws -> HTTPResponse {
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              separator.lowerBound <= 65_536,
              let headers = String(data: response[..<separator.lowerBound], encoding: .utf8) else {
            throw LocalMihomoError.invalidResponse
        }
        let lines = headers.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { throw LocalMihomoError.invalidResponse }
        let statusLine = firstLine.split(separator: " ")
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."), let status = Int(statusLine[1]) else {
            throw LocalMihomoError.invalidResponse
        }

        var contentLength: Int?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw LocalMihomoError.invalidResponse }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "transfer-encoding", value.lowercased() != "identity" {
                throw LocalMihomoError.invalidResponse
            }
            if key == "content-length" {
                guard let length = Int(value), length >= 0,
                      contentLength == nil || contentLength == length else {
                    throw LocalMihomoError.invalidResponse
                }
                contentLength = length
            }
        }
        let body = Data(response[separator.upperBound...])
        if let contentLength, contentLength != body.count { throw LocalMihomoError.invalidResponse }
        return HTTPResponse(status: status, body: body)
    }

    private func waitFor(_ events: Int16, fd: Int32, deadline: TimeInterval) throws {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw LocalMihomoError.timedOut }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&descriptor, 1, Int32(ceil(remaining * 1_000)))
            if result > 0 {
                if descriptor.revents & (events | Int16(POLLHUP)) != 0 { return }
                throw LocalMihomoError.unavailable
            }
            if result == 0 { throw LocalMihomoError.timedOut }
            if errno != EINTR { throw LocalMihomoError.unavailable }
        }
    }

    private func readLocalResponse(request: Data) throws -> Data {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw LocalMihomoError.unavailable }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalMihomoError.unavailable }
        defer { Darwin.close(fd) }

        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw LocalMihomoError.unavailable
        }
        var noSigPipe: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw LocalMihomoError.unavailable
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw LocalMihomoError.unavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        // Connecting, writing, and reading share one total deadline.
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN || errno == EINTR else {
                throw LocalMihomoError.unavailable
            }
            try waitFor(Int16(POLLOUT), fd: fd, deadline: deadline)
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0, socketError == 0 else {
                throw LocalMihomoError.unavailable
            }
        }

        var sent = 0
        while sent < request.count {
            try waitFor(Int16(POLLOUT), fd: fd, deadline: deadline)
            let count = request.withUnsafeBytes {
                Darwin.send(fd, $0.baseAddress!.advanced(by: sent), request.count - sent, 0)
            }
            if count > 0 { sent += count }
            else if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            else { throw LocalMihomoError.unavailable }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            try waitFor(Int16(POLLIN), fd: fd, deadline: deadline)
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if count == 0 { return response }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw LocalMihomoError.unavailable
            }
            guard response.count + count <= maximumResponseBytes else { throw LocalMihomoError.invalidResponse }
            response.append(contentsOf: buffer.prefix(count))
        }
    }
}
