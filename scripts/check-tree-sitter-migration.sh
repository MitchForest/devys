#!/usr/bin/env bash
# Enforce the full Tree-sitter cutover.

set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/tooling.sh

SWIFT_BIN="$(resolve_tool_or_die swift)"

run_clean_swift_test() {
  env -i \
    PATH="${PATH}" \
    HOME="${HOME}" \
    USER="${USER:-}" \
    LOGNAME="${LOGNAME:-}" \
    SHELL="${SHELL:-/bin/bash}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LANG="${LANG:-en_US.UTF-8}" \
    "$SWIFT_BIN" test --package-path "$1"
}

forbidden_paths=(
  "Packages/Syntax/Sources/COniguruma"
  "Packages/Syntax/Sources/OnigurumaKit"
  "Packages/Syntax/Sources/Syntax/Services/Regex"
  "Packages/Syntax/Sources/Syntax/Services/TextMate"
  "Packages/Syntax/Sources/Syntax/Models/TextMate"
  "Packages/Syntax/Sources/Syntax/Resources/Grammars"
  "Packages/Syntax/Sources/Syntax/Resources/Themes"
  "Packages/Syntax/xcframeworks/libonig.xcframework"
  "scripts/generate-shiki-fixtures.mjs"
  "scripts/update-shiki-resources.mjs"
)

for path in "${forbidden_paths[@]}"; do
  if [[ -e "$path" ]]; then
    echo "Tree-sitter migration gate failed: forbidden path exists: $path" >&2
    exit 1
  fi
done

forbidden_symbols=(
  "TMTokenizer"
  "TMRegistry"
  "ThemeResolver"
  "ShikiTheme"
  "OnigurumaKit"
  "COniguruma"
  "libonig"
  "SyntaxEngine"
  "eagerlyPrepareVisibleLines"
)

for symbol in "${forbidden_symbols[@]}"; do
  if rg -n "$symbol" Packages/Syntax/Sources Packages/Editor/Sources Packages/Git/Sources >/dev/null 2>&1; then
    echo "Tree-sitter migration gate failed: forbidden symbol remains in production sources: $symbol" >&2
    exit 1
  fi
done

required_language_query_dirs=(
  "c"
  "cpp"
  "csharp"
  "css"
  "go"
  "html"
  "java"
  "javascript"
  "json"
  "jsx"
  "kotlin"
  "lua"
  "make"
  "markdown"
  "markdown_inline"
  "php"
  "python"
  "ruby"
  "rust"
  "shellscript"
  "sql"
  "swift"
  "toml"
  "typescript"
  "tsx"
  "yaml"
)

for language in "${required_language_query_dirs[@]}"; do
  if [[ ! -d "Packages/Syntax/Sources/Syntax/Resources/TreeSitterQueries/$language" ]]; then
    echo "Tree-sitter migration gate failed: missing query bundle for language: $language" >&2
    exit 1
  fi
done

required_injection_aliases=(
  "css"
  "html"
  "javascript"
  "markdown_inline"
  "sql"
  "swift"
  "toml"
  "yaml"
)

for alias in "${required_injection_aliases[@]}"; do
  if ! rg -n "\"$alias\"" Packages/Syntax/Sources/Syntax/Services/TreeSitter/TreeSitterLanguageRegistry.swift >/dev/null 2>&1; then
    echo "Tree-sitter migration gate failed: missing injection alias in registry: $alias" >&2
    exit 1
  fi
done

run_clean_swift_test Packages/Syntax
run_clean_swift_test Packages/Editor
run_clean_swift_test Packages/Git

echo "Tree-sitter migration gate passed."
