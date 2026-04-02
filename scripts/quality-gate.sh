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
./scripts/unused.sh

echo ""
echo "Quality gate passed."
