#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Finder opens .command files in Terminal. Keep its result visible without
# blocking callers that run this script from a non-interactive build process.
finish() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then
        echo ""
        echo "安装未完成。请查看上面的提示，处理后重新运行 install.command。" >&2
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        echo ""
        read -r -p "按回车关闭此安装脚本…" _ || true
    fi
    exit "$result"
}
trap finish EXIT

if [ "$(uname -s)" != Darwin ]; then
    echo "NodeBar 需要 macOS 13 或更新版本。" >&2
    exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 13 ]; then
    echo "当前 macOS 版本低于 13，请先升级系统。" >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "需要 Apple Command Line Tools 才能从源码编译 NodeBar。"
    echo "现在打开 Apple 的安装窗口；安装完成后，请重新双击 install.command。"
    xcode-select --install || true
    exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "未找到 Swift 编译器，请先完成 Apple Command Line Tools / Xcode 的安装与初始化。" >&2
    exit 1
fi

if [ ! -f "$PROJECT_DIR/build.sh" ] || [ ! -f "$PROJECT_DIR/main.swift" ]; then
    echo "源码不完整，请解压完整的 NodeBar 源码 ZIP，再运行其中的 install.command。" >&2
    exit 1
fi

echo "正在编译并安装 NodeBar 0.3.1…"
/bin/bash "$PROJECT_DIR/build.sh" --install
echo ""
echo "安装完成。NodeBar 会自动寻找本机 Mihomo 接口，并打开节点管理窗口。"
echo "勾选需要监控的节点或策略组即可；主动测速默认开启。"
