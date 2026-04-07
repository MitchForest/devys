#!/usr/bin/env bash
# Hard quality gate: strict lint + zero periphery warnings.
# Usage: ./scripts/quality-gate.sh

set -euo pipefail

if [[ "${DEVYS_SKIP_QUALITY_GATE:-0}" == "1" ]]; then
    echo "Skipping quality gate (DEVYS_SKIP_QUALITY_GATE=1)."
    exit 0
fi

cd "$(dirname "$0")/.."

./scripts/lint.sh
unused_args=()
if [[ "${DEVYS_SKIP_APP_PERIPHERY:-0}" == "1" ]]; then
    unused_args+=(--skip-apps)
fi
if [[ "${DEVYS_SKIP_PACKAGE_PERIPHERY:-0}" == "1" ]]; then
    unused_args+=(--skip-packages)
fi
if [[ ${#unused_args[@]} -gt 0 ]]; then
    ./scripts/unused.sh "${unused_args[@]}"
else
    ./scripts/unused.sh
fi
./scripts/check-tree-sitter-migration.sh

echo ""
echo "Quality gate passed."
