# NodeBar

[English](README.md) · [简体中文](README.zh-CN.md)

在 macOS 菜单栏监控 Mihomo 代理节点。

NodeBar 显示所选节点的延迟，在检测失败或恢复时发送系统通知。配合现有代理客户端使用，无需打开客户端面板即可查看节点状态。

## 功能

- **自由选择监控对象。** 搜索并选择节点或策略组，策略组会跟随当前选中的节点。
- **在菜单栏查看状态。** 将常用节点显示在菜单栏中，展开菜单可查看完整监控列表。
- **接收异常与恢复通知。** 同一异常持续期间只提醒一次，通知默认隐藏节点名称。
- **自动连接本机客户端。** 自动发现正在运行的 Mihomo 控制接口，也可手动指定 Socket 路径。
- **按需调整。** 支持中英文切换、自定义刷新间隔和开机启动。

## 安装

需要 **macOS 13 或更新版本**，以及提供 **Unix Socket 控制接口的 Mihomo 客户端**，例如 Clash Verge Rev。两个下载包均支持 Apple 芯片与 Intel Mac。

**[下载最新版本](https://github.com/kyotoIndex/NodeBar/releases/latest)**

- [简体中文版](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-Chinese.zip)
- [English](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-English.zip)

两个下载包仅初始语言不同，均内置中英文，可在应用中随时切换。

解压后将 **NodeBar.app** 移到**应用程序**文件夹并打开。首次启动时允许发送通知，即可接收监控提醒。

当前发行包采用临时签名，尚未通过 Apple 公证。如果 macOS 阻止打开，请前往**系统设置 → 隐私与安全性 → 仍要打开**，按照系统提示确认。

### 从源码安装

[下载源码](https://github.com/kyotoIndex/NodeBar/archive/refs/heads/main.zip)，解压后双击 `install.command`，脚本会编译并启动应用。如果尚未安装 Apple Command Line Tools，脚本会打开 Apple 安装窗口；安装完成后，再次运行 `install.command`。

## 开始使用

1. 启动 Mihomo 代理客户端，再打开 NodeBar。
2. 在「管理监控节点…」中勾选需要监控的节点或策略组。
3. 调整菜单栏显示数量，在「设置…」中配置检测与通知，或通过「语言」菜单切换界面语言。

选择节点会固定监控该节点；选择策略组则跟随该组的当前选择。在代理客户端切换节点后，NodeBar 会随之更新。NodeBar 读取这些选择，不修改它们。

## 监控与隐私

**主动测速**默认开启，每 30 秒让 Mihomo 经所选代理节点检测 `https://cp.cloudflare.com/generate_204`。刷新间隔和默认 10 秒的检测期限均可在设置中调整。「检测超时」表示本次检查未在设定期限内完成。

**历史模式**读取 Mihomo 已有的延迟记录，关闭主动测速即可使用。超过五分钟的数值带有 `*` 标记，详情中可查看记录时间。旧记录或空记录不会触发故障通知。

NodeBar 通过本机 Unix Socket 与 Mihomo 通信，没有遥测、统计分析或自动更新检查。偏好设置和监控列表保存在本机；通知默认隐藏节点名称，可自行开启显示。

主动测速会通过 Mihomo 产生外部流量，检测服务器可见代理出口 IP 与请求时间；DNS 与路由由 Mihomo 配置决定。历史模式下，NodeBar 不下达主动检测请求。

## 开发

NodeBar 使用 Swift、AppKit 和 SwiftUI 构建，无第三方依赖。

```bash
./test.sh                  # 运行本地测试
./build.sh --build-only     # 构建 dist/NodeBar.app
./build.sh --install        # 编译、安装并启动
./package.sh                # 打包支持 Apple 芯片与 Intel 的中英文版本
```

构建需要 Apple Command Line Tools 或 Xcode。测试使用本地数据与 Unix Socket 服务，GitHub Actions 自动执行测试并构建两个发行包。

## 许可证

[MIT](LICENSE)
