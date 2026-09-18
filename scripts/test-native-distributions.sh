#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if grep -R -n 'import Starscream\|CertificatePinning\|Starscream.xcframework' Source Tests --include='*.swift'; then
  echo 'Removed dependency remains in source or tests' >&2; exit 1
fi
if grep -n Starscream Package.swift Socket.IO-Client-Swift.podspec Cartfile Cartfile.resolved Socket.IO-Client-Swift.xcodeproj/project.pbxproj; then
  echo 'Removed dependency remains in distribution metadata' >&2; exit 1
fi
ruby -c Socket.IO-Client-Swift.podspec
for SPEC in 'macosx|platform=macOS' 'iphonesimulator|generic/platform=iOS Simulator' 'appletvsimulator|generic/platform=tvOS Simulator' 'watchsimulator|generic/platform=watchOS Simulator'; do
  SDK="${SPEC%%|*}"
  DESTINATION="${SPEC#*|}"
  echo "Building native framework for $SDK"
  xcodebuild -quiet -project Socket.IO-Client-Swift.xcodeproj -scheme SocketIO \
    -sdk "$SDK" -destination "$DESTINATION" -derivedDataPath "${RUNNER_TEMP:-/tmp}/socketio-native-distributions" \
    CODE_SIGNING_ALLOWED=NO build
done
