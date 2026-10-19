# NodeBar

[English](README.md) · [简体中文](README.zh-CN.md)

macOS 菜单栏里的 Mihomo 节点监控工具。选择关心的节点或策略组，在菜单栏查看延迟，通过系统通知获知异常与恢复。

NodeBar **0.4.0** 使用 Swift、AppKit、SwiftUI 和 UserNotifications 实现，无第三方运行依赖，采用 MIT 许可证。

## 功能

- 自动发现本机 Mihomo Unix Socket，读取节点与策略组列表。
- 搜索并选择多个节点；监控策略组时，自动跟随该组当前选中的最终节点。
- 从节点名称读取国旗，操作图标使用 macOS 原生 SF Symbols，菜单栏没有前置地球图标。
- 菜单栏可显示 1–8 项，默认 3 项；更多项目通过 `+N` 提示。
- 主动测速支持 15 秒、30 秒、1 分钟和 5 分钟刷新，默认 30 秒；也可切换为仅读取历史。
- 控制器连接失败、节点测速失败或超时时发送系统通知；相同异常持续期间只提醒一次，恢复通知可关闭。
- 通知默认隐藏节点名称；支持开机启动，偏好设置保存在本机。
- 完整的英文与简体中文界面、菜单和通知，可在设置中选择**跟随系统**、**English** 或**简体中文**。

## 下载与安装

需要 **macOS 13 或更新版本**。两个发行包都同时支持 **Apple 芯片与 Intel Mac**。

[最新版本与中英文发布说明](https://github.com/kyotoIndex/NodeBar/releases/latest)

| 下载 | 初始界面语言 |
| --- | --- |
| [NodeBar macOS 英文版](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-English.zip) | English |
| [NodeBar macOS 中文版](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-Chinese.zip) | 简体中文 |

两个应用都内置中英文，可随时在设置中切换。选择一个版本安装即可。

解压后将 **NodeBar.app** 移到**应用程序**文件夹，再打开应用。当前发行包采用临时签名，尚未使用 Developer ID 签名或公证。如果 macOS 阻止打开下载的应用，前往**系统设置 → 隐私与安全性 → 仍要打开**，然后按照系统提示确认。

首次启动时允许发送通知，之后可在**系统设置 → 通知 → NodeBar** 中调整。

### 从源码构建安装

[下载完整源码 ZIP](https://github.com/kyotoIndex/NodeBar/archive/refs/heads/main.zip)，解压后双击 **`install.command`**。脚本会检查 Apple Command Line Tools；尚未安装时会打开 Apple 官方安装窗口，安装完成后再次运行 `install.command`。

脚本编译、临时签名、安装并启动 NodeBar。优先安装到 `/Applications/NodeBar.app`，该目录不可写时使用 `~/Applications/NodeBar.app`。构建与签名全部成功后才替换旧程序，临时文件自动清理。脚本不使用 `sudo`，不修改 Gatekeeper 或移除隔离属性。如果 macOS 阻止打开下载的脚本，请使用系统**隐私与安全性 → 仍要打开**的提示。

也可以在源码目录的终端中运行：

```bash
./install.command
# 或直接构建安装：
./build.sh
```

首次安装 Apple 开发工具需要下载；NodeBar 的构建过程没有包下载步骤。

## 使用

1. 启动 Clash Verge Rev 或其他提供本机 Mihomo Unix Socket 控制接口的客户端。
2. 启动 NodeBar，程序会自动发现本机控制器，首次启动打开节点管理窗口。之后也可从菜单打开「管理监控节点…」。
3. 搜索并勾选节点或策略组。选节点会固定监控该节点；选策略组会跟随其当前选中的最终节点。
4. 在管理窗口调整菜单栏显示数量；在设置中调整语言、自动连接或手动 Socket 路径、主动测速、检测期限与通知选项。

NodeBar 使用 Mihomo 的 `/proxies` 与节点测速接口，无须绑定特定 Clash Verge 版本。自动连接检查常见的本机 Socket 路径；使用自定义位置时，可关闭自动连接并填写 Unix Socket 绝对路径。

### 主动测速与历史模式

开启主动测速后，每次刷新会让 Mihomo 通过所选的最终代理节点访问 **`https://cp.cloudflare.com/generate_204`**。只有勾选监控的项目才会触发检查；多个项目指向同一节点时合并检测。`DIRECT`、`REJECT` 等非代理出口跳过测速。NodeBar 不设置直连回退，也不修改代理配置或策略组选择。

检测期限默认 **10 秒**，可在设置中选择 5、10 或 15 秒。本地接口等待时间比检测期限多 2 秒。链式代理建立连接，以及 Mihomo「统一延迟」需要的额外请求，都会占用整轮检测时间，因此完整检测可能比最终显示的延迟更久。「检测超时」表示检测地址未在所选期限内响应。

关闭主动测速后，刷新只读取 Mihomo 已有的健康检查历史。超过 5 分钟的正延迟仍显示为毫秒并带 `*` 标记，详情保留原始记录时间；空记录显示暂无历史。旧记录与空记录等待新数据，不触发节点故障通知。

控制器连接失败、监控项目消失、策略组解析异常，以及节点近期检测失败时会发送提醒。策略组切换节点后，重新跟踪新节点的状态。相同异常持续期间只提醒一次；通知默认隐藏名称，避免在横幅中显示节点信息。

## 隐私与本地数据

NodeBar 本身通过系统 **`AF_UNIX`** Socket 连接本机 Mihomo，读取节点、策略组选择和历史延迟；主动测速也通过同一个本地接口下达。程序没有遥测、上传服务、远程更新检查或第三方运行依赖。

**主动测速会产生外部流量。** Mihomo 经所选代理节点发出 HTTPS 请求，检测服务器会收到请求、代理出口 IP 与检测时间；代理服务商也能观察相应连接。域名解析和代理链路由 Mihomo 配置处理。请按自己的隐私需求选择可信节点，并配置 Mihomo 的 DNS 与路由。

历史模式下，NodeBar 不下达外部检测请求。Mihomo 自身的健康检查与其他应用的流量继续由各自配置管理。

偏好设置在当前用户本机保存 Socket 路径、监控列表、语言和界面选项；最新快照保存在进程内存中。开机启动仅管理本机用户 LaunchAgent，系统通知由 macOS 展示。

## 开发

```bash
./test.sh
./build.sh --build-only
```

`--build-only` 输出 `dist/NodeBar.app`，不会安装或启动；默认构建的应用跟随系统语言。构建并打包两种通用发行包：

```bash
./package.sh
```

单独构建某个版本：

```bash
NODEBAR_ARCH=universal NODEBAR_LANGUAGE=en ./build.sh --build-only
NODEBAR_ARCH=universal NODEBAR_LANGUAGE=zh-Hans ./build.sh --build-only
```

每条命令都会生成 `dist/NodeBar.app`，请先保存或打包第一个输出，再构建第二个。安装到自选位置：

```bash
NODEBAR_APP_PATH="$HOME/Applications/NodeBar.app" ./build.sh --install
```

默认应用标识符为 `io.github.nodebar.NodeBar`。需要独立偏好设置与通知身份时，可在构建时设置 `NODEBAR_BUNDLE_ID`。

测试使用本地构造数据与本机 Socket 服务，不访问外部服务。构建脚本直接用 `swiftc` 编译 `main.swift` 与 `Sources/*.swift`；GitHub Actions 执行脚本语法检查、测试与应用构建。

```text
main.swift               菜单栏、设置窗口与应用生命周期
Sources/                 本地接口、节点发现、测速、通知与本地化
Tests/                   本地行为测试
install.command          检查环境、编译、安装并启动
build.sh                 构建、签名与安装
test.sh                  运行本地测试
package.sh               构建中英文通用发行包
.github/workflows/       CI 构建
LICENSE                  MIT 许可证
```

## 许可证

[MIT](LICENSE) · Copyright © 2026 NodeBar contributors
