# AIOS-Based PDLC — 15-Day Build Plan (Claude Code)
**STATUS: COMMITTED — 15 working days (committed 2026-08-08). 10–11 days is stretch-only via parallel sessions; verification days are never traded for calendar days.**
**Solo-developer, ASAP schedule. Builds the r2 architecture in dependency order: substrate → bounded agents → inner loop → spine → RDR graph → enforcement. Every day ends with something tested and committed.**
*Source of truth: `v2-technical-brief-claude-langgraph-langsmith.html` (r2). Week 1 = ADAF Gates 0–1 · Week 2 = Gate 2 + spine · Week 3 = Gate 3 + hardening.*

---

## Prerequisites (Day 0, ~2 hrs)

- [x] Claude Code installed and authenticated (`claude --version`); Claude API key (or Bedrock/Vertex profile)
- [x] GitHub org/repo access with admin (rulesets, Apps); a second machine identity for agents — create GitHub App `pdlc-agent-bot`, note its app ID + private key
- [x] LangSmith account + API key (`LANGSMITH_API_KEY`)
- [ ] Docker Desktop (devcontainer + Postgres)
- [ ] Python 3.12 + `uv`
- [ ] A second-family model key for critics/judge (per r2 — any non-Claude provider via LiteLLM)

**Working method every day (non-negotiable):**
1. Start each task in **plan mode** (`Shift+Tab` in Claude Code) — review the plan before any edit.
2. **Tests before implementation** — you're building the tool that enforces this; practice it while building it.
3. One bounded session per task; `/clear` between tasks. Small commits with `Implements:` trailers from Day 4 on.
4. End of day: run the full test suite + note the day's cost from `/cost`.

---

## WEEK 1 — Substrate + bounded agents (Gates 0–1)

### Day 1 — Repo bootstrap & project skeleton
**Goal:** a Python monorepo Claude Code works well in.

Morning:
```bash
mkdir pdlc-aios && cd pdlc-aios && git init
uv init --package pdlc  # src layout
claude   # then: /init  → generates CLAUDE.md; edit it down to ≤200 lines
```
Structure to create (ask Claude Code to scaffold it in plan mode):
```
pdlc-aios/
├── CLAUDE.md                  # build cmds, conventions, do-not-touch, definition of done
├── .claude/{settings.json, commands/, agents/, skills/}
├── src/pdlc/{ears/, spine/, dispatch/, evals/, common/}
├── specs/                     # per-feature spec store
├── evals/datasets/            # golden sets (empty for now)
├── scripts/hooks/             # hook scripts
├── tests/
└── .devcontainer/             # python 3.12, uv, no host secrets mounted
```
Afternoon: pre-commit (ruff, mypy), pytest + coverage wiring, Makefile (`make test lint check`), devcontainer built and used.

**Test / DoD:** `make check` green inside the devcontainer; CLAUDE.md states where to look, what not to touch, how to prove success, when to stop; first commit pushed.

---

### Day 2 — Hooks: policy as code
**Goal:** deterministic guardrails active before any agent writes code.

Build `scripts/hooks/`:
- `deny-danger.sh` (PreToolUse:Bash) — blocks `rm -rf`, `curl|wget` egress, reads of `.env`/`*credentials*`, force-push
- `protect-paths.sh` (PreToolUse:Edit|Write) — denies writes to `specs/**/requirements.md` (post-gate), `evals/**`, `.github/**`, `scripts/hooks/**`
- `lint-test-touched.sh` (PostToolUse:Edit|Write) — ruff + pytest for touched files; nonzero exit feeds failure back into the loop

Wire into `.claude/settings.json`. Hooks receive JSON on stdin — build a **hook test harness**: `tests/hooks/test_hooks.sh` pipes recorded sample payloads (dangerous bash, protected-path write, clean edit) into each script and asserts exit codes.

**Test / DoD:** harness green in CI-style run; live check — ask Claude Code to `cat .env` and to edit `evals/x` → both visibly blocked. Hooks are now part of the repo, reviewed like code.

---

### Day 3 — GitHub: identity, invariants, CI agents
**Goal:** the outer-loop invariants platform-enforced; first two production agents live.

Morning:
- Push to GitHub; branch protection on `main`: required PR, required human review (CODEOWNERS = you), required status checks (start with `test`)
- Ruleset: only `agent/**` branches writable by `pdlc-agent-bot`; bot excluded from approvers
- `test.yml` workflow: `make check` on every PR

Afternoon — the two bounded agents (Gate 1):
- `.github/workflows/claude.yml` — `anthropics/claude-code-action@v1` on `@claude` mentions (`--max-turns 30`)
- `.github/workflows/claude-review.yml` — PR review against `Implements:` trailer, "never approve or merge" in the prompt + `claude-code-security-review` job

**Test / DoD (test the gates, not the demo):** from a token scoped as the bot: (a) push to `main` → rejected; (b) push to `agent/test` + open PR → allowed; (c) bot attempts approve → rejected; (d) `@claude` comment answers; (e) PR gets AI review + security scan comments. Screenshot each for the runbook.

---

### Day 4 — Telemetry, attribution, trailer contract
**Goal:** every future action observable and attributable; the correlation key exists.

- Enable Claude Code telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, OTLP → LangSmith or collector) in devcontainer + CI env
- `src/pdlc/common/trailers.py` — parse/emit `Implements: FEAT-x-Rn[,Rm]` and `Agent-Session: <id>` commit trailers (**TDD: tests first**)
- CI job `trailer-check`: PRs from `agent/**` must carry valid trailers → required status check
- `scripts/baseline.py` — capture the human baseline NOW (r2): median PR review cycle time, post-merge churn (via `git log --numstat` over last 90 days), deployment frequency; write to `metrics/baseline.json`

**Test / DoD:** trailer unit tests green; a trailer-less agent PR goes red; a trace with `feature_id` tag visible in LangSmith; `baseline.json` committed — this is what Gate-4 claims will be measured against.

---

### Day 5 — EARS validator + eval skeleton (report-only)
**Goal:** the machine-checkable core of the whole system, test-first.

Morning — `src/pdlc/ears/`:
- `patterns.py` — the 5 EARS templates as compiled regexes + `validate(req) -> (bool, pattern, reason)`
- `slicer.py` — INVEST size heuristics, oversized-story flag
- **Write the test suite first** (~40 cases: valid per pattern, near-misses, compound sentences, missing SHALL, `untestable:` flag pass-through)

Afternoon — eval skeleton:
- `evals/datasets/` — seed `rdr-formalize` with 15 synthetic story→EARS pairs (Claude Code generates, you review each one — these are your gold labels)
- `src/pdlc/evals/run.py` — runs a target over a dataset, scores with deterministic evaluators, writes report; LangSmith `evaluate()` wiring
- CI job `evals` — **report-only** (prints scores, never fails) per the r2 cold-start rule

**Test / DoD:** EARS tests green (aim 100% branch coverage on `patterns.py`); `python -m pdlc.evals.run --dataset rdr-formalize --report-only` produces a scored report in CI logs. **Week-1 exit = Gate 0 done + Gate 1 agents live.**

---

## WEEK 2 — Inner loop + spine (Gate 2)

### Day 6 — RDR slash commands (CLI-first, no LangGraph yet)
**Goal:** the five-stage RDR flow as Claude Code commands operating on `specs/`.

Build `.claude/commands/`:
- `clarify.md` — ingest brief → `specs/$FEAT/open-questions.md` + `candidate-stories.md`; max 7 questions, one at a time, never invents answers
- `formalize.md` — refuses while open questions unanswered (checks the file); emits `requirements.md` with EARS + stable IDs; runs `python -m pdlc.ears.validate` on its own output before finishing
- `design.md` — `design.md` + terse ADRs; ends by invoking both critic subagents (Day 7)
- `plan-tasks.md` — `tasks.md`, atomic tasks with `_Requirements:_` back-links, one-session-sized
- `delta.md` — the Tier-0/1 path: one-paragraph delta spec + tasks, skips G1/G2

**Test / DoD:** create `specs/FEAT-001/brief.md` (pick a real small feature — suggest: "the spine ingest service" itself, dogfooding). Run `/clarify` → answer questions in the file → `/formalize` → verify: EARS validator passes ≥ .98, formalize *refused* before answers existed. Commit artifacts.

---

### Day 7 — Critic subagents (cross-family where it counts)
**Goal:** independent verification wired in; never self-grading.

`.claude/agents/`:
- `threat-critic.md` — STRIDE over design.md; read-only tools; findings only
- `consistency-critic.md` — every EARS req ↔ design element, orphans both directions
- `code-reviewer.md` — diff vs linked EARS criteria + rubric; read-only; used by the dispatcher (Day 8)

Configure the critics on the second model family via env-driven model pin (r2). Build the **planted-defect test**: `tests/critics/` holds a design doc with 6 planted flaws (2 security, 2 coverage gaps, 2 inconsistencies) + a clean doc; a script runs each critic headless (`claude -p`) and asserts recall ≥ 5/6, false positives ≤ 2 on the clean doc.

**Test / DoD:** planted-defect assertions pass; run `/design` on FEAT-001 → critics' findings surface; you (architect) approve → status flips in a `gate-log.md`. Promote critic outputs into a new `design-critics` eval dataset.

---

### Day 8 — Task dispatcher (Agent SDK)
**Goal:** one bounded, policy-hooked session per task — the inner loop engine.

`src/pdlc/dispatch/`:
- `contract.py` — handoff builder: one task + linked EARS reqs + relevant design slice + CLAUDE.md pointer (never the whole spec) — **TDD**
- `runner.py` — Claude Agent SDK `query()` with `max_turns=40`, `permission_mode="acceptEdits"`, cwd = ephemeral worktree (`git worktree add`), model pin Sonnet; streams messages → LangSmith with `feature_id`/`task_id` tags
- Session prompt enforces: failing tests first (one per EARS criterion, named `test_<req_id>_*`), tests never modified after writing, commit with trailers
- After implement: fresh `code-reviewer` session over the diff; loop findings back, max 3 rounds; then push `agent/FEAT-x-task-n` + open draft PR via `gh`

**Test / DoD:** dispatch FEAT-001 task 1 end-to-end: verify in the transcript that tests were written first; trailers present; draft PR opened; PR review + security agents commented; **you** merge. Integration test `tests/dispatch/test_toy_task.py` runs the loop on a trivial fixture repo in CI (with `--max-turns 12`).

---

### Day 9 — Postgres traceability spine
**Goal:** every merge traceable; warn-and-queue degradation.

- `docker-compose.yml`: Postgres 16 (dev); `src/pdlc/spine/schema.sql` — tables per brief §7 (requirements, design_elements, tasks, prs, tests + link tables + gate_decisions)
- `spine/ingest.py` — RDR artifacts → rows (called at end of `/plan-tasks`); webhook-style ingest for merged PRs (parses trailers + `test_<req_id>` names from the diff) — **TDD with fixture git history**
- `spine/check.py` — the orphan SQL from the brief; exit 0 / warn / fail by risk tier; **warn-and-queue** file when DB unreachable, 24h grace
- CI job `traceability` (warn-only this week)

**Test / DoD:** unit + integration tests green; ingest FEAT-001's history → `check.py` reports zero orphans; stop Postgres → check degrades to warn + queue entry (drill, not assumption).

---

### Day 10 — End-to-end dry run + cost model v1
**Goal:** the full Gate-2 loop proven on a second real feature; publish the number.

- Run FEAT-002 (suggest: "steward drift-detection job") through the complete flow: `/clarify` → G1 → `/formalize` → `/design` + critics → G2 → `/plan-tasks` → dispatch each task → review → merge → spine check
- Fix every point of friction you hit (this day always finds 5–10)
- `scripts/cost_model.py` — pull the week's traces, compute: cost per RDR stage, per task, per critic round, per accepted PR → `metrics/cost-model.md` (r2 Gate-2 entry evidence)
- Promote all G1/G2 corrections + reviewer comments into eval datasets (`rdr-clarify`, `rdr-formalize`, `design-critics`, `code-review`)

**Test / DoD:** FEAT-002 merged with zero invariant violations; cost-per-accepted-PR documented; each dataset ≥ 25 examples. **Week-2 exit = Gate 2 done.**

---

## WEEK 3 — RDR graph, enforcement, hardening (Gate 3+)

### Day 11 — LangGraph service: graph topology, fake-model tests
**Goal:** the durable pipeline, testable without burning tokens.

- `uv add langgraph langchain-anthropic langgraph-checkpoint-postgres`; pin exact versions (r2); `src/pdlc/graph/`
- `state.py` — `RDRState` TypedDict + pydantic models (from the brief §4.1); `nodes.py` — clarify/formalize/design/critics/planner nodes *wrapping the same prompts the slash commands use* (one prompt source, two runtimes)
- **Fake-model test harness**: inject a scripted chat model; assert topology — clarify→pm_gate loops on unanswered questions, critics run in parallel, gate_log written. No API calls in CI.
- PostgresSaver wired; `thread_id = feature_id`

**Test / DoD:** `pytest tests/graph/` green with zero network; a live smoke run of clarify+formalize nodes on FEAT-003's brief matches Day-6 CLI output quality.

---

### Day 12 — Durable gates + minimal Agent Inbox
**Goal:** `interrupt()` gates a human can answer tomorrow.

- `pm_gate` / `architect_gate` nodes via `interrupt()` + `Command` routing (brief §4.2–4.3)
- Minimal inbox: FastAPI app `src/pdlc/inbox/` — `GET /pending` (list interrupted threads w/ payload + trace link), `POST /answer/{thread}` (resume). CLI wrapper `pdlc inbox`.
- Risk-tier field at intake; Tier-0/1 routes to delta graph

**Test / DoD:** integration test — start FEAT-003 run, assert thread parks at G1; kill the process; restart; answer via inbox; assert state resumed exactly (checkpoint proof). Live: leave a gate pending overnight tonight, answer tomorrow morning.

---

### Day 13 — write_artifacts, spine registration, full-graph E2E
**Goal:** graph output = same artifacts + spine rows as the CLI path.

- `write_artifacts` node: commit specs to a branch, register in spine, emit gate_log
- Delta-path graph (3 nodes) wired to tier assignment
- **Golden E2E test**: scripted human answers → full graph run on a fixture brief → assert artifact contents, spine rows, gate_log entries match golden files

**Test / DoD:** FEAT-003 flows brief→tasks entirely through the graph (yesterday's overnight gate answered); dispatch one FEAT-003 task from a graph-produced tasks.md; traceability check passes.

---

### Day 14 — Enforcement day: evals blocking, judge validated, injection defense
**Goal:** flip from report-only to gating (r2 thresholds met).

- Each dataset now ≥ 50 examples (top up with Day-10/13 corrections + synthetics)
- Judge (cross-family) validated: run judge over 30 examples you hand-label; require agreement ≥ 85% before it gates; record in `metrics/judge-validation.md`
- Flip CI `evals` job to blocking: deterministic floors (EARS validity ≥ .98) + no-regression vs stored baseline; runs on changes to `prompts/**`, `.claude/**`, `CLAUDE.md`, `src/pdlc/graph/**`, model pins
- Injection corpus: 20 hostile issue/PR-comment payloads → run through `@claude` and PR-review surfaces in a scratch repo; assert no tool-abuse (hooks catch attempts); make it a CI red-team job (subset, weekly full run)
- Flip `traceability` to blocking for Tier ≥ 2

**Test / DoD:** deliberately degrade a prompt → eval gate goes red → merge blocked (prove it, then revert); injection suite green; judge-validation report committed.

---

### Day 15 — Hardening drills, runbook, v0.1.0
**Goal:** production posture + demo-ready.

Morning drills (each is a test, record outcomes):
1. Revoke model key mid-graph-run → graph parks at checkpoint, resumes on restore
2. Stop Postgres → spine warn-and-queue; restore → back-fill job reconciles
3. Exhaust `max_turns` on a dispatch → session ends clean, task marked incomplete, no partial commit pushed
4. Budget breach simulation → dispatch halts at 100% of feature budget

Afternoon:
- `RUNBOOK.md` — start/stop, gate answering, drill procedures, failure modes; `README.md` — architecture summary linking the r2 brief
- Dashboard note: acceptance rate, churn, gate latency, cost per accepted PR — vs Day-4 baseline
- Tag `v0.1.0`; demo script: FEAT-004 live, brief → merged PR in one sitting

**DoD:** all four drills pass; `make check` + eval gate + traceability green on main; tagged release.

---

## After Day 15 (Gate 4 — as needed, not ASAP-critical)
Canary/rollback gates on deploy targets · incident-investigator graph (propose-only) · prod signals → annotation queues · Temporal only if a real multi-week workflow appears · Neo4j only if traversal queries demand it.

## Daily rhythm summary
| Block | Practice |
|---|---|
| Start | Plan mode; review plan before edits |
| Build | Tests first; one task per session; `/clear` between |
| Verify | Day's test suite + one adversarial check ("prove the gate blocks") |
| Close | Commit w/ trailers · `/cost` into cost log · promote corrections to datasets |

**Schedule risk honesty:** 15 days assumes full-time solo focus and no enterprise-approval waits (GitHub App creation, LangSmith procurement, second-family API key are the usual blockers — clear them Day 0). Days 8, 10 and 14 are the likely slip points; the de-scope fallback per r2: ship Gates 0–2 only (Days 1–10) and you already have the highest-value slice.
