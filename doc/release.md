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
agreement and calls the reusable test workflow on the exact tag. Python tests
run on all configured platforms, together with Swift unit/integration tests.
Only after those pass does it build and smoke-test the CLI archives and build
the desktop disk image. Both build jobs must succeed before publication.
A plain branch push runs validation workflows but does not create a release.
For a manual workflow run, select the existing version tag; branch runs skip
the release jobs. Runs for the same tag are serialized without cancelling a
release already in progress.

## Artifacts

| Artifact | Platform |
| --- | --- |
| `mackeep-cli-<version>-macos-arm64.tar.gz` | macOS Apple Silicon |
| `mackeep-cli-<version>-linux-x86_64.tar.gz` | Linux x86-64 |
| `mackeep-cli-<version>-linux-arm64.tar.gz` | Linux ARM64 |
| `Mackeep-<version>-macos-arm64.dmg` | Desktop, macOS 15+ on Apple Silicon |
| `SHA256SUMS` | SHA-256 hashes of all four downloadable packages |

CLI archives contain a directory with the executable and runtime files; keep
them together. Python is not required on the target machine. macOS artifacts
are signed ad-hoc, not notarized. Download `SHA256SUMS` alongside the packages
you want to verify. On macOS, `shasum -a 256 <package>` prints a hash to compare
with the matching line. With all four packages present, use
`shasum -a 256 -c SHA256SUMS` (Linux: `sha256sum --check SHA256SUMS`).
Checksums detect changed downloads; they are not a signature or notarization.

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
