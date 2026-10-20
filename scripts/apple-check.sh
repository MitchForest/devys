#!/usr/bin/env bash
# Native client gate: package tests, both app builds, strict lint.
set -euo pipefail
cd "$(dirname "$0")/.."
bun run surfaces:build >/dev/null
cd apple
xcodegen generate --quiet
swift test --package-path Packages/DevysKit
swift test --package-path Packages/DevysTerminal
xcodebuild -quiet -project Devys.xcodeproj -scheme Devys-macOS -destination 'platform=macOS' -derivedDataPath DerivedData build
xcodebuild -quiet -project Devys.xcodeproj -scheme Devys-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build
swiftlint --strict --quiet
echo "Apple clients: tests, macOS and iOS builds, and lint passed."
