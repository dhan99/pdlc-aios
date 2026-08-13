#!/usr/bin/env bash
# PreToolsUse hook . matcher: Bash
# Blocks destructive commands. network egress, and secret access via shell
# exit 0 = allow . exit 2 = BLOCK (stderr is fed back to the agent)
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() { echo "BLOCKED (deny-danger): $1. This action s prohibited by repo policy; do not retry variants of it." >&2; exit 2; }

# destructive filesystem
#if echo "$cmd" | grep -Eq '(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*[rf][a-zA-Z]*[rf]'; then 
if echo "$cmd" | grep -Eq '(^|[;&|[:space:]])rm[[:space:]]+(-[^[:space:]]*[rRf]|--recursive|--force)'; then
  deny "rm with recursive/force flags"
fi
# git history rewrites on shared refs
if echo "$cmd" | grep -Eq 'git[[:space:]]+push[[:space:]].*(--force|--force-with-lease|[[:space:]]-f)([[:space:]]|$)'; then
  deny "force push"
fi
#network egress tools (agents get packages via uv; nothing else leaves)
if echo "$cmd" | grep -Eq '(^|[;&|[:space:]])(curl|wget|nc|ncat|scp|rsync[[:space:]].*:)([[:space:]]|$)'; then
  deny "network egress tool"
fi
# secret material via any shell command
if echo "$cmd" | grep -Eq '\.env(\.[a-zA-Z]+)?([[:space:]]|$|/)'; then
  deny "references .env files"
fi
if echo "$cmd" | grep -Eq '\.pem([[:space:]]|$)'; then
  deny "references private key files"
fi
if echo "$cmd" | grep -Eq '(~|\$HOME|/Users/[^/]+)/\.(ssh|secrets)'; then
  deny "references ~/.ssh or ~/.secrets"
fi

exit 0







#
