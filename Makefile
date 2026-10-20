lint:
	uv run rumdl check .

ruff:
	uv run ruff check .

ty:
	uv run ty check

test:
	uv run pytest

coverage:
	uv run pytest --cov=mackeep --cov-report=term --cov-report=html --cov-report=xml

coverage-report:
	uv run coverage report

mypy:
	uv run mypy src/mackeep/

check: lint ruff mypy ty test
	@echo "All checks passed!"

clean:
	rm -rf src/mackeep/__pycache__
	rm -rf tests/__pycache__
	rm -rf dist/
	rm -rf htmlcov/
	rm -rf .coverage
	rm -rf coverage.xml

# Cut a release in one command. Bumps the version, syncs the lockfile, then
# commits, tags and pushes. The release workflow takes over from the tag push.
# Bump level defaults to patch: 0.12.X for the small changes,
# `make release BUMP=minor` for the big ones (0.13.0), `BUMP=major` for the
# breaking ones (1.0.0), or pin a version with `make release VERSION=0.13.0`.
BUMP ?= patch

release: check
	@if [ -n "$(VERSION)" ]; then uv version "$(VERSION)"; else uv version --bump $(BUMP); fi
	uv sync -U
	@V=$$(uv version --short); \
	git commit -am "Mackeep $$V" && \
	git tag "$$V" && \
	git push && \
	git push --tags && \
	echo "Released $$V"
