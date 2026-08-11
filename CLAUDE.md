# pdlc-aios

AIOS-based AI-assisted PDLC platform. Python 3.14, uv, src layout.
Architecture source of truth: v2 technical brief r2 (PDLC-DEV/v2-technical-brief-claude-langgraph-langsmith.html).

## Commands
- `make check`  - lint + typecheck + tests. Run before EVERY commit. This is the definition of green.
- `make test`   - pytest only (fast loop)
- `make lint`   - ruff + mypy
- `uv add X`    - add dependency (never pip install; never edit pyproject deps by hand)

## Layout
- `src/pdlc/ears/`      - EARS requirement validation (5 patterns, regex-based, deterministic)
- `src/pdlc/spine/`     - Postgres traceability (req↔design↔task↔PR↔test)
- `src/pdlc/dispatch/`  - one bounded Agent SDK session per task
- `src/pdlc/evals/`     - dataset runner; report-only until seeded (r2 rule)
- `src/pdlc/common/`    - trailers, ids, config. No business logic here.
- `specs/FEAT-*/`       - requirements.md (EARS), design.md, tasks.md per feature
- `scripts/hooks/`      - policy hooks. These are LAW, reviewed like code.

## Conventions
- Tests FIRST, always. Tests derived from EARS criteria are named `test_<req_id>_*` and are never modified after they are written.
- Every commit on agent branches carries trailers: `Implements: FEAT-x-Rn` and `Agent-Session: <id>`.
- Type hints everywhere; mypy strict is a gate, not a suggestion.
- No new dependencies without asking me first.
- Branches: `agent/*` for agent work, `feat/*` for human work, `chore/*` for tooling and scaffolding.
- Trailers above are required on `agent/*` only; `chore/*` predates any FEAT and carries none.
- Never commit to or push `main`. If you are on `main`, create a branch before your first edit.

## Do not touch
- `scripts/hooks/**`, `evals/**/`, `.github/**`, `specs/**/requirements.md` after approval
- hook-enforced from Day2, but do not attempt even before then.
- Never read or write `.env`, `*.pem`, `~/.secrets/`, `SAVE/` (repo root — holds live credentials).

## Definition of done
`make check` green. new code has tests. docstrings on public fucntions. commit message explains WHY, trailers present. nothing in "do not touch"modified.

## When struck
Stop after 2 failed attempts at the same fix and ask, showing both attempts. Do not delete failing tests to make the suite pass. Ever.
