import AppKit
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    @Published private(set) var preferences = AppPreferences.load()
    @Published private(set) var snapshot: ProxySnapshot?
    @Published private(set) var readings: [String: MonitoringState] = [:]
    @Published private(set) var connectionMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var notificationStatus = "正在读取权限…"
    @Published var notice: String?
    @Published var settingsTab = 0
    @Published var settingsQuery = ""
    @Published var settingsCategory = 0
    @Published var socketDraft = ""

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var window: NSWindow?
    private var menuTracking = false
    private var generation = 0
    private var refreshPending = false
    private var discoveryPending = false
    private var activeResults: [String: ActiveProbeResult] = [:]
    private var measuredSelectionIDs: Set<String> = []
    private var probeCancellation: ProbeCancellation?
    private var controllerError: LocalMihomoError?
    private var alerts = AlertTracker()
    private var notificationService: NotificationService!
    private let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "MM-dd HH:mm:ss"
        return value
    }()

    var bundleID: String { Bundle.main.bundleIdentifier ?? "io.github.nodebar.NodeBar" }
    var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }
    var autoStartEnabled: Bool { FileManager.default.fileExists(atPath: launchAgentURL.path) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("\(bundleID).show-settings"), object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(manageMonitors),
            name: Notification.Name("\(bundleID).show-settings"), object: nil)
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.image = nil
        statusItem.button?.imagePosition = .noImage
        preferences.save()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        notificationService = NotificationService()
        notificationService.onStatusChange = { [weak self] status in
            guard let self else { return }
            let newlyAllowed = status == "已允许" && self.notificationStatus != status
            self.notificationStatus = status
            if newlyAllowed && self.preferences.notificationsEnabled {
                self.alerts.reset()
                if let error = self.controllerError, !self.preferences.monitors.isEmpty {
                    self.deliver(self.alerts.updateController(error: error))
                } else { self.evaluateReadings() }
            }
        }
        notificationService.onDeliveryError = { [weak self] message in self?.notice = message }
        notificationService.onOpen = { [weak self] in self?.showSettings() }
        notificationService.refreshAuthorization(requestIfNeeded: preferences.notificationsEnabled)
        startTimer()
        updateDisplay()
        refresh()
        if preferences.monitors.isEmpty || CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        notificationService?.refreshAuthorization(requestIfNeeded: false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func refresh(forceDiscovery: Bool = false) {
        guard !isRefreshing else {
            refreshPending = true
            discoveryPending = discoveryPending || forceDiscovery
            return
        }
        isRefreshing = true
        let token = generation
        let path = preferences.socketPath
        let automatic = preferences.automaticConnection
        let active = preferences.activeProbing
        let probeBudget = Int(preferences.probeTimeoutSeconds * 1_000)
        let selections = preferences.monitors
        let discover = forceDiscovery || discoveryPending
        let cancellation = ProbeCancellation()
        probeCancellation = cancellation
        refreshPending = false
        discoveryPending = false
        updateDisplay()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result: Result<(SocketDiscoveryResult, [String: ActiveProbeResult]), LocalMihomoError>
            do {
                let endpoint: SocketDiscoveryResult
                if discover && automatic {
                    endpoint = try SocketDiscovery.resolve(preferred: path)
                } else {
                    do {
                        endpoint = SocketDiscoveryResult(path: path, snapshot: try LocalMihomoClient(path: path).fetchSnapshot())
                    } catch {
                        let originalError = error
                        guard automatic else { throw originalError }
                        do { endpoint = try SocketDiscovery.resolve(preferred: path) }
                        catch { throw originalError }
                    }
                }
                let results = active ? LocalMihomoClient(path: endpoint.path).probeSelections(selections, snapshot: endpoint.snapshot,
                    timeoutMilliseconds: probeBudget, cancellation: cancellation) : [:]
                result = .success((endpoint, results))
            }
            catch { result = .failure(error as? LocalMihomoError ?? .unavailable) }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.isRefreshing = false
                self.probeCancellation = nil
                self.lastUpdated = Date()
                switch result {
                case .success(let (endpoint, results)):
                    self.snapshot = endpoint.snapshot
                    self.activeResults = results
                    self.measuredSelectionIDs = Set(selections.map(\.id))
                    if self.preferences.socketPath != endpoint.path {
                        self.preferences.socketPath = endpoint.path
                        self.socketDraft = endpoint.path
                        self.preferences.save()
                    }
                    let error = results.values.compactMap { measurement -> LocalMihomoError? in
                        if case .localFailure(let error) = measurement.state { return error }
                        return nil
                    }.first
                    self.controllerError = error
                    self.connectionMessage = error.map { self.description(for: $0) }
                    if let error, !self.preferences.monitors.isEmpty {
                        self.deliver(self.alerts.updateController(error: error))
                    } else { self.evaluateReadings() }
                case .failure(let error):
                    self.controllerError = error
                    self.connectionMessage = self.description(for: error)
                    if !self.preferences.monitors.isEmpty {
                        self.deliver(self.alerts.updateController(error: error))
                    }
                }
                self.updateDisplay()
                if self.refreshPending { self.refresh() }
            }
        }
    }

    private func evaluateReadings() {
        guard let snapshot else { return }
        let selected = preferences.monitors
        alerts.reconcile(selectedIDs: Set(selected.map(\.id)))
        if !selected.isEmpty { deliver(alerts.updateController(error: nil)) }
        var states: [String: MonitoringState] = [:]
        let now = Date()
        for selection in selected {
            let resolution = snapshot.resolve(selection)
            var state = MonitoringState.evaluate(resolution, now: now)
            let identity: String?
            if case .resolved(let monitor) = resolution { identity = monitor.terminalName }
            else { identity = nil }
            if preferences.activeProbing, let identity {
                if state.kind != .direct && state.kind != .rejected { state = .checking }
                if measuredSelectionIDs.contains(selection.id), let measurement = activeResults[identity] {
                    switch measurement.state {
                    case .success(let delay): state = .healthy(delay: delay, time: measurement.checkedAt)
                    case .failed: state = .failed(time: measurement.checkedAt)
                    case .timedOut: state = .timedOut(time: measurement.checkedAt)
                    case .unsupported:
                        if state.kind != .direct && state.kind != .rejected { state = .unsupported }
                    case .localFailure: break
                    }
                }
            }
            states[selection.id] = state
            deliver(alerts.update(selection: selection, state: state, terminalIdentity: identity))
        }
        readings = states
    }

    private func deliver(_ events: [AlertEvent]) {
        notificationService?.deliver(events, preferences: preferences)
    }

    func isSelected(_ selection: MonitorSelection) -> Bool { preferences.monitors.contains(selection) }

    func setSelected(_ selection: MonitorSelection, selected: Bool) {
        guard selected != isSelected(selection) else { return }
        cancelCurrentRefresh()
        measuredSelectionIDs.remove(selection.id)
        if selected && !isSelected(selection) { preferences.monitors.append(selection) }
        if !selected { preferences.monitors.removeAll { $0.id == selection.id } }
        preferences.save()
        if preferences.monitors.isEmpty { alerts.reset() }
        if controllerError == nil { evaluateReadings() }
        else {
            alerts.reconcile(selectedIDs: Set(preferences.monitors.map(\.id)))
            if !preferences.monitors.isEmpty { deliver(alerts.updateController(error: controllerError)) }
        }
        updateDisplay()
        refresh()
    }

    func setRefreshInterval(_ interval: Double) {
        guard AppPreferences.intervals.contains(interval) else { return }
        preferences.refreshInterval = interval
        preferences.save()
        startTimer()
        updateDisplay()
    }

    func setBarLimit(_ limit: Int) {
        preferences.barLimit = min(8, max(1, limit))
        preferences.save()
        updateDisplay()
    }

    func moveToFront(_ selection: MonitorSelection) {
        guard isSelected(selection) else { return }
        preferences.monitors.removeAll { $0.id == selection.id }
        preferences.monitors.insert(selection, at: 0)
        preferences.save()
        updateDisplay()
    }

    func setNotifications(_ enabled: Bool) {
        preferences.notificationsEnabled = enabled
        preferences.save()
        if enabled {
            alerts.reset()
            notificationService.refreshAuthorization(requestIfNeeded: true)
            if let error = controllerError, !preferences.monitors.isEmpty {
                deliver(alerts.updateController(error: error))
            } else { evaluateReadings() }
        }
        updateDisplay()
    }

    func setRecoveryNotifications(_ enabled: Bool) {
        preferences.recoveryNotifications = enabled
        preferences.save()
    }

    func setNotificationNames(_ enabled: Bool) {
        preferences.notificationNames = enabled
        preferences.save()
    }

    func setActiveProbing(_ enabled: Bool) {
        preferences.activeProbing = enabled
        preferences.save()
        cancelCurrentRefresh()
        activeResults = [:]
        measuredSelectionIDs = []
        alerts.reset()
        refresh()
    }

    func setProbeTimeout(_ seconds: Double) {
        guard [5.0, 10.0, 15.0].contains(seconds) else { return }
        preferences.probeTimeoutSeconds = seconds
        preferences.save()
        cancelCurrentRefresh()
        refresh()
    }

    func setAutomaticConnection(_ enabled: Bool) {
        preferences.automaticConnection = enabled
        preferences.save()
        if enabled { detectConnection() }
        else {
            cancelCurrentRefresh()
            activeResults = [:]
            measuredSelectionIDs = []
            refresh()
        }
    }

    func detectConnection() {
        cancelCurrentRefresh()
        activeResults = [:]
        measuredSelectionIDs = []
        controllerError = nil
        connectionMessage = nil
        alerts.reset()
        refresh(forceDiscovery: true)
    }

    func applySocketPath(_ value: String) {
        let path = NSString(string: value.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard path.hasPrefix("/"), !path.utf8.contains(0), path.utf8.count < 104 else {
            notice = "请输入有效的本机 Socket 绝对路径（UTF-8 长度小于 104 字节）。"
            return
        }
        preferences.socketPath = path
        preferences.automaticConnection = false
        preferences.save()
        cancelCurrentRefresh()
        snapshot = nil
        readings = [:]
        activeResults = [:]
        measuredSelectionIDs = []
        controllerError = nil
        connectionMessage = nil
        lastUpdated = nil
        alerts.reset()
        refresh()
    }

    private func cancelCurrentRefresh() {
        probeCancellation?.cancel()
        probeCancellation = nil
        generation += 1
        isRefreshing = false
        refreshPending = false
        discoveryPending = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        probeCancellation?.cancel()
    }

    func requestNotificationPermission() { notificationService.refreshAuthorization(requestIfNeeded: true) }
    func sendTestNotification() { notice = nil; notificationService.sendTest() }
    func openSystemSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func showSettings(tab: Int = 0) {
        settingsTab = tab
        if window == nil {
            socketDraft = preferences.socketPath
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
            newWindow.title = "NodeBar"
            newWindow.contentView = NSHostingView(rootView: SettingsView(controller: self))
            newWindow.minSize = NSSize(width: 660, height: 480)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: preferences.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func terminalName(for selection: MonitorSelection) -> String {
        if let snapshot, case .resolved(let monitor) = snapshot.resolve(selection) { return monitor.terminalName }
        return selection.name
    }

    func detail(for selection: MonitorSelection) -> String {
        if let connectionMessage { return connectionMessage }
        return readings[selection.id]?.detailText(formatter: dateFormatter) ?? "正在读取…"
    }

    private func updateDisplay() {
        guard statusItem != nil else { return }
        let monitors = preferences.monitors
        let title: String
        if let error = controllerError { title = error == .timedOut ? "超时" : "未连接" }
        else if monitors.isEmpty { title = "NodeBar" }
        else {
            var segments = monitors.prefix(preferences.barLimit).map { selection in
                "\(NodeLabel.shortName(terminalName(for: selection))) \(readings[selection.id]?.barText ?? "--")"
            }
            if monitors.count > preferences.barLimit { segments.append("+\(monitors.count - preferences.barLimit)") }
            title = segments.joined(separator: "   ")
        }
        statusItem.button?.title = title
        statusItem.button?.image = nil
        statusItem.button?.toolTip = monitors.isEmpty ? "NodeBar · 点击选择监控节点" : monitors.map {
            "\($0.name)\n\(detail(for: $0))"
        }.joined(separator: "\n\n")
        if !menuTracking { rebuildMenu() }
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(); menuTracking = true }
    func menuDidClose(_ menu: NSMenu) { menuTracking = false }

    private func icon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, symbol: String? = nil,
                         action: Selector? = nil, value: Any? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = value
        if let symbol { item.image = icon(symbol) }
        menu.addItem(item)
        return item
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        if let connectionMessage { addItem(menu, connectionMessage, symbol: "exclamationmark.triangle") }
        if preferences.monitors.isEmpty { addItem(menu, "尚未选择监控节点") }
        for selection in preferences.monitors {
            let state = readings[selection.id]
            let title = "\(selection.name)  ·  \(controllerError == nil ? (state?.barText ?? "--") : "未连接")"
            let item = addItem(menu, title, symbol: state?.symbolName ?? "network")
            let detailMenu = NSMenu()
            if selection.kind == .group { addItem(detailMenu, "当前节点：\(terminalName(for: selection))") }
            addItem(detailMenu, detail(for: selection))
            detailMenu.addItem(.separator())
            addItem(detailMenu, "停止监控", symbol: "minus.circle", action: #selector(removeMonitor(_:)), value: selection.id)
            item.submenu = detailMenu
        }
        if let lastUpdated { addItem(menu, "最后读取：\(dateFormatter.string(from: lastUpdated))") }
        menu.addItem(.separator())
        addItem(menu, "管理监控节点…", symbol: "slider.horizontal.3", action: #selector(manageMonitors), key: "m")
        let measuring = preferences.activeProbing && !preferences.monitors.isEmpty
        addItem(menu, isRefreshing ? (measuring ? "正在测速…" : "正在刷新…") : (measuring ? "立即测速" : "刷新"),
                symbol: "arrow.clockwise", action: #selector(manualRefresh), key: "r")
        let probing = addItem(menu, "主动测速", symbol: "waveform.path.ecg", action: #selector(toggleActiveProbing))
        probing.state = preferences.activeProbing ? .on : .off
        let intervalItem = addItem(menu, "刷新间隔", symbol: "timer")
        let intervalMenu = NSMenu()
        for interval in AppPreferences.intervals {
            let item = addItem(intervalMenu, interval < 60 ? "\(Int(interval)) 秒" : "\(Int(interval / 60)) 分钟",
                               action: #selector(changeInterval(_:)), value: interval)
            item.state = interval == preferences.refreshInterval ? .on : .off
        }
        intervalItem.submenu = intervalMenu
        let notifications = addItem(menu, "异常通知", symbol: "bell", action: #selector(toggleNotifications))
        notifications.state = preferences.notificationsEnabled ? .on : .off
        let startup = addItem(menu, "开机自动启动", symbol: "power", action: #selector(toggleAutoStart))
        startup.state = autoStartEnabled ? .on : .off
        addItem(menu, "设置…", symbol: "gearshape", action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem(menu, "退出 NodeBar", symbol: "xmark.circle", action: #selector(quitApp), key: "q")
    }

    private func description(for error: LocalMihomoError) -> String {
        switch error {
        case .unavailable: return "无法连接本机 Mihomo"
        case .timedOut: return "本机 Mihomo 响应超时"
        case .invalidResponse: return "Mihomo 数据格式异常"
        }
    }

    @objc private func manageMonitors() { showSettings() }
    @objc private func openSettings() { showSettings(tab: 1) }
    @objc private func manualRefresh() { refresh() }
    @objc private func toggleActiveProbing() { setActiveProbing(!preferences.activeProbing) }
    @objc private func toggleNotifications() { setNotifications(!preferences.notificationsEnabled) }
    @objc private func changeInterval(_ sender: NSMenuItem) {
        if let interval = sender.representedObject as? Double { setRefreshInterval(interval) }
    }
    @objc private func removeMonitor(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String,
           let selection = preferences.monitors.first(where: { $0.id == id }) { setSelected(selection, selected: false) }
    }
    @objc private func toggleAutoStart() {
        do {
            if autoStartEnabled { try FileManager.default.removeItem(at: launchAgentURL) }
            else {
                guard let executable = Bundle.main.executablePath else { throw CocoaError(.fileNoSuchFile) }
                try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let propertyList: [String: Any] = ["Label": bundleID, "ProgramArguments": [executable], "RunAtLoad": true]
                let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
                try data.write(to: launchAgentURL, options: .atomic)
            }
            objectWillChange.send()
            updateDisplay()
        } catch {
            notice = "开机启动设置失败：\(error.localizedDescription)"
            showSettings(tab: 1)
        }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.run()
