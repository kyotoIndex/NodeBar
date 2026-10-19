import Foundation
import Darwin

enum SocketDiscoveryTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(description: message) }
    }

    /// Bind a filesystem Unix socket without accepting requests or contacting a controller.
    private static func bindSocket(_ path: String) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure(description: "Could not create discovery fixture") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(descriptor)
            throw Failure(description: "Discovery fixture path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw Failure(description: "Could not bind discovery fixture")
        }
        return descriptor
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nbd-\(UUID().uuidString.prefix(6))", isDirectory: true)
        let nested = directory.appendingPathComponent("client", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let known = directory.appendingPathComponent("known.sock").path
        let detected = nested.appendingPathComponent("mihomo.sock").path
        let unrelated = directory.appendingPathComponent("unrelated.sock").path
        let descriptors = try [known, detected, unrelated].map(bindSocket)
        defer { descriptors.forEach { Darwin.close($0) } }
        let ordinary = directory.appendingPathComponent("clash.sock")
        try Data("ordinary file".utf8).write(to: ordinary)
        let link = directory.appendingPathComponent("verge-link.sock")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: detected)

        let paths = SocketDiscovery.candidates(preferred: detected,
                                              roots: [directory, directory],
                                              knownPaths: [known, known, ordinary.path])
        try expect(paths == [detected, known], "Explicit socket comes first, candidates are deduplicated, files and links are ignored")
        let scanned = SocketDiscovery.candidates(preferred: nil, roots: [directory], knownPaths: [])
        try expect(scanned.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ==
                   [URL(fileURLWithPath: detected).resolvingSymlinksInPath().path],
                   "Only compatible socket names under this user's roots are discovered")

        let snapshot = ProxySnapshot(proxies: ["Example": MihomoProxy(name: "Example", type: "Selector", now: "Node", all: ["Node"])])
        var attempted: [String] = []
        let found = try SocketDiscovery.resolve(paths: ["/stale.sock", detected, known]) { path, timeout in
            attempted.append(path)
            try expect(timeout > 0 && timeout <= 1, "Discovery gives each candidate at most one second")
            if path == "/stale.sock" { throw LocalMihomoError.unavailable }
            return snapshot
        }
        try expect(found.path == detected && found.snapshot.selectableGroups.count == 1,
                   "Discovery verifies the API and preserves its strategy groups")
        try expect(attempted == ["/stale.sock", detected], "A failed candidate does not block the next candidate")

        var discoveryInvoked = false
        attempted = []
        let manual = try SocketDiscovery.resolve(preferred: known, automatic: false, discover: {
            discoveryInvoked = true
            return [detected]
        }) { path, _ in
            attempted.append(path)
            return snapshot
        }
        try expect(manual.path == known && attempted == [known] && !discoveryInvoked,
                   "Manual mode only contacts the explicitly configured local socket")
        do {
            _ = try SocketDiscovery.resolve(paths: ["/missing.sock"]) { _, _ in throw LocalMihomoError.unavailable }
            throw Failure(description: "Missing controller unexpectedly resolved")
        } catch LocalMihomoError.unavailable { }
    }
}
