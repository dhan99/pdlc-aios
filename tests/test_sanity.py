"""Repo-level sanity checks: the package imports, the interpreter is pinned, CLAUDE.md fits."""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# Agent context budget. CLAUDE.md is loaded into every agent session, so it stays
# small enough to read in full. See CLAUDE.md.
CLAUDE_MD_MAX_LINES = 200


def test_pdlc_imports() -> None:
    import pdlc

    assert pdlc.__doc__, "pdlc package is missing its module docstring"


def test_python_version_is_pinned() -> None:
    assert sys.version_info[:2] == (3, 14), (
        f"expected Python 3.14 (see .python-version and requires-python), "
        f"got {sys.version.split()[0]}"
    )


def test_claude_md_within_context_budget() -> None:
    claude_md = REPO_ROOT / "CLAUDE.md"
    assert claude_md.is_file(), f"CLAUDE.md not found at {claude_md}"

    line_count = len(claude_md.read_text(encoding="utf-8").splitlines())
    assert line_count <= CLAUDE_MD_MAX_LINES, (
        f"CLAUDE.md is {line_count} lines, over the {CLAUDE_MD_MAX_LINES}-line budget"
    )
