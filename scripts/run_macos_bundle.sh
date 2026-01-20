#!/bin/sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
cargo build -p app
open "$ROOT_DIR/macos/Devys.app"
