#!/usr/bin/env bash
# Full active-surface audit: SwiftLint + Periphery + Tree-sitter gate + app build.
# Usage: ./scripts/audit.sh

set -euo pipefail

cd "$(dirname "$0")/.."

lint_output="$(mktemp)"
periphery_output="$(mktemp)"
migration_output="$(mktemp)"
build_output="$(mktemp)"
trap 'rm -f "$lint_output" "$periphery_output" "$migration_output" "$build_output"' EXIT

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

echo "3. Running Tree-sitter migration gate..."
echo "-------------------------------------------"
if ./scripts/check-tree-sitter-migration.sh >"$migration_output" 2>&1; then
    cat "$migration_output"
else
    cat "$migration_output"
fi
echo ""

echo "4. Building mac-client..."
echo "-------------------------------------------"
if DEVYS_SKIP_QUALITY_GATE=1 ./scripts/build-mac-client.sh >"$build_output" 2>&1; then
    cat "$build_output"
else
    cat "$build_output"
fi
echo ""

echo "5. Summary"
echo "-------------------------------------------"
SWIFTLINT_COUNT=$(grep -Ec '^/.+:[0-9]+:[0-9]+: (warning|error):' "$lint_output" || true)
PERIPHERY_COUNT=$(grep -Ec '^/.+:[0-9]+:[0-9]+: warning:' "$periphery_output" || true)
MIGRATION_FAILED=0
BUILD_FAILED=0
if ! grep -Fq "Tree-sitter migration gate passed." "$migration_output"; then
    MIGRATION_FAILED=1
fi
if ! grep -Fq "** BUILD SUCCEEDED **" "$build_output"; then
    BUILD_FAILED=1
fi
echo "   SwiftLint findings:   $SWIFTLINT_COUNT"
echo "   Periphery warnings:   $PERIPHERY_COUNT"
echo "   Tree-sitter gate:     $([[ "$MIGRATION_FAILED" -eq 0 ]] && echo passed || echo failed)"
echo "   mac-client build:     $([[ "$BUILD_FAILED" -eq 0 ]] && echo passed || echo failed)"
echo ""
echo "Run './scripts/lint.sh --fix' to auto-fix some SwiftLint issues."
echo "=========================================="

if [[ "$SWIFTLINT_COUNT" -ne 0 || "$PERIPHERY_COUNT" -ne 0 || "$MIGRATION_FAILED" -ne 0 || "$BUILD_FAILED" -ne 0 ]]; then
    exit 1
fi
