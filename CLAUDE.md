# pdlc-aios

AIOS-based AI-assisted PDLC platform. Python 3.14, uv, src layout.
Architecture source of truth: docs/architecture/v2-brief-r2.html (r2). Consult it for WHY decisions; do not load it wholesale — read the specific section you need.

## Commands
- `make check`  - lint + typecheck + tests. Run before EVERY commit. This is the definition of green.
- `make test`   - pytest only (fast loop)
- `make lint`   - ruff + mypy
- `uv add X`    - add dependency (never pip install; never edit pyproject deps by hand)

## Layout
- `src/pdlc/ears/`      - EARS requirement validation (5 patterns, regex-based, deterministic)
- `src/pdlc/spine/`     - Postgres traceability (req↔design↔task↔PR↔test)
- `src/pdlc/dispatch/`  - one bounded Agent SDK session per task
- `src/pdlc/evals/`     - dataset runner. See "Evals" below.
- `src/pdlc/common/`    - trailers, ids, config. No business logic here.
- `specs/FEAT-*/`       - requirements.md (EARS), design.md, tasks.md per feature
- `scripts/hooks/`      - policy hooks. These are LAW, reviewed like code.
- `evals/datasets/`     - golden data (not code). Protected; see "Do not touch".
- `metrics/`            - baseline.json, cost model. Append-only; never rewrite history.
- `docs/architecture/`  - the r2 brief and `build-plan.md`, the day-by-day plan every "Day N"
                          above refers to. Read the section you need, not the whole file.

## IDs
One grammar, used in spec dirs, trailers, tests, and the spine. Slugs are lowercase kebab-case.
- Feature:     `FEAT-<slug>`         e.g. `FEAT-ears-validator`  (dir: `specs/FEAT-ears-validator/`)
- Requirement: `FEAT-<slug>-R<n>`    e.g. `FEAT-ears-validator-R3`  (`n` counts from 1, never reused)
- Test name:   lowercase the req id, hyphens to underscores, prefix `test_`, suffix the behaviour:
  `FEAT-ears-validator-R3` -> `test_feat_ears_validator_r3_rejects_bare_shall`

## Conventions
- Tests FIRST, always. Tests derived from EARS criteria follow the test-name rule above.
  Their assertions are frozen; their mechanics are not. You may move an import, rename a fixture,
  extract a helper, reformat. You may not change, weaken, skip, xfail, or delete an assertion.
  To change what a test asserts, amend the EARS criterion in `requirements.md` first, then update
  the test in the same commit — the requirement moves and the test follows, never the reverse.
  Non-EARS tests (unit, helper) are yours to refactor freely.
- Every commit on agent branches carries trailers: `Implements: FEAT-<slug>-R<n>` and `Agent-Session: <id>`.
  `<id>` is the Agent SDK session id, exported by `dispatch/` as `$PDLC_AGENT_SESSION` and read by
  `common/`. It is what joins a commit to its transcript and LangSmith trace, so never invent one:
  if the variable is unset, stop and ask rather than guess.
- Type hints everywhere; mypy strict is a gate, not a suggestion.
- No new dependencies without asking me first.
- Branches: `agent/*` for agent work, `feat/*` for human work, `chore/*` for tooling and scaffolding.
- Trailers above are required on `agent/*` only; `chore/*` predates any FEAT and carries none.
- Never commit to or push `main`. If you are on `main`, create a branch before your first edit.

## Evals
- Seeded = at least 20 goldens in `evals/datasets/`. Below that, a pass rate is noise: one bad
  case moves it 5 points.
- Until seeded, evals are report-only. Run them, write the score to `metrics/`, and never let a
  result block a commit or a merge.
- Once seeded, a run is gated on regression against `metrics/baseline.json`:
  score below baseline blocks; score at or above it passes and rewrites the baseline;
  no baseline file yet means record it and do not block.
- Never edit `metrics/baseline.json` by hand to get to green. If a drop is a deliberate
  trade-off, say so and I will move the baseline.

## Do not touch
- `scripts/hooks/**`, `evals/**` (the top-level dir, NOT `src/pdlc/evals/`), and
  `specs/**/requirements.md` once approved. Read them freely; never modify them.
- `.github/**` is human-owned. You may draft or edit a workflow only when I ask you to in the
  current conversation, and only on a branch — never merge it, never self-approve, never edit
  it as a side effect of some other task.
- Hook-enforced from Day 2, but do not attempt even before then.
- Never read or write `.env`, `*.pem`, `~/.secrets/`, `SAVE/` (repo root — holds live credentials).

## Definition of done
`make check` green. New code has tests. Docstrings on public functions. Commit message explains WHY, trailers present. Nothing in "do not touch" modified.

## When stuck
Stop after 2 failed attempts at the same fix and ask, showing both attempts. Do not delete failing tests to make the suite pass. Ever.
