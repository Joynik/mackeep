# Development

Use Python 3.14+ and [uv](https://docs.astral.sh/uv/). Run these commands from
the repository root:

```bash
git clone https://github.com/Joynik/mackeep.git
cd mackeep
uv sync --dev
uv run mackeep-cli --version
make check
```

`uv sync` creates the local environment and installs development dependencies.
The runtime depends only on the standard library and `docopt-ng`.

## Checks

| Command | Checks |
| --- | --- |
| `make check` | Markdown, Ruff, mypy, ty, and pytest |
| `make lint` | Markdown with rumdl |
| `make ruff` | Python linting, including modernization and performance rules |
| `make mypy` / `make ty` | Python types |
| `make test` | Python test suite |
| `make coverage` | Branch coverage; fails below 80%; writes HTML/XML reports |
| `make coverage-report` | Display the last coverage result |

Run a focused test with `uv run python -m pytest tests/test_excludes.py -q`.
GitHub Actions runs Ruff, mypy, ty, and Markdown in separate workflows on pushes
to `master` and pull requests. Tests cover Python 3.14 on Ubuntu 24.04/26.04 and
macOS 15. CI checks that `uv.lock` is current with `uv sync --locked --dev`.

The HTML coverage report is `htmlcov/index.html`. Tests must use temporary HOME
and XDG directories, avoid network access, and never operate on real backups.
See [test conventions](../tests/README.md).

## Exercise a custom application safely

Create a disposable HOME and an existing storage directory. Put a test
`.mackeep.cfg` and custom application definition there, then run the checkout
with `HOME` and `XDG_CONFIG_HOME` set to those directories. Start with
`--dry-run`. An environment variable alone is not a sandbox: definitions must
also point only at disposable files.

Built-in definitions live in `src/mackeep/applications/`. Custom definitions and
exclusions are described in the [configuration guide](README.md#custom-applications).
A development checkout does not need to replace the installed CLI.

## Desktop and packaging

See [desktop/README.md](../desktop/README.md) for Xcode builds and tests.
`make binary` builds the standalone CLI in `dist-bin/mackeep-cli/`; it creates a
separate build environment and installs build tools. Do not use it as a test of
the user's installed CLI. Publishing is covered by the [release guide](release.md).

Keep generated results out of commits. Remove temporary logs and verification
artifacts when finished; `make clean` also removes build and coverage outputs.
