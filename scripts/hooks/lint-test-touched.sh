#!/usr/bin/env bash
# PostToolUse hook . matcher: Edit | Write
# After any python edit: lint + format-check the file, run its sibling tests.
# Failures exit 2 -> the output goes straight back into teh agent's loop
set -uo pipefail

payload="$(cat)"
fp="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[[ "$fp" != *.py ]] && exit 0
cd "$CLAUDE_PROJECT_DIR"

problems=""
if ! out="$(uv run ruff check "$fp" 2>&1)"; then problems+="RUFF LINT:\n$out\n\n"; fi
if ! out="$(uv run ruff format --check "$fp" 2>&1)"; then problems+="RUFF FORMAT:\n$out\n\n"; fi

base="$(basename "$fp" .py)"
if [[ "$base" != test_* ]]; then
  sibling="$(find tests -name "test_${base}.py" -print -quit 2>/dev/null)"
else
  sibling="$fp"
fi
if [ -n "${sibling:-}" ] && [ -f "$sibling" ]; then
    if ! out="$(uv run pytest "$sibling" -q --no-cov 2>&1)"; then problems+="TESTS ($sibling):\n$out\n"; fi
fi

if [ -n "$problems" ]; then
    printf "Post-edit checks FAILED for %s — fix before proceeding:\n\n%b" "$fp" "$problems" >&2
    exit 2
fi
exit 0
