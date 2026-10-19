#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_LANGUAGE="${NODEBAR_LANGUAGE:-system}"
if [ "$INSTALL_LANGUAGE" = system ]; then
    SYSTEM_LANGUAGE="$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' || true)"
    case "$SYSTEM_LANGUAGE" in
        *zh*) INSTALL_LANGUAGE=zh-Hans ;;
        *) INSTALL_LANGUAGE=en ;;
    esac
fi
say() {
    if [ "$INSTALL_LANGUAGE" = zh-Hans ]; then echo "$1"; else echo "$2"; fi
}

# Finder opens .command files in Terminal. Keep its result visible without
# blocking callers that run this script from a non-interactive build process.
finish() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then
        echo ""
        say "安装未完成。请查看上面的提示，处理后重新运行 install.command。" "Installation did not finish. Review the messages above, then run install.command again." >&2
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        echo ""
        read -r -p "$(say '按回车关闭此安装脚本…' 'Press Return to close…')" _ || true
    fi
    exit "$result"
}
trap finish EXIT

if [ "$(uname -s)" != Darwin ]; then
    say "NodeBar 需要 macOS 13 或更新版本。" "NodeBar requires macOS 13 or later." >&2
    exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 13 ]; then
    say "当前 macOS 版本低于 13，请先升级系统。" "Please update to macOS 13 or later." >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    say "需要 Apple Command Line Tools 才能从源码编译 NodeBar。" "Apple Command Line Tools are required to build NodeBar from source."
    say "现在打开 Apple 的安装窗口；安装完成后，请重新双击 install.command。" "Opening the Apple installer. Run install.command again after installation finishes."
    xcode-select --install || true
    exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    say "未找到 Swift 编译器，请先完成 Apple Command Line Tools / Xcode 的安装与初始化。" "Swift compiler not found. Finish installing and setting up Apple Command Line Tools or Xcode." >&2
    exit 1
fi

if [ ! -f "$PROJECT_DIR/build.sh" ] || [ ! -f "$PROJECT_DIR/main.swift" ]; then
    say "源码不完整，请解压完整的 NodeBar 源码 ZIP，再运行其中的 install.command。" "Source files are missing. Extract the complete NodeBar source ZIP and run its install.command." >&2
    exit 1
fi

say "正在编译并安装 NodeBar 0.4.0…" "Building and installing NodeBar 0.4.0…"
/bin/bash "$PROJECT_DIR/build.sh" --install
echo ""
say "安装完成。NodeBar 会自动寻找本机 Mihomo 接口，并打开节点管理窗口。" "Installation complete. NodeBar will detect local Mihomo and open the monitor manager."
say "勾选需要监控的节点或策略组即可；主动测速默认开启。" "Select the nodes or groups to monitor. Active probing is enabled by default."
