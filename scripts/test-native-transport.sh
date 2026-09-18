#!/usr/bin/env bash
# Offline, dependency-free check of ONLY the native transport milestone.
# This is not a replacement for the full repository's macOS/E2E test suite.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/Sources/SocketIO" "$scratch/Tests/TestSocketIO"
cp "$root"/Source/SocketIO/Engine/Transport/*.swift "$scratch/Sources/SocketIO/"
cp "$root/Tests/TestSocketIO/URLSessionWebSocketTransportTest.swift" "$scratch/Tests/TestSocketIO/"
cat > "$scratch/Package.swift" <<'MANIFEST'
// swift-tools-version:5.4
import PackageDescription
let package = Package(
    name: "NativeTransportCheck",
    targets: [
        .target(name: "SocketIO"),
        .testTarget(name: "TestSocketIO", dependencies: ["SocketIO"])
    ]
)
MANIFEST
swift test --package-path "$scratch" "$@"
