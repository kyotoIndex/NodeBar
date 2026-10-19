#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nodebar-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc \
    "$PROJECT_DIR/Sources/NodeBarCore.swift" \
    "$PROJECT_DIR/Sources/AlertPolicy.swift" \
    "$PROJECT_DIR/Sources/ActiveMonitoring.swift" \
    "$PROJECT_DIR/Sources/SocketDiscovery.swift" \
    "$PROJECT_DIR/Sources/AppPreferences.swift" \
    "$PROJECT_DIR"/Tests/*.swift \
    -o "$TEST_DIR/NodeBarTests"
"$TEST_DIR/NodeBarTests"
