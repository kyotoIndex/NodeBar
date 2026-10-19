import Foundation
import Darwin

struct SocketDiscoveryResult: Sendable {
    let path: String
    let snapshot: ProxySnapshot
}

/// Discover compatible local controllers by reading their proxy list over Unix sockets.
/// Discovery never reads configuration secrets or opens an IP connection.
enum SocketDiscovery {
    static func candidates(preferred: String? = nil) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"),
            home.appendingPathComponent("Library/Application Support/io.github.zzzgydi.clash-verge"),
            home.appendingPathComponent(".config/mihomo"),
            home.appendingPathComponent(".config/clash"),
            FileManager.default.temporaryDirectory
        ]
        let known = [
            LocalMihomoClient.defaultSocketPath,
            "/tmp/verge/verge-mihomo.sock",
            "/tmp/mihomo.sock",
            "/tmp/clash.sock"
        ]
        return candidates(preferred: preferred, roots: roots, knownPaths: known)
    }

    static func resolve(preferred: String?, automatic: Bool = true) throws -> SocketDiscoveryResult {
        return try resolve(preferred: preferred, automatic: automatic,
                           discover: { candidates(preferred: preferred) }) { path, timeout in
            try LocalMihomoClient(path: path, timeout: timeout).fetchSnapshot()
        }
    }

    static func resolve(preferred: String?, automatic: Bool,
                        discover: () -> [String],
                        fetch: (String, TimeInterval) throws -> ProxySnapshot) throws -> SocketDiscoveryResult {
        let paths = automatic ? discover() : [preferredPath(preferred)]
        return try resolve(paths: paths, fetch: fetch)
    }

    // Injectable roots and fetcher let tests exercise discovery without reading a user's controller.
    static func candidates(preferred: String?, roots: [URL], knownPaths: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        func append(_ path: String) {
            let identity = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            guard !path.isEmpty, seen.insert(identity).inserted else { return }
            result.append(path)
        }
        if let preferred, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(preferred)
        }
        for path in knownPaths where ownedSocket(at: path) { append(path) }

        // Only inspect a small number of entries inside this user's known locations.
        // Never follow directory symlinks or scan another user's temporary directory.
        var remainingEntries = 512
        var scannedDirectories: Set<String> = []
        func scan(_ directory: URL, depth: Int) {
            guard depth <= 2, remainingEntries > 0,
                  scannedDirectories.insert(directory.resolvingSymlinksInPath().standardizedFileURL.path).inserted,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let entries = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard remainingEntries > 0 else { break }
                remainingEntries -= 1
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path),
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { continue }
                let type = attributes[.type] as? FileAttributeType
                if type == .typeSocket {
                    let name = entry.lastPathComponent.lowercased()
                    if ["clash", "mihomo", "verge"].contains(where: name.contains) { append(entry.path) }
                } else if type == .typeDirectory {
                    scan(entry, depth: depth + 1)
                }
            }
        }
        for root in roots { scan(root, depth: 0) }
        return Array(result.prefix(32))
    }

    static func resolve(paths: [String],
                        fetch: (String, TimeInterval) throws -> ProxySnapshot) throws -> SocketDiscoveryResult {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        for path in paths.prefix(32) {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining >= 0.1 else { break }
            do {
                let snapshot = try fetch(path, min(1, remaining))
                return SocketDiscoveryResult(path: path, snapshot: snapshot)
            } catch {
                // An unrelated or stale local socket must not prevent trying the next candidate.
                continue
            }
        }
        throw LocalMihomoError.unavailable
    }

    private static func preferredPath(_ preferred: String?) -> String {
        guard let preferred, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LocalMihomoClient.defaultSocketPath
        }
        return preferred
    }

    private static func ownedSocket(at path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeSocket else { return false }
        return (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    }
}
