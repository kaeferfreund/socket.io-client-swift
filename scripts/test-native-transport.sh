#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Sources/SocketIO" "$TMP/Tests/TestSocketIO"
cp "$ROOT"/Source/SocketIO/Engine/Transport/*.swift "$TMP/Sources/SocketIO/"
cp "$ROOT"/Source/SocketIO/Security/*.swift "$TMP/Sources/SocketIO/"
cp "$ROOT"/Tests/TestSocketIO/URLSessionWebSocketTransportTest.swift "$TMP/Tests/TestSocketIO/"
cat > "$TMP/Package.swift" <<'MANIFEST'
// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "SocketIO",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [.library(name: "SocketIO", targets: ["SocketIO"])],
    targets: [.target(name: "SocketIO"), .testTarget(name: "TestSocketIO", dependencies: ["SocketIO"])])
MANIFEST
cd "$TMP"
swift test
