#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

git restore --staged --worktree fixtures/agent_workspace
git clean -fd -- fixtures/agent_workspace
