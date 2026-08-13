#!/usr/bin/env bash
# PreToolUse hook . matcher: Edit | Write
#  Protects law, CI, gold data, and gate-approved specs from agent modification
set -euo pipefail

payload="$(cat)"
fp="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$fp" ] && exit 0
rel="${fp#"$CLAUDE_PROJECT_DIR"/}"

deny() { echo "BLOCKED (protect-paths): $rel - $1" >&2; exit 2; }

case "$rel" in
  scripts/hooks/*) deny "hook scripts are policy; changed only by a human PR" ;;
  .github/*) deny "CO workflows are protected; changed only by a human PR" ;;
  evals/datasets/*) deny "gold datasets are written by seed scripts after human review, never edited directly" ;;
  .claude/settings.json) deny "hook wiring is policy; changed only by a human PR" ;;
esac

# requirements.md is frozen once its features passed the PM gate (G1)
if [[ "$rel" == specs/*/requirements.md ]]; then
  gate="$CLAUDE_PROJECT_DIR/$(dirname "$rel")/gate-log.md"
  if [ -f "$gate" ] && grep -q "pm_gate: approved" "$gate"; then
    deny "requirements are G1-approved; reopening requirees a human clearing the gate-log entry"
  fi
fi

exit 0
