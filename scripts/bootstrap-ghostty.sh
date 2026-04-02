#!/usr/bin/env bash
# Bootstrap the pinned Ghostty source checkout used by the libghostty rewrite.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib/ghostty-config.sh
source "$repo_root/scripts/lib/ghostty-config.sh"

source_dir="$repo_root/$DEVYS_GHOSTTY_SOURCE_DIR"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/bootstrap-ghostty.sh

Checks out the pinned Ghostty commit into .deps/ghostty-src.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

mkdir -p "$(dirname "$source_dir")"

new_checkout=0
if [[ ! -d "$source_dir/.git" ]]; then
    git clone --filter=blob:none --no-checkout "$DEVYS_GHOSTTY_REPOSITORY" "$source_dir"
    new_checkout=1
fi

git -C "$source_dir" remote set-url origin "$DEVYS_GHOSTTY_REPOSITORY"

has_worktree_files=0
if find "$source_dir" -mindepth 1 -maxdepth 1 ! -name .git | read -r _; then
    has_worktree_files=1
fi

if [[ "$new_checkout" -eq 0 && "$has_worktree_files" -eq 1 && -n "$(git -C "$source_dir" status --porcelain)" ]]; then
    echo "Ghostty source checkout is dirty: $source_dir" >&2
    echo "Commit or discard local changes before re-bootstrapping." >&2
    exit 1
fi

current_commit="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)"
if [[ "$current_commit" != "$DEVYS_GHOSTTY_COMMIT" ]]; then
    git -C "$source_dir" fetch --depth 1 origin "$DEVYS_GHOSTTY_COMMIT"
    git -C "$source_dir" checkout --detach "$DEVYS_GHOSTTY_COMMIT"
elif [[ "$has_worktree_files" -eq 0 ]]; then
    git -C "$source_dir" checkout --detach "$DEVYS_GHOSTTY_COMMIT"
fi

resolved_commit="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$resolved_commit" != "$DEVYS_GHOSTTY_COMMIT" ]]; then
    echo "Ghostty checkout failed to resolve pinned commit." >&2
    exit 1
fi

echo "Ghostty source ready:"
echo "  repo:   $DEVYS_GHOSTTY_REPOSITORY"
echo "  commit: $resolved_commit"
echo "  path:   $source_dir"
