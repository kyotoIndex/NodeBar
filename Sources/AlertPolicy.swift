import Foundation

enum MonitoringState: Equatable, Sendable {
    case healthy(delay: Int, time: Date)
    case failed(time: Date)
    case timedOut(time: Date)
    case unsupported
    case checking
    case stale(lastTime: Date?, delay: Int? = nil)
    case noHistory
    case missing
    case invalidGroup
    case direct
    case rejected

    enum Kind: String, Sendable {
        case healthy, failed, timedOut, unsupported, checking, stale, noHistory, missing, invalidGroup, direct, rejected
    }

    var kind: Kind {
        switch self {
        case .healthy: return .healthy
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .unsupported: return .unsupported
        case .checking: return .checking
        case .stale: return .stale
        case .noHistory: return .noHistory
        case .missing: return .missing
        case .invalidGroup: return .invalidGroup
        case .direct: return .direct
        case .rejected: return .rejected
        }
    }

    var sampleTime: Date? {
        switch self {
        case .healthy(_, let time), .failed(let time), .timedOut(let time): return time
        case .stale(let time, _): return time
        default: return nil
        }
    }

    var barText: String {
        switch self {
        case .healthy(let delay, _): return "\(delay)ms"
        case .failed: return "失败"
        case .timedOut: return "检测超时"
        case .unsupported: return "跳过"
        case .checking: return "…"
        case .stale(_, let delay): return delay.flatMap { $0 > 0 ? "\($0)ms*" : nil } ?? "--"
        case .noHistory: return "--"
        case .missing: return "缺失"
        case .invalidGroup: return "组异常"
        case .direct: return "直连"
        case .rejected: return "拒绝"
        }
    }

    var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        case .timedOut: return "clock"
        case .unsupported: return "nosign"
        case .checking: return "clock"
        case .stale: return "clock"
        case .noHistory: return "minus.circle"
        case .missing: return "questionmark.circle"
        case .invalidGroup: return "arrow.triangle.2.circlepath"
        case .direct: return "arrow.right.circle"
        case .rejected: return "nosign"
        }
    }

    func detailText(formatter: DateFormatter) -> String {
        switch self {
        case .healthy(let delay, let time):
            return "延迟 \(delay) ms · \(formatter.string(from: time))"
        case .failed(let time):
            return "Mihomo 测速失败或超时 · \(formatter.string(from: time))"
        case .timedOut(let time): return "检测地址未在期限内响应 · \(formatter.string(from: time))"
        case .unsupported: return "此项目不执行主动测速"
        case .checking: return "等待本轮主动测速结果"
        case .stale(let lastTime, let delay):
            let value = delay.map { $0 > 0 ? "历史延迟 \($0) ms" : "上次记录为测速失败" } ?? "历史记录"
            let time = lastTime.map { formatter.string(from: $0) } ?? "记录时间未知"
            return "\(value) · 尚未获得新测量 · \(time)"
        case .noHistory: return "暂无延迟记录"
        case .missing: return "节点或策略组选项已不存在"
        case .invalidGroup: return "策略组存在循环引用或无效选择"
        case .direct: return "策略组当前选择直连"
        case .rejected: return "策略组当前选择拒绝连接"
        }
    }

    static func evaluate(_ resolution: MonitorResolution, now: Date = Date(),
                         staleAfter: TimeInterval = 300) -> MonitoringState {
        switch resolution {
        case .missing: return .missing
        case .cycle: return .invalidGroup
        case .resolved(let monitor):
            let proxy = monitor.proxy
            if proxy.name.uppercased() == "DIRECT" || proxy.type.lowercased() == "direct" {
                return .direct
            }
            if proxy.name.uppercased() == "REJECT" || proxy.type.lowercased().hasPrefix("reject") {
                return .rejected
            }
            guard !proxy.isGroup else { return .invalidGroup }
            guard !proxy.history.isEmpty else { return .noHistory }
            // Histories need not arrive in chronological order. Records without a
            // usable timestamp cannot establish a current success or failure.
            guard let record = proxy.history.filter({ $0.time != nil }).max(by: {
                $0.time! < $1.time!
            }), let time = record.time else { return .stale(lastTime: nil, delay: proxy.history.last?.delay) }
            let age = now.timeIntervalSince(time)
            guard age >= -60, age <= staleAfter else { return .stale(lastTime: time, delay: record.delay) }
            return record.delay > 0 ? .healthy(delay: record.delay, time: time) : .failed(time: time)
        }
    }
}

struct AlertEvent: Sendable {
    enum Kind: String, Sendable {
        case outage, recovery, controllerFailure, controllerRecovery
    }

    let kind: Kind
    let monitorID: String?
    let monitorName: String?
    let title: String
    let body: String
}

/// Pure local transition policy. Notification delivery and permission are owned
/// by the app; this type never performs I/O or probes a node.
struct AlertTracker {
    private struct Entry {
        var terminalIdentity: String?
        var reportedOutage: MonitoringState.Kind?
    }

    private var entries: [String: Entry] = [:]
    private var controllerFailed = false

    mutating func update(selection: MonitorSelection, state: MonitoringState,
                         terminalIdentity: String?) -> [AlertEvent] {
        var entry = entries[selection.id] ?? Entry()
        // A group switching nodes starts a new incident context. A temporarily
        // missing terminal retains the previous context until it resolves again.
        if let old = entry.terminalIdentity, let new = terminalIdentity, old != new {
            entry.reportedOutage = nil
        }
        if let terminalIdentity { entry.terminalIdentity = terminalIdentity }

        var events: [AlertEvent] = []
        switch state {
        case .failed, .timedOut, .missing, .invalidGroup:
            let incidentKind: MonitoringState.Kind = state.kind == .timedOut ? .failed : state.kind
            if entry.reportedOutage != incidentKind {
                let body: String
                switch state {
                case .failed, .timedOut: body = "一个监控项目的最新检测显示连接失败或超时。打开 NodeBar 查看详情。"
                case .missing: body = "一个监控项目的节点或策略组选项已不存在。打开 NodeBar 查看详情。"
                default: body = "一个监控项目的策略组无法解析。打开 NodeBar 查看详情。"
                }
                events.append(AlertEvent(kind: .outage, monitorID: selection.id,
                                         monitorName: selection.name, title: "NodeBar · 监控异常", body: body))
                entry.reportedOutage = incidentKind
            }
        case .healthy:
            if entry.reportedOutage != nil {
                events.append(AlertEvent(kind: .recovery, monitorID: selection.id,
                                         monitorName: selection.name, title: "NodeBar · 监控恢复",
                                         body: "一个监控项目已获得正常的延迟记录。打开 NodeBar 查看详情。"))
                entry.reportedOutage = nil
            }
        case .direct, .rejected, .unsupported:
            entry.reportedOutage = nil
        case .stale, .noHistory, .checking:
            // Unknown freshness neither opens nor resolves an outage.
            break
        }
        entries[selection.id] = entry
        return events
    }

    mutating func updateController(error: LocalMihomoError?) -> [AlertEvent] {
        if let error {
            guard !controllerFailed else { return [] }
            controllerFailed = true
            let body: String
            switch error {
            case .timedOut: body = "读取本机 Mihomo 状态超时。打开 NodeBar 查看详情。"
            case .unavailable: body = "无法连接本机 Mihomo。打开 NodeBar 检查连接设置。"
            case .invalidResponse: body = "本机 Mihomo 返回的数据无法读取。打开 NodeBar 查看详情。"
            }
            return [AlertEvent(kind: .controllerFailure, monitorID: nil, monitorName: nil,
                               title: "NodeBar · 本机连接异常", body: body)]
        }
        guard controllerFailed else { return [] }
        controllerFailed = false
        return [AlertEvent(kind: .controllerRecovery, monitorID: nil, monitorName: nil,
                           title: "NodeBar · 本机连接恢复", body: "已恢复读取本机 Mihomo 状态。")]
    }

    mutating func reconcile(selectedIDs: Set<String>) {
        entries = entries.filter { selectedIDs.contains($0.key) }
    }

    mutating func resetMonitorStates() { entries.removeAll() }

    mutating func reset() {
        resetMonitorStates()
        controllerFailed = false
    }
}
