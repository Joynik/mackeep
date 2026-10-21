lint:
	uv run rumdl check .

ruff:
	uv run ruff check .

ty:
	uv run ty check

test:
	uv run pytest

coverage:
	uv run pytest --cov=mackeep --cov=mackeep_cli --cov-report=term --cov-report=html --cov-report=xml --cov-fail-under=80

coverage-report:
	uv run coverage report

mypy:
	uv run mypy src/mackeep src/mackeep_cli

check: lint ruff mypy ty test
	@echo "All checks passed!"

clean:
	rm -rf src/mackeep/__pycache__
	rm -rf src/mackeep_cli/__pycache__
	rm -rf .build-venv
	rm -rf build
	rm -rf dist-bin
	rm -rf tests/__pycache__
	rm -rf dist/
	rm -rf htmlcov/
	rm -rf .coverage
	rm -rf coverage.xml

# Build the standalone binary, like the releases do. Needs a C compiler.
# The binary is a folder, not a single file: a single file has to unpack
# itself on every run, that takes seconds.
binary:
	uv build --wheel
	uv venv .build-venv
	uv pip install --python .build-venv/bin/python dist/*.whl nuitka
	.build-venv/bin/python -m nuitka --standalone \
		--output-filename=mackeep-cli \
		--include-package=mackeep \
		--include-package-data=mackeep \
		--include-distribution-metadata=mackeep-cli \
		--assume-yes-for-downloads \
		--output-dir=dist-bin \
		src/mackeep_cli/__main__.py
	rm -rf dist-bin/mackeep-cli
	mv dist-bin/__main__.dist dist-bin/mackeep-cli

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
	git push origin "$$V" && \
	echo "Released $$V"
