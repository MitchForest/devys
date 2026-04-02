#!/usr/bin/env bash
# Full code audit: SwiftLint + Periphery
# Usage: ./scripts/audit.sh

set -euo pipefail

cd "$(dirname "$0")/.."

lint_output="$(mktemp)"
periphery_output="$(mktemp)"
trap 'rm -f "$lint_output" "$periphery_output"' EXIT

echo "=========================================="
echo "DEVYS CODE AUDIT"
echo "=========================================="
echo ""

echo "1. Running SwiftLint..."
echo "-------------------------------------------"
if ./scripts/lint.sh >"$lint_output" 2>&1; then
    cat "$lint_output"
else
    cat "$lint_output"
fi
echo ""

echo "2. Running Periphery (unused code detection)..."
echo "-------------------------------------------"
if ./scripts/unused.sh >"$periphery_output" 2>&1; then
    cat "$periphery_output"
else
    cat "$periphery_output"
fi
echo ""

echo "3. Summary"
echo "-------------------------------------------"
SWIFTLINT_COUNT=$(grep -Ec '^/.+:[0-9]+:[0-9]+: (warning|error):' "$lint_output" || true)
PERIPHERY_COUNT=$(grep -Ec '^/.+:[0-9]+:[0-9]+: warning:' "$periphery_output" || true)
echo "   SwiftLint findings:   $SWIFTLINT_COUNT"
echo "   Periphery warnings:   $PERIPHERY_COUNT"
echo ""
echo "Run './scripts/lint.sh --fix' to auto-fix some SwiftLint issues."
echo "=========================================="
