.DEFAULT_GOAL := check
.PHONY: help check test lint fmt typecheck hooks-test cov clean

help:
	@echo "check      lint + tests. The definition of green. (default target)"
	@echo "test       pytest only (fast loop)"
	@echo "lint       ruff check + ruff format --check + mypy"
	@echo "fmt        ruff format"
	@echo "typecheck  mypy only"
	@echo "hooks-test policy hook tests (skipped until Day 2)"
	@echo "cov        pytest with coverage report"
	@echo "clean      remove caches and build artifacts"

check: lint test

test:
	uv run pytest

lint:
	uv run ruff check src tests && uv run ruff format --check src tests && uv run mypy

fmt:
	uv run ruff format src tests

typecheck:
	uv run mypy

# The hook test script lands Day 2. Until then a missing script is a friendly
# skip, not a failure. Once it exists its exit status stands.
hooks-test:
	@if [ -f tests/hooks/test_hooks.sh ]; then \
		bash tests/hooks/test_hooks.sh; \
	else \
		echo "tests/hooks/test_hooks.sh not present yet — policy hooks land Day 2 (skipping)"; \
	fi

# pytest exits 5 when it collects nothing; tolerate that for coverage runs.
cov:
	@uv run pytest --cov=pdlc --cov-report=term-missing; status=$$?; \
	if [ $$status -eq 5 ]; then echo "no tests collected yet (ok)"; exit 0; fi; \
	exit $$status

clean:
	rm -rf .mypy_cache .ruff_cache .pytest_cache htmlcov .coverage coverage.xml
	find . -path ./.venv -prune -o -name __pycache__ -type d -print0 | xargs -0 rm -rf
