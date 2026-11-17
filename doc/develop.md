# Development

Use Python 3.14+ and [uv](https://docs.astral.sh/uv/). Run these commands from the repository root:

```bash
git clone https://github.com/Joynik/mackeep.git
cd mackeep
uv sync --dev
uv run mackeep-cli --version
make check
```

`uv sync` creates the local environment and installs development dependencies. The runtime depends
only on the standard library and `docopt-ng`.

## Checks

`Makefile` delegates checks to `mise.toml`. Change task implementations in mise; the Make commands
remain stable. Install mise and the selected tools before running checks.

| Command | mise task | Checks |
| --- | --- | --- |
| `make check` | `verify` | All checks, then Python and Desktop unit/integration tests |
| `make lint` | `lint` | Ruff, rumdl and SwiftLint |
| `make ruff` | `lint` | Compatibility alias for `make lint` |
| `make ty` / `make typecheck` | `typecheck` | Python types and a Desktop Debug build |
| `make format-check` | `format-check` | Python, Markdown and Swift formatting |
| `make format` | `format` | Apply formatting |
| `make test` | `test` | Python and Desktop unit/integration tests |
| `make coverage` | `coverage` | Python branch coverage; fails below 90%; writes HTML/XML reports |
| `make coverage-report` | `coverage-report` | Display the last Python coverage result |

Desktop tasks generate the Xcode project with XcodeGen and use `desktop/build/mise` for build
products. Local mise builds disable code signing. Tests use a separate bundle identifier and run
`MackeepDesktopTests`; UI tests remain a separate manual check. Packaging and publication remain in
the Makefiles.

Run a focused test with `uv run python -m pytest tests/test_excludes.py -q`. GitHub Actions runs
Ruff, ty, and Markdown in separate workflows on pushes to `master` and pull requests. Tests cover
Python 3.14 on Ubuntu 24.04/26.04 and macOS 15. CI checks that `uv.lock` is current with
`uv sync --locked --dev`.

Changes limited to `src/mackeep/applications/*.cfg` use the library workflow: catalog validation,
publisher tests, and manifest publication. A separate workflow uses `pre-commit-hooks` to require
exactly one final newline in application definitions. It fails when files need correction and does
not publish fixes. Run `mise run applications:format` locally to correct only these `.cfg` files.
Code changes and releases keep the full CI suite. Generated `library-manifest.json` updates do not
trigger the general workflows.

The HTML coverage report is `htmlcov/index.html`. Tests must use temporary HOME and XDG directories,
avoid network access, and never operate on real backups. See [test conventions](../tests/README.md).

## Exercise a custom application safely

Create a disposable HOME and an existing storage directory. Put a test `.mackeep.cfg` and custom
application definition there, then run the checkout with `HOME` and `XDG_CONFIG_HOME` set to those
directories. Start with `--dry-run`. An environment variable alone is not a sandbox: definitions
must also point only at disposable files.

Built-in definitions live in `src/mackeep/applications/`. Custom definitions and exclusions are
described in the [configuration guide](README.md#custom-applications). A development checkout does
not need to replace the installed CLI.

## Desktop and packaging

See [desktop/README.md](../desktop/README.md) for Xcode builds and tests. `make binary` builds the
standalone CLI in `dist-bin/mackeep-cli/`; it creates a separate build environment and installs
build tools. Do not use it as a test of the user's installed CLI. Publishing is covered by the
[release guide](release.md).

Keep generated results out of commits. Remove temporary logs and verification artifacts when
finished; `make clean` also removes build and coverage outputs.
