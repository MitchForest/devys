#!/usr/bin/env bash
# Canonical CLI build for the active macOS app target.

set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild build \
    -project Devys.xcodeproj \
    -scheme mac-client \
    -destination "generic/platform=macOS" \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO
