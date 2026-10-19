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
                    Text("在菜单栏查看节点状态").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("已选择 \(controller.preferences.monitors.count) 项").font(.headline)
                    Text(connectionSummary).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
            if let notice = controller.notice {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(notice).font(.callout)
                    Spacer()
                    Button { controller.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("关闭提示")
                }.padding(12).background(Color.orange.opacity(0.12))
            }
            TabView(selection: $controller.settingsTab) {
                monitorPicker.tabItem { Label("监控节点", systemImage: "list.bullet") }.tag(0)
                connectionSettings.tabItem { Label("连接与通知", systemImage: "gearshape") }.tag(1)
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private var connectionSummary: String {
        if let error = controller.connectionMessage { return error }
        if let snapshot = controller.snapshot { return "已连接 Mihomo · \(snapshot.selectableNodes.count) 个节点" }
        return "正在加载节点…"
    }

    private var monitorPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索节点或策略组", text: $controller.settingsQuery).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { controller.settingsQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }.padding(9).background(Color(nsColor: .textBackgroundColor)).cornerRadius(8)
            HStack {
                Picker("筛选", selection: $controller.settingsCategory) {
                    Text("全部").tag(0)
                    Text("策略组").tag(1)
                    Text("节点").tag(2)
                    Text("已选择").tag(3)
                }.pickerStyle(.segmented).labelsHidden()
                Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(controller.isRefreshing).help("重新加载列表")
            }
            List {
                if category == 3 {
                    if controller.preferences.monitors.isEmpty {
                        Text("勾选节点或策略组后，会在这里显示。").foregroundStyle(.secondary)
                    }
                    ForEach(controller.preferences.monitors.filter { matches($0.name) }) { selection in
                        monitorRow(selection)
                    }
                } else {
                    if category != 2, let snapshot = controller.snapshot {
                        Section("策略组 · 跟随当前选中的节点") {
                            ForEach(snapshot.selectableGroups.filter { matches($0.name) }, id: \.name) { proxy in
                                monitorRow(MonitorSelection(kind: .group, name: proxy.name))
                            }
                        }
                    }
                    if category != 1, let snapshot = controller.snapshot {
                        Section("节点 · 固定监控") {
                            ForEach(snapshot.selectableNodes.filter { matches($0.name) }, id: \.name) { proxy in
                                monitorRow(MonitorSelection(kind: .node, name: proxy.name))
                            }
                        }
                    }
                    if controller.snapshot == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(controller.connectionMessage ?? "正在加载列表…").font(.headline)
                            Text("请启动 Mihomo，或在“连接与通知”中设置 Socket 路径。")
                                .foregroundStyle(.secondary)
                            Button("连接设置") { controller.settingsTab = 1 }
                        }.padding(.vertical, 16)
                    }
                }
            }.listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Text("勾选后立即保存；已选择列表可将项目置顶。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("菜单栏显示", selection: Binding(get: { controller.preferences.barLimit }, set: controller.setBarLimit)) {
                    ForEach(1...8, id: \.self) { count in Text("\(count) 项").tag(count) }
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
                        Text("当前：\(controller.terminalName(for: selection))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if let proxy = controller.snapshot?.proxies[selection.name] {
                        Text(proxy.type).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.toggleStyle(.checkbox)
            Spacer(minLength: 8)
            if controller.isSelected(selection) {
                Text(controller.connectionMessage == nil ? (controller.readings[selection.id]?.barText ?? "--") : "未连接")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .help(controller.detail(for: selection))
                if category == 3 {
                    Button { controller.moveToFront(selection) } label: { Image(systemName: "pin") }
                        .buttonStyle(.borderless).help("移到菜单栏显示顺序的最前面")
                }
            }
        }.padding(.vertical, 5)
    }

    private var connectionSettings: some View {
        Form {
            Section("本机 Mihomo") {
                Toggle("自动检测本机 Mihomo", isOn: Binding(get: { controller.preferences.automaticConnection }, set: controller.setAutomaticConnection))
                TextField("Socket 路径", text: $controller.socketDraft).font(.system(.body, design: .monospaced))
                    .disabled(controller.preferences.automaticConnection)
                HStack {
                    Button("重新检测") { controller.detectConnection() }
                        .disabled(!controller.preferences.automaticConnection || controller.isRefreshing)
                    Spacer()
                    Button("应用并连接") { controller.applySocketPath(controller.socketDraft) }
                        .disabled(controller.preferences.automaticConnection || controller.isRefreshing)
                }
                Text(connectionSummary).font(.caption).foregroundStyle(.secondary)
            }
            Section("通知") {
                Toggle("异常通知", isOn: Binding(get: { controller.preferences.notificationsEnabled }, set: controller.setNotifications))
                Toggle("恢复正常时通知", isOn: Binding(get: { controller.preferences.recoveryNotifications }, set: controller.setRecoveryNotifications))
                    .disabled(!controller.preferences.notificationsEnabled)
                Toggle("在通知中显示节点名称", isOn: Binding(get: { controller.preferences.notificationNames }, set: controller.setNotificationNames))
                    .disabled(!controller.preferences.notificationsEnabled)
                Text("系统权限：\(controller.notificationStatus)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("请求通知权限") { controller.requestNotificationPermission() }
                    Button("测试通知") { controller.sendTestNotification() }
                    Spacer()
                    Button("系统通知设置") { controller.openSystemSettings() }
                }
            }
            Section("状态与刷新") {
                Toggle("主动测速", isOn: Binding(get: { controller.preferences.activeProbing }, set: controller.setActiveProbing))
                Picker("检测超时", selection: Binding(get: { controller.preferences.probeTimeoutSeconds }, set: controller.setProbeTimeout)) {
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                    Text("15 秒").tag(15.0)
                }.disabled(!controller.preferences.activeProbing)
                Picker("刷新间隔", selection: Binding(get: { controller.preferences.refreshInterval }, set: controller.setRefreshInterval)) {
                    Text("15 秒").tag(15.0)
                    Text("30 秒").tag(30.0)
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                }
                Text(controller.preferences.activeProbing
                     ? "由 Mihomo 经所选节点检测 HTTPS 连通性。每轮只检测勾选的项目，同一异常只提醒一次。"
                     : "读取 Mihomo 历史记录。超过 5 分钟未更新的延迟带 * 标记，详情显示记录时间。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(.top, 8)
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }
}
