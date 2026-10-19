import Foundation

enum AlertPolicyTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    static func run() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = MonitorSelection(kind: .group, name: "Private group name")
        func resolve(_ history: [ProxyHistory], terminal: String = "Private node name") -> MonitorResolution {
            .resolved(ResolvedMonitor(selection: selection, terminalName: terminal,
                                      proxy: MihomoProxy(name: terminal, type: "Shadowsocks", history: history),
                                      chain: [selection.name, terminal]))
        }
        func evaluate(_ history: [ProxyHistory]) -> MonitoringState {
            MonitoringState.evaluate(resolve(history), now: now)
        }

        let freshFailure = evaluate([ProxyHistory(delay: 0, time: now)])
        let healthy = evaluate([ProxyHistory(delay: 80, time: now)])
        try expect(freshFailure == .failed(time: now), "Fresh zero-delay record is a failure")
        try expect(healthy == .healthy(delay: 80, time: now), "Fresh positive delay is healthy")
        try expect(evaluate([]) == .noHistory, "Empty history is unknown")
        try expect(evaluate([ProxyHistory(delay: 0, time: nil)]) == .stale(lastTime: nil, delay: 0),
                   "An unknown timestamp cannot establish a failure")
        let old = now.addingTimeInterval(-301)
        try expect(evaluate([ProxyHistory(delay: 0, time: old)]) == .stale(lastTime: old, delay: 0),
                   "An old failure does not represent a current outage")
        let future = now.addingTimeInterval(61)
        try expect(evaluate([ProxyHistory(delay: 80, time: future)]) == .stale(lastTime: future, delay: 80),
                   "A far-future timestamp is not current")
        try expect(evaluate([ProxyHistory(delay: 137, time: old)]).barText == "137ms*",
                   "Old positive delays remain visible with a historical-record marker")
        try expect(evaluate([ProxyHistory(delay: 80, time: now), ProxyHistory(delay: 0, time: old)]) == healthy,
                   "The newest timestamp determines state, independent of array order")

        var tracker = AlertTracker()
        try expect(tracker.update(selection: selection, state: .checking, terminalIdentity: "A").isEmpty,
                   "A new selection awaiting active measurement does not alert on history")
        try expect(tracker.update(selection: selection, state: .stale(lastTime: old), terminalIdentity: "A").isEmpty,
                   "Launching with stale failures sends no notification")
        try expect(tracker.update(selection: selection, state: .noHistory, terminalIdentity: "A").isEmpty,
                   "No history sends no outage notification")
        let firstFailure = tracker.update(selection: selection, state: freshFailure, terminalIdentity: "A")
        try expect(firstFailure.count == 1 && firstFailure.first?.kind == .outage,
                   "A fresh failure sends one outage notification")
        try expect(!(firstFailure[0].title + firstFailure[0].body).contains(selection.name),
                   "Notification text hides monitor names")
        try expect(tracker.update(selection: selection, state: .failed(time: now.addingTimeInterval(10)),
                                  terminalIdentity: "A").isEmpty,
                   "A continuing failure with a new sample does not flood notifications")
        try expect(tracker.update(selection: selection, state: .stale(lastTime: now), terminalIdentity: "A").isEmpty,
                   "Stale data does not announce a recovery")
        let recovery = tracker.update(selection: selection, state: healthy, terminalIdentity: "A")
        try expect(recovery.count == 1 && recovery.first?.kind == .recovery,
                   "Fresh success after an outage sends a recovery")
        try expect(tracker.update(selection: selection, state: healthy, terminalIdentity: "A").isEmpty,
                   "A continuing healthy state stays quiet")

        tracker.reset()
        let timeoutAlert = tracker.update(selection: selection, state: .timedOut(time: now), terminalIdentity: "A")
        try expect(timeoutAlert.count == 1 && timeoutAlert[0].kind == .outage,
                   "An active node timeout emits an outage")
        try expect(tracker.update(selection: selection, state: freshFailure, terminalIdentity: "A").isEmpty,
                   "A timeout becoming a failure stays in the same incident")
        try expect(tracker.update(selection: selection, state: healthy, terminalIdentity: "A").first?.kind == .recovery,
                   "An active node timeout recovers on a positive measurement")

        _ = tracker.update(selection: selection, state: freshFailure, terminalIdentity: "A")
        try expect(tracker.update(selection: selection, state: healthy, terminalIdentity: "B").isEmpty,
                   "A new terminal does not falsely announce recovery of the old one")
        try expect(tracker.update(selection: selection, state: freshFailure, terminalIdentity: "B").count == 1,
                   "A failure on the new terminal has its own incident")
        tracker.reconcile(selectedIDs: [])
        try expect(tracker.update(selection: selection, state: freshFailure, terminalIdentity: "B").count == 1,
                   "Removing a selection clears its alert baseline")

        tracker.reset()
        try expect(tracker.update(selection: selection, state: .missing, terminalIdentity: nil).count == 1,
                   "A missing selection sends an alert")
        try expect(tracker.update(selection: selection, state: .missing, terminalIdentity: nil).isEmpty,
                   "A continuously missing selection stays quiet")
        try expect(tracker.update(selection: selection, state: healthy, terminalIdentity: "A").first?.kind == .recovery,
                   "A missing selection that resolves again can recover")
        tracker.resetMonitorStates()
        try expect(tracker.update(selection: selection, state: .invalidGroup, terminalIdentity: nil).count == 1,
                   "A cyclic group sends an alert")
        try expect(tracker.update(selection: selection, state: .invalidGroup, terminalIdentity: nil).isEmpty,
                   "A continuing cyclic group stays quiet")

        tracker.reset()
        try expect(tracker.updateController(error: nil).isEmpty, "Initial controller success is silent")
        let failure = tracker.updateController(error: .timedOut)
        try expect(failure.count == 1 && failure.first?.kind == .controllerFailure,
                   "Controller timeout sends one consolidated alert")
        try expect(tracker.updateController(error: .unavailable).isEmpty,
                   "A continuing controller outage stays quiet even when its error changes")
        try expect(tracker.updateController(error: nil).first?.kind == .controllerRecovery,
                   "Controller recovery sends one notification")
        try expect(tracker.updateController(error: nil).isEmpty, "Continued controller success stays quiet")
        _ = tracker.updateController(error: .unavailable)
        tracker.reset()
        try expect(tracker.updateController(error: nil).isEmpty,
                   "Changing the socket resets the previous controller incident")
    }
}

#if ALERT_POLICY_TEST_RUNNER
@main
enum AlertPolicyTestRunner {
    static func main() throws {
        try AlertPolicyTests.run()
        print("AlertPolicy transition tests passed")
    }
}
#endif
