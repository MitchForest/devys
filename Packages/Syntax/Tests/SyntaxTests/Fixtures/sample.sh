#!/usr/bin/env bash
set -euo pipefail

NAME="Devys"

log() {
  local msg="$1"
  echo "[info] $msg"
}

if [[ -z "${NAME}" ]]; then
  log "Name is empty"
else
  log "Hello, ${NAME}!"
fi

for file in *.md; do
  if [[ -f "$file" ]]; then
    echo "found: $file"
  fi
done
