# Installation

## CLI

Install on macOS or Linux with [Homebrew](https://brew.sh/):

```bash
brew install Joynik/tap/mackeep-cli
mackeep-cli --version
```

The distributed CLI is a standalone binary; Python is not required. Release
archives are available for macOS ARM64 and Linux x86-64/ARM64 on the
[releases page](https://github.com/Joynik/mackeep/releases).

For manual installation, extract the entire archive and keep the executable
with its accompanying runtime files. Add its directory to `PATH`.

Follow the [quickstart](README.md#quickstart) to select storage and applications.
Installation alone does not configure storage or restore files.

## Desktop

Install the desktop application with Homebrew:

```bash
brew install joynik/tap/mackeep
```

It requires macOS 15+ on Apple Silicon and the CLI installed separately as shown
above. If installing manually, download `Mackeep-<version>-macos-arm64.dmg` from
the releases page and drag `Mackeep.app` into Applications.
See the desktop guide below if the CLI is not detected.

Release builds are signed ad-hoc and are not notarized. macOS may require
explicit approval to open a downloaded build. See the
[desktop guide](desktop/README.md) for behavior and build instructions.

## Upgrade or remove

```bash
brew update
brew upgrade mackeep-cli

# Remove the CLI executable
brew uninstall mackeep-cli
```

Update the desktop application with `brew upgrade mackeep`, or use the disk
image of the same release.
Removing executables does not restore linked files or delete your configuration
and backups. If using legacy link mode, run `mackeep-cli link uninstall` before
removing the CLI.

## Development checkout

Building from source requires Python 3.14+ and uv. See the
[development guide](doc/develop.md); source environments are separate from the
Homebrew installation.
