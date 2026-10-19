import Foundation
import Darwin

enum LocalCoreTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    /// A single-request Unix socket fixture; it never opens an IP socket.
    private final class FixtureServer: @unchecked Sendable {
        let path: String
        private let descriptor: Int32
        private let done = DispatchSemaphore(value: 0)
        private var request = Data()
        private var failure: Error?

        init(path: String) throws {
            self.path = path
            descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw Failure(description: "Fixture socket creation failed") }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(descriptor)
                throw Failure(description: "Fixture path exceeds Unix socket limit")
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0, Darwin.listen(descriptor, 1) == 0 else {
                Darwin.close(descriptor)
                throw Failure(description: "Fixture socket bind/listen failed")
            }
        }

        func serve(_ body: Data) {
            DispatchQueue.global().async { [self] in
                defer { Darwin.close(descriptor); done.signal() }
                do {
                    try ready(descriptor, events: Int16(POLLIN))
                    let client = Darwin.accept(descriptor, nil, nil)
                    guard client >= 0 else { throw Failure(description: "Fixture accept failed") }
                    defer { Darwin.close(client) }
                    var noSigPipe: Int32 = 1
                    _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                    let terminator = Data("\r\n\r\n".utf8)
                    var buffer = [UInt8](repeating: 0, count: 1_024)
                    while request.range(of: terminator) == nil {
                        try ready(client, events: Int16(POLLIN))
                        let count = buffer.withUnsafeMutableBytes { Darwin.recv(client, $0.baseAddress, $0.count, 0) }
                        guard count > 0, request.count + count <= 4_096 else {
                            throw Failure(description: "Fixture received an incomplete or oversized request")
                        }
                        request.append(contentsOf: buffer.prefix(count))
                    }
                    var response = Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                    response.append(body)
                    var sent = 0
                    while sent < response.count {
                        try ready(client, events: Int16(POLLOUT))
                        let count = response.withUnsafeBytes {
                            Darwin.send(client, $0.baseAddress!.advanced(by: sent), response.count - sent, 0)
                        }
                        guard count > 0 else { throw Failure(description: "Fixture response send failed") }
                        sent += count
                    }
                } catch {
                    failure = error
                }
            }
        }

        func receivedRequest() throws -> Data {
            guard done.wait(timeout: .now() + 6) == .success else {
                throw Failure(description: "Fixture did not finish")
            }
            if let failure { throw failure }
            return request
        }

        private func ready(_ fd: Int32, events: Int16) throws {
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            guard Darwin.poll(&descriptor, 1, 6_000) > 0 else {
                throw Failure(description: "Fixture socket wait failed")
            }
        }
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let body = Data(#"""
        {"proxies":{
          "Group":{"type":"Selector","now":"Nested","all":["Nested"]},
          "Nested":{"type":"URLTest","now":"🇯🇵 Tokyo","all":["🇯🇵 Tokyo"]},
          "🇯🇵 Tokyo":{"type":"Shadowsocks","alive":true,"history":[
            {"delay":42,"time":"2026-10-19T11:12:13.123456789Z"},
            {"delay":0,"time":"invalid"}]},
          "Untested":{"type":"Shadowsocks","history":[]},
          "Cycle":{"type":"Selector","now":"Cycle","all":["Cycle"]},
          "Direct Group":{"type":"Selector","now":"DIRECT","all":["DIRECT"]},
          "DIRECT":{"type":"Direct","history":[]},
          "REJECT":{"type":"Reject","history":[]}
        }}
        """#.utf8)
        let fixture = try FixtureServer(path: directory.appendingPathComponent("core.sock").path)
        fixture.serve(body)
        let snapshot = try LocalMihomoClient(path: fixture.path).fetchSnapshot()
        let request = try fixture.receivedRequest()
        let expected = Data("GET /proxies HTTP/1.0\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
        try expect(request == expected, "A poll sends exactly one snapshot GET, including when history is empty")
        try expect(Set(snapshot.selectableNodes.map(\.name)) == Set(["Untested", "🇯🇵 Tokyo"]),
                   "Only actual leaf nodes appear in the node picker")
        try expect(snapshot.selectableGroups.count == 4, "Strategy groups appear in their own picker")

        switch snapshot.resolve(MonitorSelection(kind: .group, name: "Group")) {
        case .resolved(let result):
            try expect(result.terminalName == "🇯🇵 Tokyo", "Nested groups resolve to the chosen leaf")
            try expect(result.chain == ["Group", "Nested", "🇯🇵 Tokyo"], "Resolution preserves the selection chain")
            try expect(result.proxy.name == "🇯🇵 Tokyo", "Proxy lookup keys supply canonical names")
            try expect(result.proxy.history.first?.time != nil, "Nanosecond ISO history timestamps parse")
            try expect(result.proxy.history.last?.time == nil, "Unknown timestamps stay unknown")
            try expect(result.proxy.alive == true, "Optional controller alive state is decoded")
        default: throw Failure(description: "Nested selection did not resolve")
        }
        switch snapshot.resolve(MonitorSelection(kind: .node, name: "Untested")) {
        case .resolved(let result): try expect(result.proxy.history.isEmpty, "Empty histories remain empty without probing")
        default: throw Failure(description: "A node with no history did not resolve")
        }
        switch snapshot.resolve(MonitorSelection(kind: .group, name: "Cycle")) {
        case .cycle(let chain): try expect(chain == ["Cycle", "Cycle"], "Group cycles terminate with their chain")
        default: throw Failure(description: "Group cycle was not detected")
        }
        switch snapshot.resolve(MonitorSelection(kind: .node, name: "Missing")) {
        case .missing(let name): try expect(name == "Missing", "Missing names are preserved")
        default: throw Failure(description: "Missing node was not reported")
        }
        let implicitDirect = ProxySnapshot(proxies: [
            "Direct Group": MihomoProxy(name: "Direct Group", type: "Selector", now: "DIRECT", all: ["DIRECT"])
        ])
        switch implicitDirect.resolve(MonitorSelection(kind: .group, name: "Direct Group")) {
        case .resolved(let result):
            try expect(result.terminalName == "DIRECT" && result.proxy.isSynthetic,
                       "Built-in DIRECT terminals resolve even if absent from the snapshot")
        default: throw Failure(description: "Synthetic DIRECT terminal did not resolve")
        }
        try expect(NodeLabel.flag(in: "Test 🇯🇵 Tokyo") == "🇯🇵", "Flags come directly from regional indicators")
        try expect(NodeLabel.flag(in: "🌎 Tokyo") == nil, "Other emoji are not interpreted as country flags")
        try expect(NodeLabel.shortName("  Tokyo  ") == "Tokyo", "Unflagged names have a compact text fallback")
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProxySnapshot.self, from: encoded)
        try expect(decoded.proxies.count == 8, "Snapshots support Codable roundtrips")
        do {
            _ = try LocalMihomoClient(path: directory.appendingPathComponent("missing.sock").path).fetchSnapshot()
            throw Failure(description: "A missing local socket unexpectedly succeeded")
        } catch LocalMihomoError.unavailable { }
    }
}
