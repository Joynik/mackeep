# Release

CLI and desktop share a version and are released together. Distribution is
through GitHub release artifacts and Homebrew, not PyPI.

## Before publishing

- Commit the intended changes, including new files; keep the working tree clean.
- Run `make check` and obtain green CI for the commit being released.
- Validate desktop builds/tests when desktop or the JSON contract changed.
- Check migration notes for storage, cleanup, configuration, or schema changes.

Do not run the root `make release` just to create a local build: it commits,
tags, and pushes.

## Publish

From the repository root:

```bash
make release                    # Increment patch
make release BUMP=minor          # Increment minor, reset patch
make release BUMP=major          # Increment major, reset minor/patch
make release VERSION=0.23.0      # Use an exact version
```

Preview the version calculation without changing files:

```bash
uv version --bump minor --dry-run
```

The target runs checks, changes the Python version, synchronizes dependencies
and the lockfile, updates `desktop/project.yml`, commits tracked changes, creates
a version tag, and pushes the branch and tag. It runs `uv sync -U`, which can
also update dependencies; review that behavior before using it for a release
requiring a fixed dependency set. It does not automatically stage untracked files.

The [release workflow](../.github/workflows/release.yaml) checks tag/version
agreement, builds and tests archives, builds the desktop disk image, and creates
the GitHub release with generated notes after both build jobs succeed.
A plain branch push runs validation workflows but does not create a release.

## Artifacts

| Artifact | Platform |
| --- | --- |
| `mackeep-cli-<version>-macos-arm64.tar.gz` | macOS Apple Silicon |
| `mackeep-cli-<version>-linux-x86_64.tar.gz` | Linux x86-64 |
| `mackeep-cli-<version>-linux-arm64.tar.gz` | Linux ARM64 |
| `Mackeep-<version>-macos-arm64.dmg` | Desktop, macOS 15+ on Apple Silicon |

CLI archives contain a directory with the executable and runtime files; keep
them together. Python is not required on the target machine. macOS artifacts
are signed ad-hoc, not notarized.

The Homebrew formula in the separate
[homebrew tap](https://github.com/Joynik/homebrew-tap) is updated by its own
release-monitoring automation. The formula is not maintained in this repository.
Verify the published version and installation after that update completes.

## Build without publishing

`make binary` at the root builds the standalone CLI using Nuitka, installs build
tools in `.build-venv`, and writes `dist-bin/mackeep-cli/`.

For the desktop disk image, run from the root:

```bash
make -C desktop package XCODEBUILD_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="
```

This builds Release and writes the image into `dist/`; it does not publish it.
See the [desktop guide](../desktop/README.md) for signing and tests.

## Versioning

- `0.0.X`: small fixes, documentation, or refactoring.
- `0.X.0`: substantial features or behavior/configuration changes.
- `X.0.0`: a frozen public configuration and behavior contract.

JSON schema versions are separate from release versions. Breaking schema
changes need a schema bump and matching desktop/documentation updates.
