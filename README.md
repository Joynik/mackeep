# Mackeep

[![Tests](https://github.com/Joynik/mackeep/actions/workflows/test.yaml/badge.svg)](https://github.com/Joynik/mackeep/actions/workflows/test.yaml)
[![Ruff](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json)](https://github.com/astral-sh/ruff)
[![mypy](https://img.shields.io/badge/mypy-checked-blue)](https://mypy-lang.org/)
[![ty](https://github.com/Joynik/mackeep/actions/workflows/ty.yaml/badge.svg)](https://github.com/Joynik/mackeep/actions/workflows/ty.yaml)
[![License](https://img.shields.io/github/license/Joynik/mackeep.svg)](LICENSE)

Back up and restore application settings on macOS and Linux. Mackeep copies
selected files into a storage folder; Dropbox, iCloud, or another sync client
can transfer that folder between machines.

The native macOS desktop application edits the same configuration and runs
operations through the CLI. Backups are manual snapshots, not continuous sync.

## Quickstart

Install the standalone CLI with [Homebrew](https://brew.sh/):

```bash
brew install joynik/tap/mackeep-cli
mackeep-cli config
```

For the native desktop interface on macOS 15+ with Apple Silicon, also install:

```bash
brew install joynik/tap/mackeep
```

The desktop app uses the CLI installed above. See the
[installation guide](INSTALL.md#desktop) for details and manual disk images.

The first ordinary run creates `~/.mackeep.cfg` and `~/.mackeep/`. Choose storage
in desktop settings or edit the config. The storage path must already exist:

```ini
[storage]
engine = file_system
path = /absolute/path/to/storage
directory = Mackeep

[applications_to_sync]
git
vim
```

Review the plan, then back up:

```bash
mackeep-cli --dry-run backup
mackeep-cli backup
```

On another machine, install Mackeep, configure the same storage, wait for it to
sync, and run `mackeep-cli restore`. Existing destinations require confirmation;
restore replaces files and does not merge their contents.

## Commands

| Command | Purpose |
| --- | --- |
| `mackeep-cli list` | List supported application identifiers |
| `mackeep-cli show git` | Show an application's configured paths and exclusions |
| `mackeep-cli config` | Show active configuration and storage |
| `mackeep-cli backup [application]` | Copy local settings into storage |
| `mackeep-cli restore [application]` | Copy stored settings back locally |
| `mackeep-cli migrate --dry-run` | Preview migration from Mackup |
| `mackeep-cli --help` | Show all commands and options |
| `mackeep-cli --version` | Show the installed version |

A named application overrides selection and ignore lists for that command.
Without a name, `[applications_to_sync]` selects applications and
`[applications_to_ignore]` removes them. An absent selection section means all
supported applications; an explicitly empty section means none.

Use `--dry-run` to preview backup/restore without writing, `--force` to accept
replacements, and `--force-no` to decline them. The `mackeep` alias also invokes
the CLI.

Legacy `link install`, `link`, and `link uninstall` commands remain available.
Use copy mode on current macOS: symlinked preferences can fail on macOS 14+.

## Before backing up

- A successful backup replaces the selected application's stored snapshot.
  Previously tracked files removed from its rules or newly excluded are cleaned
  up, unless another application owns them.
- Restore preserves excluded local files. It does not combine different versions
  of a configuration file; [merge them first](doc/configuration_merge_guide.md).
- Backups are unencrypted. Sensitive-path warnings do not detect every secret.
- Local operations by the same user are locked per storage folder. Run only one
  operation across your computers at a time; cloud sync does not share this lock.
  Replacement rollback handles errors but is not a recovery journal for power loss.

## Documentation

- [Installation and upgrades](INSTALL.md)
- [Configuration, exclusions, operation behavior, and JSON](doc/README.md)
- [Desktop application](desktop/README.md)
- [Architecture](doc/ARCHITECTURE.md)
- [Development and tests](doc/develop.md)
- [Contributing](.github/CONTRIBUTING.md)
- [Release process](doc/release.md)

## Credits

Mackeep is a fork of [Mackup](https://github.com/lra/mackup), written by
[Laurent Raufaste](https://github.com/lra). It is distributed under the
[GPL-3.0](LICENSE) license, like the original project.
