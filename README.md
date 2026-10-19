# NodeBar

[English](README.md) · [简体中文](README.zh-CN.md)

A native macOS menu bar app for monitoring Mihomo proxy nodes and groups. Choose what to monitor, view latency in the menu bar, and receive macOS notifications when a check fails or recovers.

NodeBar **0.4.0** uses Swift, AppKit, SwiftUI, and UserNotifications, with no third-party runtime dependencies. Licensed under MIT.

## Features

- Automatically discovers local Mihomo Unix Sockets and loads available nodes and groups.
- Search and select multiple nodes; monitor a group to follow its currently selected final node.
- Displays flags from node names, uses native SF Symbols for controls, and keeps the menu bar free of a leading globe icon.
- Shows up to 1–8 items in the menu bar (3 by default), with `+N` for additional items.
- Active checks every 15 seconds, 30 seconds, 1 minute, or 5 minutes; defaults to 30 seconds. A history-only mode is also available.
- Sends notifications for controller connection errors, failed checks, and timeouts. Repeated alerts are suppressed until the state changes; recovery alerts are optional.
- Hides node names in notifications by default. Supports launch at login and stores preferences locally.
- Complete English and Simplified Chinese interfaces, menus, and notifications. Choose **Follow System**, **English**, or **简体中文** in settings.

## Download and install

Requires **macOS 13 or later**. Both release downloads support **Apple silicon and Intel Macs**.

[Latest release and bilingual release notes](https://github.com/kyotoIndex/NodeBar/releases/latest)

| Download | Initial interface language |
| --- | --- |
| [NodeBar for macOS — English](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-English.zip) | English |
| [NodeBar for macOS — 简体中文](https://github.com/kyotoIndex/NodeBar/releases/download/v0.4.0/NodeBar-0.4.0-macOS-Chinese.zip) | Simplified Chinese |

Both apps include both languages; you can switch languages in settings. Install one variant at a time.

Unzip the download, move **NodeBar.app** to **Applications**, and open it. These builds are ad hoc signed and are not Developer ID signed or notarized. If macOS blocks the downloaded app, open **System Settings → Privacy & Security → Open Anyway**, then confirm the system prompt.

Allow notifications when prompted. You can change this later in **System Settings → Notifications → NodeBar**.

### Build and install from source

[Download the source ZIP](https://github.com/kyotoIndex/NodeBar/archive/refs/heads/main.zip), extract it, and double-click **`install.command`**. The script checks for Apple Command Line Tools; if missing, it opens Apple's installer. Run `install.command` again after those tools finish installing.

The script compiles, ad hoc signs, installs, and launches NodeBar. It uses `/Applications/NodeBar.app` when writable, otherwise `~/Applications/NodeBar.app`. It replaces the previous app only after the new build and signature succeed, and cleans temporary files automatically. No `sudo`, Gatekeeper changes, or quarantine removal is used. If macOS blocks the downloaded script, use the system's **Privacy & Security → Open Anyway** prompt.

From Terminal in the source directory:

```bash
./install.command
# Or build and install directly:
./build.sh
```

Installing Apple's development tools requires a download. Building NodeBar has no package download step.

## Usage

1. Start Clash Verge Rev or another client that exposes a local Mihomo Unix Socket control API.
2. Open NodeBar. It discovers the local controller and opens the monitor manager on first launch. You can also open **Manage Monitors…** from the menu later.
3. Search for and select nodes or groups. A node selection stays fixed; a group selection follows the group's current final node.
4. Adjust the menu bar item count in the manager. In settings, configure language, connection discovery or a manual Socket path, active checks, timeouts, and notifications.

NodeBar uses Mihomo's `/proxies` and per-node delay APIs; it does not require a specific Clash Verge version. Automatic discovery checks common local Socket locations. For a custom location, disable automatic connection and enter the absolute Unix Socket path.

### Active checks and history-only mode

With active checks enabled, each refresh asks Mihomo to visit **`https://cp.cloudflare.com/generate_204`** through each selected final proxy node. Only monitored selections are checked; selections that resolve to the same node share one check. Non-proxy adapters such as `DIRECT` and `REJECT` are skipped. NodeBar does not configure a direct fallback or change proxy settings or group selections.

The default check deadline is **10 seconds**, with 5, 10, and 15 seconds available in settings. The local API wait allows another 2 seconds. Establishing a proxy chain and Mihomo's additional request for unified delay both take time, so the full check can take longer than the latency eventually displayed. A **Test timed out** status means the test endpoint did not respond within the chosen deadline.

Turn active checks off to read only Mihomo's existing health-check history. Refreshing then reloads those records. A positive latency older than 5 minutes remains visible with an `*`; details show its original timestamp. Empty records show no history. Old or missing history waits for new data without triggering a node-failure alert.

Controller connection failures, missing monitors, invalid group resolution, and recent failed node checks can trigger notifications. Following a group switch starts tracking the newly selected node. Persistent incidents produce one alert, and notification names are hidden by default.

## Privacy and local data

NodeBar itself communicates with local Mihomo through **`AF_UNIX`**. It reads nodes, group selections, and latency history, and submits active-check requests through that same local interface. There is no telemetry, upload service, remote update check, or third-party runtime dependency.

**Active checks generate external traffic.** Mihomo sends HTTPS requests through the selected proxy node. The test server receives the request, proxy exit IP, and timing information; the proxy provider can observe the corresponding connection. Mihomo's configuration controls DNS resolution and the proxy chain. Select trusted nodes and configure Mihomo's DNS and routing for your privacy needs.

In history-only mode, NodeBar submits no external-check requests. Mihomo's own health checks and other applications continue to follow their own configurations.

Preferences store the Socket path, selected monitors, language, and interface options locally for the current user. The latest controller snapshot stays in process memory. Launch at login manages a local user LaunchAgent. Notifications are displayed by macOS.

## Development

```bash
./test.sh
./build.sh --build-only
```

`--build-only` writes `dist/NodeBar.app` without installing or launching it. By default, the app follows the system language. Build and package both universal release variants with:

```bash
./package.sh
```

To build a single variant:

```bash
NODEBAR_ARCH=universal NODEBAR_LANGUAGE=en ./build.sh --build-only
NODEBAR_ARCH=universal NODEBAR_LANGUAGE=zh-Hans ./build.sh --build-only
```

Each command writes `dist/NodeBar.app`; copy or package the first output before building the second. To install elsewhere:

```bash
NODEBAR_APP_PATH="$HOME/Applications/NodeBar.app" ./build.sh --install
```

The default bundle identifier is `io.github.nodebar.NodeBar`. Set `NODEBAR_BUNDLE_ID` when building if a separate preferences and notification identity is needed.

Tests use local fixtures and local Socket servers; they do not connect to external services. The build script compiles `main.swift` and `Sources/*.swift` directly with `swiftc`. GitHub Actions runs script syntax checks, tests, and app builds.

```text
main.swift               Menu bar, settings window, and app lifecycle
Sources/                 Local API, discovery, checks, alerts, and localization
Tests/                   Local behavior tests
install.command          Environment check, build, install, and launch
build.sh                 Build, sign, and install
test.sh                  Run local tests
package.sh               Build English and Chinese universal release ZIPs
.github/workflows/       CI builds
LICENSE                  MIT license
```

## License

[MIT](LICENSE) · Copyright © 2026 NodeBar contributors
