#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nodebar-package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT

NODEBAR_ARCH=universal NODEBAR_LANGUAGE=system "$PROJECT_DIR/build.sh" --build-only
app="$PROJECT_DIR/dist/NodeBar.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"

for language in en zh-Hans; do
    if [ "$language" = en ]; then label=English; else label=Chinese; fi
    stage="$PACKAGE_DIR/$label"
    mkdir -p "$stage"
    ditto "$app" "$stage/NodeBar.app"
    /usr/libexec/PlistBuddy -c "Set :NodeBarDefaultLanguage $language" "$stage/NodeBar.app/Contents/Info.plist"
    codesign --force --sign - --identifier "$bundle_id" \
        --requirements "=designated => identifier \"$bundle_id\"" "$stage/NodeBar.app"
    cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/README.md" "$PROJECT_DIR/README.zh-CN.md" "$stage/"
    codesign --verify --strict "$stage/NodeBar.app"
    for architecture in arm64 x86_64; do
        lipo "$stage/NodeBar.app/Contents/MacOS/NodeBar" -verify_arch "$architecture"
    done
    archive="$PROJECT_DIR/dist/NodeBar-$version-macOS-$label.zip"
    ditto -c -k "$stage" "$archive"
    echo "Packaged: $archive"
done
