## English

NodeBar is a native macOS menu bar monitor for Mihomo proxy nodes and groups.

### New in 0.4.0

- Complete English and Simplified Chinese interfaces, menus, status details, and macOS notifications.
- Switch languages instantly from the menu or Settings: Follow System, English, or 简体中文.
- English and Chinese download variants, each including both languages and supporting Apple silicon and Intel Macs.
- English primary README with a link to the complete Chinese documentation.
- Automatic local controller discovery, searchable node/group selection, and group tracking.
- Active HTTPS checks with a 10-second default deadline, plus history-only mode. This deadline accommodates proxy-chain setup and Mihomo unified-delay checks.
- Notifications for failures, timeouts, and recovery, with node names hidden by default.

### Download and install

Requires **macOS 13 or later**. Download **NodeBar-0.4.0-macOS-English.zip** or **NodeBar-0.4.0-macOS-Chinese.zip**, unzip it, move `NodeBar.app` to Applications, and open it. Choose one variant; saved language preferences take priority over the package's initial language.

The apps are **ad hoc signed**, with no Developer ID signature or notarization. If macOS blocks the app, use **System Settings → Privacy & Security → Open Anyway** and follow the system prompt. You can also build from source by running `install.command` in the complete source archive; this requires Apple Command Line Tools.

**Privacy:** NodeBar itself only connects to the local Mihomo Unix Socket. Active checks ask Mihomo to visit `https://cp.cloudflare.com/generate_204` through the selected proxy nodes. Turn active probing off for history-only operation. No telemetry or update checks.

Validation: local behavior tests passed; both universal app bundles were built and their ad hoc signatures and architectures verified.

[English documentation](https://github.com/kyotoIndex/NodeBar/blob/v0.4.0/README.md) · [中文文档](https://github.com/kyotoIndex/NodeBar/blob/v0.4.0/README.zh-CN.md)

---

## 简体中文

NodeBar 是在 macOS 菜单栏监控 Mihomo 代理节点与策略组的小工具。

### 0.4.0 更新

- 完整的英文与简体中文界面、菜单、状态详情及 macOS 通知。
- 可在菜单或设置中即时切换「跟随系统」「English」「简体中文」。
- 提供默认英文与默认中文两个下载包；两个包都内置双语，同时支持 Apple 芯片和 Intel Mac。
- 主 README 改为英文，顶部可切换至完整中文文档。
- 自动发现本机控制接口，可搜索并自主选择节点或策略组，策略组跟随当前节点。
- 主动 HTTPS 检测默认期限为 10 秒，兼顾链式代理与 Mihomo 统一延迟所需时间，也可选择历史模式。
- 异常、超时与恢复时发送通知，默认隐藏节点名称。

### 下载与安装

需要 **macOS 13 或更新版本**。下载 **NodeBar-0.4.0-macOS-Chinese.zip** 或 **NodeBar-0.4.0-macOS-English.zip**，解压后将 `NodeBar.app` 移到「应用程序」并打开。选择一个版本安装即可；已保存的语言偏好优先于下载包的初始语言。

应用采用**临时签名**，尚未使用 Developer ID 签名或公证。如果 macOS 阻止打开，请前往**系统设置 → 隐私与安全性 → 仍要打开**，按照系统提示确认。也可以在完整源码目录运行 `install.command`，通过 Apple Command Line Tools 在本机编译安装。

**隐私：** NodeBar 自身仅连接本机 Mihomo Unix Socket。主动测速由 Mihomo 经选定节点访问 `https://cp.cloudflare.com/generate_204`；关闭主动测速后只读取历史。没有遥测或更新检查。

验证：本地行为测试通过；两个通用应用包均完成构建、临时签名验证与架构检查。

[English documentation](https://github.com/kyotoIndex/NodeBar/blob/v0.4.0/README.md) · [中文文档](https://github.com/kyotoIndex/NodeBar/blob/v0.4.0/README.zh-CN.md)
