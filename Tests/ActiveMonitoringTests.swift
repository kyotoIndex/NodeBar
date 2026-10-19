import Foundation
import Darwin

enum ActiveMonitoringTests {
    private struct Failure: Error, CustomStringConvertible { let description: String }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    /// Models only Mihomo's Unix HTTP interface, including concurrent delay requests.
    private final class Server: @unchecked Sendable {
        let path: String
        private let fd: Int32
        private let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var requests: [String] = []
        private var errors: [Error] = []
        private var active = 0
        private var maximum = 0
        private let snapshot: Data
        private let cancellationOnProbe: ProbeCancellation?

        init(path: String, snapshot: ProxySnapshot, cancellationOnProbe: ProbeCancellation? = nil) throws {
            self.path = path
            self.cancellationOnProbe = cancellationOnProbe
            self.snapshot = try JSONEncoder().encode(snapshot)
            fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw Failure(description: "Create Unix fixture failed") }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(fd)
                throw Failure(description: "Fixture socket path is too long")
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, Darwin.listen(fd, 16) == 0 else {
                Darwin.close(fd)
                throw Failure(description: "Bind fixture failed")
            }
        }

        func start(requestCount: Int) {
            DispatchQueue.global().async { [self] in
                let pending = DispatchGroup()
                defer { Darwin.close(fd); done.signal() }
                do {
                    for _ in 0..<requestCount {
                        try Self.ready(fd, Int16(POLLIN))
                        let connection = Darwin.accept(fd, nil, nil)
                        guard connection >= 0 else { throw Failure(description: "Accept fixture connection failed") }
                        pending.enter()
                        DispatchQueue.global().async { [self] in
                            defer { pending.leave(); Darwin.close(connection) }
                            do { try handle(connection) }
                            catch { lock.lock(); errors.append(error); lock.unlock() }
                        }
                    }
                } catch { lock.lock(); errors.append(error); lock.unlock() }
                if pending.wait(timeout: .now() + 6) != .success {
                    lock.lock(); errors.append(Failure(description: "Fixture handlers stalled")); lock.unlock()
                }
            }
        }

        private func handle(_ connection: Int32) throws {
            var noSigPipe: Int32 = 1
            _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var request = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while request.range(of: Data("\r\n\r\n".utf8)) == nil {
                try Self.ready(connection, Int16(POLLIN))
                let count = buffer.withUnsafeMutableBytes { Darwin.recv(connection, $0.baseAddress, $0.count, 0) }
                guard count > 0, request.count + count < 8_192 else { throw Failure(description: "Invalid fixture request") }
                request.append(contentsOf: buffer.prefix(count))
            }
            guard let text = String(data: request, encoding: .utf8), let line = text.components(separatedBy: "\r\n").first else {
                throw Failure(description: "Invalid request encoding")
            }
            let isProbe = line != "GET /proxies HTTP/1.0"
            lock.lock()
            requests.append(text)
            if isProbe { active += 1; maximum = max(maximum, active) }
            lock.unlock()
            defer { if isProbe { lock.lock(); active -= 1; lock.unlock() } }
            let status: Int
            let body: Data
            if !isProbe { status = 200; body = snapshot }
            else {
                cancellationOnProbe?.cancel()
                // Let the first wave overlap so the four-request bound is observable.
                Thread.sleep(forTimeInterval: line.contains("/Slow/") ? 5.2 : 0.06)
                if line.contains("/Failed/") { status = 503; body = Data(#"{"message":"connection refused"}"#.utf8) }
                else if line.contains("/TimedOut/") { status = 504; body = Data(#"{"message":"timeout"}"#.utf8) }
                else if line.contains("/Auth/") { status = 401; body = Data(#"{"message":"unauthorized"}"#.utf8) }
                else if line.contains("/Malformed/") { status = 200; body = Data(#"{"delay":-1}"#.utf8) }
                else if line.contains("/Zero/") { status = 200; body = Data(#"{"delay":0}"#.utf8) }
                else { status = 200; body = Data(#"{"delay":42}"#.utf8) }
            }
            var response = Data("HTTP/1.0 \(status) Fixture\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            response.append(body)
            var sent = 0
            while sent < response.count {
                try Self.ready(connection, Int16(POLLOUT))
                let count = response.withUnsafeBytes {
                    Darwin.send(connection, $0.baseAddress!.advanced(by: sent), response.count - sent, 0)
                }
                guard count > 0 else { throw Failure(description: "Fixture write failed") }
                sent += count
            }
        }

        func finish() throws -> (requests: [String], maximum: Int) {
            guard done.wait(timeout: .now() + 7) == .success else { throw Failure(description: "Fixture did not finish") }
            lock.lock()
            defer { lock.unlock() }
            if let error = errors.first { throw error }
            return (requests, maximum)
        }

        private static func ready(_ descriptor: Int32, _ events: Int16) throws {
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            guard Darwin.poll(&item, 1, 5_000) > 0 else { throw Failure(description: "Fixture request timed out") }
        }
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nba-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let leafName = "JP / A?%#&"
        let names = [leafName, "Failed", "TimedOut", "Auth", "Malformed", "Zero"]
        var proxies = Dictionary(uniqueKeysWithValues: names.map {
            ($0, MihomoProxy(name: $0, type: "Shadowsocks", history: [ProxyHistory(delay: 999, time: .distantPast)]))
        })
        proxies["Group"] = MihomoProxy(name: "Group", type: "Selector", now: "Nested", all: ["Nested"])
        proxies["Nested"] = MihomoProxy(name: "Nested", type: "URLTest", now: leafName, all: [leafName])
        proxies["Unused"] = MihomoProxy(name: "Unused", type: "Shadowsocks")
        proxies["DIRECT"] = MihomoProxy(name: "DIRECT", type: "Direct")
        proxies["REJECT"] = MihomoProxy(name: "REJECT", type: "Reject")
        proxies["Pass alias"] = MihomoProxy(name: "Pass alias", type: "Pass")
        let snapshot = ProxySnapshot(proxies: proxies)
        let server = try Server(path: directory.appendingPathComponent("probe.sock").path, snapshot: snapshot)
        server.start(requestCount: names.count + 1)
        let client = LocalMihomoClient(path: server.path)
        let start = Date()
        let selections = names.map { MonitorSelection(kind: .node, name: $0) } + [
            MonitorSelection(kind: .group, name: "Group"), MonitorSelection(kind: .group, name: "Nested"),
            MonitorSelection(kind: .node, name: "DIRECT"), MonitorSelection(kind: .node, name: "REJECT"),
            MonitorSelection(kind: .node, name: "Pass alias")
        ]
        let batch = try client.fetchMonitoringBatch(selections: selections)
        let observed = try server.finish()
        try expect(batch.snapshot.proxies.count == snapshot.proxies.count, "Batch supplies its fresh snapshot")
        try expect(batch.results[leafName]?.state == .success(42), "Explicit probe success replaces old 999ms history")
        try expect(batch.results["Failed"]?.state == .failed, "503 means a node failure")
        try expect(batch.results["TimedOut"]?.state == .timedOut, "504 means a node timeout")
        try expect(batch.results["Auth"]?.state == .localFailure(.unavailable), "Controller rejection is not a failed node")
        try expect(batch.results["Malformed"]?.state == .localFailure(.invalidResponse), "Invalid success bodies are local protocol errors")
        try expect(batch.results["Zero"]?.state == .failed, "A zero delay is treated as a failed health check")
        try expect(batch.results["DIRECT"]?.state == .unsupported && batch.results["REJECT"]?.state == .unsupported &&
                   batch.results["Pass alias"]?.state == .unsupported, "Synthetic proxies are refused locally")
        try expect(batch.results["Unused"] == nil && batch.results["Group"] == nil, "Only selected terminal nodes have probe results")
        try expect(batch.results.values.allSatisfy { $0.checkedAt >= start }, "Every result has this cycle's completion time")
        try expect(observed.requests.count == 7, "One snapshot and six deduplicated leaf requests")
        try expect(observed.maximum >= 2 && observed.maximum <= 4, "Delay requests overlap with a maximum of four")
        let expected = "GET /proxies/JP%20%2F%20A%3F%25%23%26/delay?url=https%3A%2F%2Fcp.cloudflare.com%2Fgenerate_204&timeout=10000&expected=204 HTTP/1.0\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
        try expect(observed.requests.filter { $0 == expected }.count == 1, "Encoded leaf path and fixed HTTPS target are exact and deduplicated")
        try expect(observed.requests.first?.hasPrefix("GET /proxies HTTP/1.0\r\n") == true, "Snapshot precedes all probes")
        let slowServer = try Server(path: directory.appendingPathComponent("slow.sock").path, snapshot: snapshot)
        slowServer.start(requestCount: 1)
        let slow = LocalMihomoClient(path: slowServer.path).probe(proxy: MihomoProxy(name: "Slow", type: "Socks5"))
        let slowObserved = try slowServer.finish()
        try expect(slow.state == .success(42), "A valid chained/unified delay response may take over five seconds")
        try expect(slowObserved.requests.first?.contains("timeout=10000") == true,
                   "Mihomo's timeout and the longer local response deadline must agree")
        let unavailable = LocalMihomoClient(path: directory.appendingPathComponent("missing.sock").path)
        let preCancelled = ProbeCancellation()
        preCancelled.cancel()
        try expect(unavailable.probeSelections(selections, snapshot: snapshot, cancellation: preCancelled).isEmpty,
                   "A cancelled cycle starts no leaf requests, even when the controller is unavailable")

        let queuedNames = (0..<12).map { String(format: "Queued%02d", $0) }
        let queuedSnapshot = ProxySnapshot(proxies: Dictionary(uniqueKeysWithValues: queuedNames.map {
            ($0, MihomoProxy(name: $0, type: "Shadowsocks"))
        }))
        let queuedCancellation = ProbeCancellation()
        let cancellationServer = try Server(path: directory.appendingPathComponent("cancel.sock").path,
                                            snapshot: queuedSnapshot, cancellationOnProbe: queuedCancellation)
        // The first accepted probe cancels the cycle. Other first-wave requests may
        // already be connected; the controller fixture closes those without replying.
        cancellationServer.start(requestCount: 1)
        let partial = LocalMihomoClient(path: cancellationServer.path).probeSelections(
            queuedNames.map { MonitorSelection(kind: .node, name: $0) }, snapshot: queuedSnapshot,
            cancellation: queuedCancellation)
        let cancelledObservation = try cancellationServer.finish()
        try expect(queuedCancellation.isCancelled && cancelledObservation.requests.count == 1,
                   "The controller fixture cancels the cycle on its first request")
        try expect(!partial.isEmpty && partial.count <= 4,
                   "Cancellation allows the already-started wave to finish and skips all queued nodes")

        let unsupportedGroup = MihomoProxy(name: "Malformed Group", type: "Fallback")
        try expect(unavailable.probe(proxy: unsupportedGroup).state == .unsupported, "A group is refused even when now/all is absent")
        try expect(unavailable.probe(proxy: MihomoProxy(name: "Node", type: "Shadowsocks")).state == .localFailure(.unavailable),
                   "Missing local controller is distinct from node failure")
    }
}
