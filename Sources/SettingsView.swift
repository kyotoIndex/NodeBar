import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    private var query: String { controller.settingsQuery }
    private var category: Int { controller.settingsCategory }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "network").font(.system(size: 28)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NodeBar").font(.title2.bold())
                    Text(L("在菜单栏查看节点状态", "Monitor proxy nodes in your menu bar")).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L("已选择 \(controller.preferences.monitors.count) 项", "\(controller.preferences.monitors.count) selected")).font(.headline)
                    Text(connectionSummary).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
            if let notice = controller.notice {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(notice).font(.callout)
                    Spacer()
                    Button { controller.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel(L("关闭提示", "Dismiss notice"))
                }.padding(12).background(Color.orange.opacity(0.12))
            }
            TabView(selection: $controller.settingsTab) {
                monitorPicker.tabItem { Label(L("监控节点", "Monitors"), systemImage: "list.bullet") }.tag(0)
                connectionSettings.tabItem { Label(L("连接与通知", "Connection & Notifications"), systemImage: "gearshape") }.tag(1)
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private var connectionSummary: String {
        if let error = controller.connectionMessage { return error }
        if let snapshot = controller.snapshot { return L("已连接 Mihomo · \(snapshot.selectableNodes.count) 个节点", "Connected to Mihomo · \(snapshot.selectableNodes.count) nodes") }
        return L("正在加载节点…", "Loading nodes…")
    }

    private var monitorPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索节点或策略组", "Search nodes or groups"), text: $controller.settingsQuery).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { controller.settingsQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel(L("清除搜索", "Clear search"))
                }
            }.padding(9).background(Color(nsColor: .textBackgroundColor)).cornerRadius(8)
            HStack {
                Picker(L("筛选", "Filter"), selection: $controller.settingsCategory) {
                    Text(L("全部", "All")).tag(0)
                    Text(L("策略组", "Groups")).tag(1)
                    Text(L("节点", "Nodes")).tag(2)
                    Text(L("已选择", "Selected")).tag(3)
                }.pickerStyle(.segmented).labelsHidden()
                Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(controller.isRefreshing).help(L("重新加载列表", "Reload list"))
            }
            List {
                if category == 3 {
                    if controller.preferences.monitors.isEmpty {
                        Text(L("勾选节点或策略组后，会在这里显示。", "Selected nodes and groups appear here.")).foregroundStyle(.secondary)
                    }
                    ForEach(controller.preferences.monitors.filter { matches($0.name) }) { selection in
                        monitorRow(selection)
                    }
                } else {
                    if category != 2, let snapshot = controller.snapshot {
                        Section(L("策略组 · 跟随当前选中的节点", "Groups · Follow the current node")) {
                            ForEach(snapshot.selectableGroups.filter { matches($0.name) }, id: \.name) { proxy in
                                monitorRow(MonitorSelection(kind: .group, name: proxy.name))
                            }
                        }
                    }
                    if category != 1, let snapshot = controller.snapshot {
                        Section(L("节点 · 固定监控", "Nodes · Monitor a specific node")) {
                            ForEach(snapshot.selectableNodes.filter { matches($0.name) }, id: \.name) { proxy in
                                monitorRow(MonitorSelection(kind: .node, name: proxy.name))
                            }
                        }
                    }
                    if controller.snapshot == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(controller.connectionMessage ?? L("正在加载列表…", "Loading list…")).font(.headline)
                            Text(L("请启动 Mihomo，或在“连接与通知”中设置 Socket 路径。", "Start Mihomo, or set its socket path in Connection & Notifications."))
                                .foregroundStyle(.secondary)
                            Button(L("连接设置", "Connection settings")) { controller.settingsTab = 1 }
                        }.padding(.vertical, 16)
                    }
                }
            }.listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Text(L("勾选后立即保存；已选择列表可将项目置顶。", "Changes save immediately. Pin items in the Selected list to show them first.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(L("菜单栏显示", "Menu bar items"), selection: Binding(get: { controller.preferences.barLimit }, set: controller.setBarLimit)) {
                    ForEach(1...8, id: \.self) { count in Text(L("\(count) 项", "\(count) items")).tag(count) }
                }.fixedSize()
            }
        }.padding(.top, 16)
    }

    private func monitorRow(_ selection: MonitorSelection) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(get: { controller.isSelected(selection) },
                                 set: { controller.setSelected(selection, selected: $0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.name).lineLimit(1).help(selection.name)
                    if selection.kind == .group {
                        Text(L("当前：\(controller.terminalName(for: selection))", "Current: \(controller.terminalName(for: selection))"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if let proxy = controller.snapshot?.proxies[selection.name] {
                        Text(proxy.type).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.toggleStyle(.checkbox)
            Spacer(minLength: 8)
            if controller.isSelected(selection) {
                Text(controller.connectionMessage == nil ? (controller.readings[selection.id]?.barText ?? "--") : L("未连接", "Disconnected"))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .help(controller.detail(for: selection))
                if category == 3 {
                    Button { controller.moveToFront(selection) } label: { Image(systemName: "pin") }
                        .buttonStyle(.borderless).help(L("移到菜单栏显示顺序的最前面", "Move to the front of the menu bar"))
                }
            }
        }.padding(.vertical, 5)
    }

    private var connectionSettings: some View {
        Form {
            Picker(L("界面语言", "Language"), selection: Binding(get: { L10n.preference }, set: controller.setLanguage)) {
                Text(L("跟随系统", "Follow System")).tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh-Hans")
            }
            Section(L("本机 Mihomo", "Local Mihomo")) {
                Toggle(L("自动检测本机 Mihomo", "Detect local Mihomo automatically"), isOn: Binding(get: { controller.preferences.automaticConnection }, set: controller.setAutomaticConnection))
                TextField(L("Socket 路径", "Socket path"), text: $controller.socketDraft).font(.system(.body, design: .monospaced))
                    .disabled(controller.preferences.automaticConnection)
                HStack {
                    Button(L("重新检测", "Detect again")) { controller.detectConnection() }
                        .disabled(!controller.preferences.automaticConnection || controller.isRefreshing)
                    Spacer()
                    Button(L("应用并连接", "Apply & Connect")) { controller.applySocketPath(controller.socketDraft) }
                        .disabled(controller.preferences.automaticConnection || controller.isRefreshing)
                }
                Text(connectionSummary).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("通知", "Notifications")) {
                Toggle(L("异常通知", "Notify on failure"), isOn: Binding(get: { controller.preferences.notificationsEnabled }, set: controller.setNotifications))
                Toggle(L("恢复正常时通知", "Notify on recovery"), isOn: Binding(get: { controller.preferences.recoveryNotifications }, set: controller.setRecoveryNotifications))
                    .disabled(!controller.preferences.notificationsEnabled)
                Toggle(L("在通知中显示节点名称", "Show node names in notifications"), isOn: Binding(get: { controller.preferences.notificationNames }, set: controller.setNotificationNames))
                    .disabled(!controller.preferences.notificationsEnabled)
                Text(L("系统权限：\(controller.notificationStatus)", "System permission: \(controller.notificationStatus)")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("请求通知权限", "Request permission")) { controller.requestNotificationPermission() }
                    Button(L("测试通知", "Test notification")) { controller.sendTestNotification() }
                    Spacer()
                    Button(L("系统通知设置", "Notification settings")) { controller.openSystemSettings() }
                }
            }
            Section(L("状态与刷新", "Status & Refresh")) {
                Toggle(L("主动测速", "Active probing"), isOn: Binding(get: { controller.preferences.activeProbing }, set: controller.setActiveProbing))
                Picker(L("检测超时", "Probe timeout"), selection: Binding(get: { controller.preferences.probeTimeoutSeconds }, set: controller.setProbeTimeout)) {
                    Text(L("5 秒", "5 seconds")).tag(5.0)
                    Text(L("10 秒", "10 seconds")).tag(10.0)
                    Text(L("15 秒", "15 seconds")).tag(15.0)
                }.disabled(!controller.preferences.activeProbing)
                Picker(L("刷新间隔", "Refresh interval"), selection: Binding(get: { controller.preferences.refreshInterval }, set: controller.setRefreshInterval)) {
                    Text(L("15 秒", "15 seconds")).tag(15.0)
                    Text(L("30 秒", "30 seconds")).tag(30.0)
                    Text(L("1 分钟", "1 minute")).tag(60.0)
                    Text(L("5 分钟", "5 minutes")).tag(300.0)
                }
                Text(controller.preferences.activeProbing
                     ? L("由 Mihomo 经所选节点检测 HTTPS 连通性。每轮只检测勾选的项目，同一异常只提醒一次。", "Mihomo checks HTTPS connectivity through the selected nodes. Each round checks selected items only; each incident sends one alert.")
                     : L("读取 Mihomo 历史记录。超过 5 分钟未更新的延迟带 * 标记，详情显示记录时间。", "Read Mihomo history. Latency older than 5 minutes is marked with *, with its timestamp shown in details."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(.top, 8)
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }
}
