# NodeBar

macOS 菜单栏里的 Mihomo 节点监控工具。选择关心的节点或策略组，在菜单栏查看延迟，通过系统通知获知异常与恢复。

NodeBar 0.3.1 使用 Swift、AppKit、SwiftUI 和 UserNotifications 实现，无第三方运行依赖，采用 MIT 许可证。

## 功能

- 自动寻找本机 Mihomo Unix Socket，读取策略组和节点列表，无需修改源码或填写私人节点名称。
- 自主选择多个节点，支持搜索、随时添加和取消监控；首次启动打开节点管理窗口。
- 监控策略组时，递归跟随该组当前选中的最终节点；在 Clash 中切换节点后自动跟随。
- 从节点名称读取国旗，其余操作图标使用 macOS 原生 SF Symbols，菜单栏不加前置地球图标。
- 菜单栏默认显示前 3 项，可在设置中调整为 1–8 项；更多项目通过 `+N` 提示，完整状态在菜单中查看。
- 默认开启主动测速，提供 15 秒、30 秒、1 分钟和 5 分钟刷新间隔，默认 30 秒；也可切换为仅读取历史。
- 本地控制器连接失败、节点测速超时或不可用时发送系统通知；相同异常持续期间只提醒一次，恢复通知可关闭。
- 通知默认隐藏节点名称；支持开机启动，设置与选择保存在当前用户的本机偏好设置中。

## 安装

需要 **macOS 13 或更新版本**。[下载完整源码 ZIP](https://github.com/kyotoIndex/NodeBar/archive/refs/heads/main.zip) 并解压，双击文件夹中的 **`install.command`**。

安装脚本检查 macOS 和 Apple Command Line Tools，然后编译、签名、安装并启动 NodeBar。若尚未安装 Command Line Tools，脚本会打开 Apple 官方安装窗口；完成后再次双击 `install.command`。首次安装开发工具需要按 Apple 提示下载，NodeBar 的构建过程没有包下载步骤。

脚本在 `/Applications` 可写时安装到 `/Applications/NodeBar.app`，否则使用 `~/Applications/NodeBar.app`。构建与签名全部成功后才退出并替换旧程序，临时文件自动清理。脚本不需要 `sudo`，也不会修改 Gatekeeper 或文件隔离设置。若 macOS 提示无法打开下载的脚本，可按照系统「隐私与安全性」中的提示允许打开。

也可以在源码目录运行：

```bash
./install.command
```

或直接构建安装：

```bash
./build.sh
```

首次启动时允许 NodeBar 发送通知，也可随后在 macOS「系统设置 → 通知 → NodeBar」调整。若之前拒绝过授权，需要从系统设置重新开启。

仅构建、保留当前运行的程序：

```bash
./build.sh --build-only
```

输出为 `dist/NodeBar.app`，不会安装或启动。安装到自选位置：

```bash
NODEBAR_APP_PATH="$HOME/Applications/NodeBar.app" ./build.sh --install
```

应用采用本机临时签名，默认标识符为 `io.github.nodebar.NodeBar`。需要独立偏好设置与通知身份时，可在构建时设置 `NODEBAR_BUNDLE_ID`。GitHub Actions 也会生成可下载的应用 ZIP；正式分发的二进制应由发布者完成 Developer ID 签名与公证，当前版本推荐从源码本机构建。

## 使用

1. 启动 Clash Verge Rev 或其他提供 Mihomo Unix Socket 控制接口的客户端。
2. 启动 NodeBar，自动发现本机接口并打开节点管理窗口。尚未启动代理客户端时，可稍后在菜单中打开「管理监控节点…」。
3. 搜索并勾选节点或策略组。选节点会固定监控该节点，选策略组会跟随其当前选择。
4. 在节点管理窗口底部调整菜单栏显示数量；在「设置… → 连接与通知」中调整自动连接、手动 Socket 路径、主动测速与通知选项。

自动连接扫描常见客户端使用的本机 Socket 路径，并通过本地接口读取完整列表。使用自定义路径时，可关闭自动连接并填入 Unix Socket 绝对路径。程序依赖 Mihomo 的 `/proxies` 与节点测速接口，无须绑定特定 Clash Verge 版本。

### 主动测速与历史模式

默认模式下，每次刷新会让 Mihomo 通过选中的最终代理节点，访问固定的 HTTPS 地址 `https://cp.cloudflare.com/generate_204`。只有勾选监控的项目才会触发检查；多个项目指向同一最终节点时合并检测。`DIRECT`、`REJECT` 等非代理出口跳过测速，失败显示异常。NodeBar 不设置直连回退，不修改代理配置或策略组选择。

检测期限默认为 10 秒，可在「连接与通知」中选 5、10 或 15 秒。本地接口等待时间比检测期限多 2 秒。链式代理建立连接，以及 Mihomo 的“统一延迟”所需的额外请求，都会占用整轮检测时间，因此检测期限独立于最终显示的延迟值。

关闭主动测速后，刷新只读取 Mihomo 已有的健康检查历史，数值更新时间由该历史决定。超过 5 分钟的正延迟仍显示为毫秒并带 `*` 标记，详情显示历史值和原始记录时间；空记录显示暂无历史。旧记录与空记录等待新数据，不触发节点故障通知。

控制器连接失败、监控项目消失、策略组解析异常或节点近期检测失败时发送提醒。策略组切换到其他节点时，重新跟踪新节点的状态。相同异常持续期间不会每次刷新重复提醒；通知名称默认隐藏，避免在锁屏或通知横幅中显示节点信息。

## 通信与本地数据

NodeBar 本身通过系统 `AF_UNIX` Socket 连接本机 Mihomo，读取节点列表、策略组选择和历史延迟；主动测速也由这个本地接口下达。NodeBar 没有遥测、上传、远程更新检查或第三方运行依赖。

**主动测速会产生外部流量。** 实际 HTTPS 请求由 Mihomo 经所选代理节点发出，检测服务器会收到请求、代理出口 IP 和检测时间；代理服务商也能观察相应连接。域名解析和代理链路由 Mihomo 配置处理。请只监控可信的代理节点，并按自己的隐私需求配置 Mihomo 的 DNS 与路由。

切换为历史模式后，NodeBar 只读取本机记录，不下达外部检测请求。Mihomo 自己的健康检查与其他应用的流量继续由各自配置管理。

偏好设置保存 Socket 路径、监控列表和界面选项；最新快照保存在进程内存中。开机启动仅管理当前用户的本机 LaunchAgent。macOS 系统通知由系统在本机展示。

## 开发

```bash
./test.sh
./build.sh --build-only
```

测试使用本地构造的数据验证自动发现、节点解析与通知规则，不连接外网。构建脚本直接用 `swiftc` 编译 `main.swift` 与 `Sources/*.swift`，无包下载步骤。GitHub Actions 执行脚本语法检查、测试与构建，生成应用压缩包。

```text
main.swift               菜单栏、设置窗口与应用生命周期
Sources/                 本地控制接口、节点发现、测速与状态通知逻辑
Tests/                   本地规则测试
install.command          双击检查环境、编译、安装并启动
build.sh                 构建、签名与安装
test.sh                  运行本地规则测试
.github/workflows/       CI 构建
LICENSE                  MIT 许可证
```

## 许可证

[MIT](LICENSE) · Copyright © 2026 NodeBar contributors
