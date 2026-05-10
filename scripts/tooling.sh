#!/usr/bin/env bash

ensure_devys_tooling_path() {
    local dir
    for dir in /opt/homebrew/bin /usr/local/bin; do
        [[ -d "$dir" ]] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) PATH="$dir:$PATH" ;;
        esac
    done
    export PATH
}

resolve_tool_or_die() {
    local tool_name="$1"
    local tool_path

    ensure_devys_tooling_path
    tool_path="$(command -v "$tool_name" || true)"

    if [[ -n "$tool_path" ]]; then
        printf '%s\n' "$tool_path"
        return 0
    fi

    echo "Missing required tool: $tool_name" >&2
    echo "Install it with Homebrew or make it available in /opt/homebrew/bin, /usr/local/bin, or PATH." >&2
    return 1
}
