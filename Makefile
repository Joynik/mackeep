.PHONY: lint ruff ty test format format-check typecheck verify coverage coverage-report check clean binary release

lint test format format-check typecheck verify coverage coverage-report:
	mise run $@

ruff: lint

ty: typecheck

check: verify

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

# Cut a release in one command. Bumps the version of the tool and of the
# application, syncs the lockfile, then commits, tags and pushes. The release
# workflow takes over from the tag push.
# BUMP defaults to patch. See doc/release.md for usage.
BUMP ?= patch

release: check
	@if [ -n "$(VERSION)" ]; then uv version "$(VERSION)"; else uv version --bump $(BUMP); fi
	uv sync -U
	@V=$$(uv version --short); \
	python3 desktop/Tools/sync_version.py "$$V" && \
	git commit -am "Mackeep $$V" && \
	git tag "$$V" && \
	git push && \
	git push origin "$$V" && \
	echo "Released $$V"
