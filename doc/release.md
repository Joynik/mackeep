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

- Builds the standalone binary with [Nuitka](https://nuitka.net), one per
  platform (macOS and Linux)
- Creates the GitHub release with auto-generated notes and the binaries

The application of the desktop is released with the tool, they share the same
version. The `make release` command writes the version of the release in
`desktop/project.yml`, so the version of the application is always the one of
the release, in the "About" window too.

The releases hold one package per platform:

```text
mackeep-cli-0.14.0-macos-arm64.tar.gz
mackeep-cli-0.14.0-linux-x86_64.tar.gz
```

Each package holds the `mackeep-cli` folder with the binary and the runtime
it needs, so Python is not required to run it. The binary is a folder and
not a single file on purpose: a single file has to unpack itself on every
run, that takes seconds. The binary can also be built locally, with
`make binary`.

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
brew install Joynik/tap/mackeep-cli
```

The formula is updated automatically: the
[homebrew tap](https://github.com/Joynik/homebrew-tap) runs a workflow that
checks the latest release, updates the version, the URL and the checksum of
the formula, and commits the result.
