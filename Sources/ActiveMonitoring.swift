import Foundation

/// A result from this polling cycle, independent of Mihomo's saved history.
enum ActiveProbeState: Equatable, Sendable {
    case success(Int)
    case failed
    case timedOut
    case unsupported
    case localFailure(LocalMihomoError)
}

struct ActiveProbeResult: Sendable {
    let terminalName: String
    let checkedAt: Date
    let state: ActiveProbeState
}

struct ActiveMonitoringBatch: Sendable {
    let snapshot: ProxySnapshot
    let results: [String: ActiveProbeResult]
}

/// Invalidating a polling cycle prevents its queued probes from starting.
/// Requests that already started are allowed to finish within their existing deadline.
final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

extension LocalMihomoClient {
    static let probeURL = "https://cp.cloudflare.com/generate_204"
    static let probeTimeoutMilliseconds = 10_000

    /// Discover selections from one fresh snapshot, then pin every request to its final leaf.
    /// Controller discovery is read-only; only explicitly selected monitors are probed.
    func fetchMonitoringBatch(selections: [MonitorSelection], timeoutMilliseconds: Int = LocalMihomoClient.probeTimeoutMilliseconds,
                              cancellation: ProbeCancellation? = nil) throws -> ActiveMonitoringBatch {
        let snapshot = try fetchSnapshot()
        return ActiveMonitoringBatch(snapshot: snapshot, results: probeSelections(selections, snapshot: snapshot,
            timeoutMilliseconds: timeoutMilliseconds, cancellation: cancellation))
    }

    func probeSelections(_ selections: [MonitorSelection], snapshot: ProxySnapshot,
                         timeoutMilliseconds: Int = LocalMihomoClient.probeTimeoutMilliseconds,
                         cancellation: ProbeCancellation? = nil) -> [String: ActiveProbeResult] {
        guard cancellation?.isCancelled != true else { return [:] }
        var terminals: [String: MihomoProxy] = [:]
        for selection in selections {
            if case .resolved(let resolved) = snapshot.resolve(selection) {
                terminals[resolved.terminalName] = resolved.proxy
            }
        }
        let proxies = terminals.values.sorted { $0.name < $1.name }
        guard !proxies.isEmpty else { return [:] }
        let results = ProbeResults()
        let workers = min(4, proxies.count)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: proxies.count, by: workers) {
                guard cancellation?.isCancelled != true else { break }
                let proxy = proxies[index]
                results.insert(probe(proxy: proxy, timeoutMilliseconds: timeoutMilliseconds))
            }
        }
        return results.values
    }

    /// Never pass a strategy group to /delay: it could choose another node on failure.
    /// A synthetic terminal is reported locally without issuing a controller request.
    func probe(proxy: MihomoProxy, timeoutMilliseconds: Int = LocalMihomoClient.probeTimeoutMilliseconds) -> ActiveProbeResult {
        func result(_ state: ActiveProbeState) -> ActiveProbeResult {
            ActiveProbeResult(terminalName: proxy.name, checkedAt: Date(), state: state)
        }
        guard !proxy.isGroup, !proxy.isSynthetic else { return result(.unsupported) }
        let budget = min(15_000, max(5_000, timeoutMilliseconds))
        let name = Self.encodeComponent(proxy.name)
        let target = Self.encodeComponent(Self.probeURL)
        let requestTarget = "/proxies/\(name)/delay?url=\(target)&timeout=\(budget)&expected=204"
        do {
            // Mihomo may establish a chain and perform two requests for unified delay.
            // Its returned delay can be much shorter than the full HTTP API duration.
            let controller = LocalMihomoClient(path: path, timeout: Double(budget) / 1_000 + 2)
            let response = try controller.localGET(requestTarget)
            switch response.status {
            case 200:
                struct DelayResponse: Decodable { let delay: Int }
                guard let decoded = try? JSONDecoder().decode(DelayResponse.self, from: response.body), decoded.delay >= 0 else {
                    return result(.localFailure(.invalidResponse))
                }
                return result(decoded.delay == 0 ? .failed : .success(decoded.delay))
            case 503: return result(.failed)
            case 504: return result(.timedOut)
            // A controller/auth/protocol issue must not be announced as a failed node.
            default: return result(.localFailure(.unavailable))
            }
        } catch let error as LocalMihomoError {
            return result(.localFailure(error))
        } catch {
            return result(.localFailure(.invalidResponse))
        }
    }

    /// Encode a single path segment or query value, including '/', '%', '?', and Unicode.
    private static func encodeComponent(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

private final class ProbeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: ActiveProbeResult] = [:]

    func insert(_ result: ActiveProbeResult) {
        lock.lock()
        defer { lock.unlock() }
        stored[result.terminalName] = result
    }

    var values: [String: ActiveProbeResult] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
