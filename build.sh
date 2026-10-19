#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:---install}"
case "$MODE" in
    --build-only|--install) ;;
    --help|-h)
        echo "Usage: ./build.sh [--install|--build-only]"
        echo "Environment: NODEBAR_APP_PATH, NODEBAR_BUNDLE_ID, NODEBAR_ARCH, NODEBAR_LANGUAGE"
        exit 0 ;;
    *) echo "Unknown option: $MODE" >&2; exit 1 ;;
esac
if [ "$#" -gt 1 ]; then
    echo "Only one option is accepted." >&2
    exit 1
fi

BUNDLE_ID="${NODEBAR_BUNDLE_ID:-io.github.nodebar.NodeBar}"
if ! [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    echo "NODEBAR_BUNDLE_ID contains invalid characters." >&2
    exit 1
fi
case "${NODEBAR_ARCH:-$(uname -m)}" in
    arm64) BUILD_ARCH=arm64 ;;
    x86_64) BUILD_ARCH=x86_64 ;;
    universal) BUILD_ARCH=universal ;;
    *) echo "Unsupported Mac architecture." >&2; exit 1 ;;
esac
DEFAULT_LANGUAGE="${NODEBAR_LANGUAGE:-system}"
case "$DEFAULT_LANGUAGE" in
    system|en|zh-Hans) ;;
    *) echo "NODEBAR_LANGUAGE must be system, en, or zh-Hans." >&2; exit 1 ;;
esac

if [ "$MODE" = --build-only ]; then
    APP_PATH="$PROJECT_DIR/dist/NodeBar.app"
elif [ -n "${NODEBAR_APP_PATH:-}" ]; then
    APP_PATH="$NODEBAR_APP_PATH"
elif [ -w /Applications ]; then
    APP_PATH=/Applications/NodeBar.app
else
    APP_PATH="$HOME/Applications/NodeBar.app"
fi
case "$APP_PATH" in
    /*/NodeBar.app) ;;
    *) echo "App destination must be an absolute path ending in /NodeBar.app." >&2; exit 1 ;;
esac

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nodebar-build.XXXXXX")"
INSTALL_STAGE=""
BACKUP_PATH=""
cleanup() {
    rm -rf "$BUILD_DIR"
    if [ -n "$INSTALL_STAGE" ]; then
        if [ -n "$BACKUP_PATH" ] && [ -e "$BACKUP_PATH" ] && [ ! -e "$APP_PATH" ]; then
            if ! mv "$BACKUP_PATH" "$APP_PATH"; then
                echo "Previous app preserved at: $BACKUP_PATH" >&2
                return
            fi
        fi
        rm -rf "$INSTALL_STAGE"
    fi
}
trap cleanup EXIT

APP_STAGE="$BUILD_DIR/NodeBar.app"
mkdir -p "$APP_STAGE/Contents/MacOS"
SWIFT_SOURCES=("$PROJECT_DIR/main.swift")
for source in "$PROJECT_DIR"/Sources/*.swift; do
    [ ! -f "$source" ] || SWIFT_SOURCES+=("$source")
done
echo "Building NodeBar ($BUILD_ARCH, macOS 13+)..."
if [ "$BUILD_ARCH" = universal ]; then
    for architecture in arm64 x86_64; do
        swiftc -O -target "$architecture-apple-macosx13.0" "${SWIFT_SOURCES[@]}" \
            -o "$BUILD_DIR/NodeBar-$architecture"
    done
    lipo -create "$BUILD_DIR/NodeBar-arm64" "$BUILD_DIR/NodeBar-x86_64" \
        -output "$APP_STAGE/Contents/MacOS/NodeBar"
else
    swiftc -O -target "$BUILD_ARCH-apple-macosx13.0" "${SWIFT_SOURCES[@]}" \
        -o "$APP_STAGE/Contents/MacOS/NodeBar"
fi

cat > "$APP_STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NodeBar</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>NodeBar</string>
    <key>CFBundleDisplayName</key><string>NodeBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.4.0</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
    <key>NodeBarDefaultLanguage</key><string>$DEFAULT_LANGUAGE</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
plutil -lint "$APP_STAGE/Contents/Info.plist"
codesign --force --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP_STAGE"

# Fully stage the signed bundle on the destination volume before stopping the app.
APP_PARENT="$(dirname "$APP_PATH")"
mkdir -p "$APP_PARENT"
INSTALL_STAGE="$(mktemp -d "$APP_PARENT/.nodebar-install.XXXXXX")"
ditto "$APP_STAGE" "$INSTALL_STAGE/NodeBar.app"

if [ "$MODE" = --install ]; then
    # Match both the process name and executable path; never match shell arguments.
    while IFS= read -r process_id; do
        [ -n "$process_id" ] || continue
        executable="$(ps -ww -p "$process_id" -o comm= 2>/dev/null || true)"
        [ "$executable" = "$APP_PATH/Contents/MacOS/NodeBar" ] || continue
        kill -TERM "$process_id" 2>/dev/null || true
        for ((attempt=0; attempt<20; attempt++)); do
            if ! kill -0 "$process_id" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$process_id" 2>/dev/null; then
            kill -KILL "$process_id" 2>/dev/null || true
        fi
    done < <(pgrep -x NodeBar || true)
fi

# Keep the previous bundle recoverable until the replacement is in place.
if [ -e "$APP_PATH" ]; then
    BACKUP_PATH="$INSTALL_STAGE/previous.app"
    mv "$APP_PATH" "$BACKUP_PATH"
fi
mv "$INSTALL_STAGE/NodeBar.app" "$APP_PATH"
if [ "$MODE" = --install ]; then
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$APP_PATH"; fi
    open "$APP_PATH"
    echo "Installed and launched: $APP_PATH"
else
    echo "Built: $APP_PATH"
fi
