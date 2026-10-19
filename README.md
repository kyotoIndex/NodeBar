# NodeBar

[English](README.md) · [简体中文](README.zh-CN.md)

Monitor your Mihomo proxy nodes from the macOS menu bar.

NodeBar shows latency for the nodes you choose and sends macOS notifications when checks fail or recover. It works alongside your proxy client, so you can keep track of connections without opening its dashboard.

## Features

- **Choose what to monitor.** Search and select individual nodes or proxy groups. Groups follow their currently selected node.
- **See status at a glance.** Keep selected nodes in the menu bar and view the full list from its menu.
- **Get notified.** Receive failure and recovery alerts, with repeated alerts suppressed during an ongoing incident. Node names are hidden in notifications by default.
- **Connect automatically.** Discover a running local Mihomo controller, with a manual socket path option for custom setups.
- **Make it yours.** Switch between English and Simplified Chinese, adjust refresh intervals, and enable launch at login.

## Installation

Requires **macOS 13 or later** and a running **Mihomo-compatible client with a Unix Socket control API**, such as Clash Verge Rev. Both downloads support Apple silicon and Intel Macs.

**[Download the latest release](https://github.com/kyotoIndex/NodeBar/releases/latest)**

- [English](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-English.zip)
- [简体中文](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-Chinese.zip)

The downloads differ only in their initial language. Both include English and Simplified Chinese, which you can switch in the app.

Unzip the download, move **NodeBar.app** to **Applications**, and open it. Allow notifications when prompted to receive monitoring alerts.

The current release is ad hoc signed and has not been notarized by Apple. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** and follow the system prompt.

### Install from source

[Download the source](https://github.com/kyotoIndex/NodeBar/archive/refs/heads/main.zip), extract it, and double-click `install.command`. The installer builds and launches the app. If Apple Command Line Tools are missing, it opens Apple's installer; run `install.command` again after the tools finish installing.

## Getting started

1. Start your Mihomo-based proxy client, then open NodeBar.
2. Select the nodes or groups to monitor in **Manage Monitors…**.
3. Choose how many items appear in the menu bar. Open **Settings…** to configure checks and notifications, or **Language** to change the interface language.

Selecting a node monitors that specific node. Selecting a group follows its current choice as you switch nodes in your proxy client. NodeBar reads these selections without changing them.

## Monitoring and privacy

**Active probing** is enabled by default. Every 30 seconds, NodeBar asks Mihomo to check `https://cp.cloudflare.com/generate_204` through the selected proxy nodes. Refresh intervals and the 10-second check timeout are adjustable in settings. A timeout means this check did not finish within the configured deadline.

**History mode** reads existing Mihomo latency records. Turn off active probing to use it. Values older than five minutes carry an `*`; their timestamps appear in the details. Old or empty history does not trigger failure notifications.

NodeBar communicates with Mihomo through a local Unix Socket. It has no telemetry, analytics, or automatic update checks. Preferences and monitor selections are stored on your Mac; node names are hidden in notifications unless you enable them.

Active checks generate external traffic through Mihomo: the test server sees the proxy exit IP and request timing. Mihomo's configuration controls DNS and routing. In history mode, NodeBar sends no active-check requests.

## Development

NodeBar is built with Swift, AppKit, and SwiftUI, with no third-party dependencies.

```bash
./test.sh                  # Run local tests
./build.sh --build-only     # Build dist/NodeBar.app
./build.sh --install        # Build, install, and launch
./package.sh                # Package both languages for Apple silicon and Intel
```

Building requires Apple Command Line Tools or Xcode. Tests use local fixtures and Unix Socket servers. GitHub Actions runs the tests and builds both release packages.

## License

[MIT](LICENSE)
