# Release

Releasing is automated. Pushing a version tag triggers the
[`release` workflow](../.github/workflows/release.yaml), which builds the
package and creates the GitHub release with the artifacts.

To cut a release, run one command. The version is `X.Y.Z`
(`major.minor.patch`), and the `BUMP` you choose increments one number and
resets the numbers to its right to `0`:

```sh
make release              # patch: 0.12.1 -> 0.12.2 (small changes)
make release BUMP=minor   # minor: 0.12.1 -> 0.13.0  (big changes)
make release BUMP=major   # major: 0.12.1 -> 1.0.0   (breaking changes)
make release VERSION=0.13.0  # pin an exact version, no arithmetic
```

Preview a bump without changing anything with `uv version --bump <level>
--dry-run`.

This runs the checks, bumps the version, syncs the lockfile, then commits, tags
and pushes. The workflow takes over from the tag push:

- Builds the package with `uv build`
- Creates the GitHub release with auto-generated notes and the built artifacts

## The versioning scheme

Mackeep is young, so the version numbers stay low:

- `0.12.X` for the small changes: bug fixes, documentation, refactoring,
  small features.
- `0.13.0` for the big changes: a new feature that changes the behaviour of
  the tool, a new configuration format, a new command.
- `1.0.0` when the format of the configuration files and the behaviour of
  the tool are frozen.

The first release of Mackeep is `0.12.1`.

## The distribution

Mackeep is distributed with [Homebrew](https://brew.sh/), it is not published
on PyPI. The formula lives in the
[homebrew tap](https://github.com/Joynik/homebrew-tap) and points to the
release of the matching version:

```bash
# Install
brew install Joynik/tap/mackeep
```

The formula is updated automatically: the
[homebrew tap](https://github.com/Joynik/homebrew-tap) runs a workflow that
checks the latest release, updates the version, the URL and the checksum of
the formula, and commits the result.
