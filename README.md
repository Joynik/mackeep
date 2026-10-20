# Mackeep

[![Tests](https://github.com/Joynik/mackeep/actions/workflows/test.yaml/badge.svg)](https://github.com/Joynik/mackeep/actions/workflows/test.yaml)
[![Ruff](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json)](https://github.com/astral-sh/ruff)
[![mypy](https://img.shields.io/badge/mypy-checked-blue)](http://mypy-lang.org/)
[![License](https://img.shields.io/github/license/Joynik/mackeep.svg)](https://github.com/Joynik/mackeep/blob/master/LICENSE)

Backup and keep your application settings in sync.

## Table of contents

- [Mackeep](#mackeep)
  - [Table of contents](#table-of-contents)
  - [Quickstart](#quickstart)
  - [Usage](#usage)
  - [What does it do](#what-does-it-do)
    - [Copy mode](#copy-mode)
    - [Link mode](#link-mode)
      - [`mackeep-cli link install`](#mackeep-cli-link-install)
      - [`mackeep-cli link`](#mackeep-cli-link)
      - [`mackeep-cli link uninstall`](#mackeep-cli-link-uninstall)
  - [Supported Storages](#supported-storages)
  - [Personalization \& configuration](#personalization--configuration)
  - [What's new in Mackeep](#whats-new-in-mackeep)
  - [What platforms are supported](#what-platforms-are-supported)
  - [Architecture](#architecture)
  - [Credits](#credits)
  - [Where can I find more information](#where-can-i-find-more-information)

## Quickstart

On macOS or Linux, install the terminal version with
[Homebrew](https://brew.sh/):

```bash
# Install the terminal version of Mackeep
brew install Joynik/tap/mackeep-cli

# Launch it and back up your files
mackeep-cli backup
```

You're all set and can back up from now on.

Next, on any new workstation, do:

```bash
# Install Mackeep
brew install Joynik/tap/mackeep-cli

# Launch it and restore your files
mackeep-cli restore
```

Done!

You can find more detailed instructions in [INSTALL.md](INSTALL.md).

## Usage

`backup`, `restore`, `link install`, `link uninstall` and `link` operate on all
of your configured applications by default. To limit a command to a single
application, add its name (the identifier shown by `mackeep-cli list`), e.g.
`mackeep-cli backup vim`. Naming an application overrides the
`[applications_to_sync]` / `[applications_to_ignore]` settings in your
`.mackeep.cfg`, so you can act on any supported app without editing your config.

`mackeep-cli backup [application]`

Back up your application files. Copy your local config files into the Mackeep folder.
Name an application to back up only that one, e.g. `mackeep-cli backup vim`.

`mackeep-cli restore [application]`

Restore your application settings on a newly installed workstation.
Copy config files from the Mackeep folder to your home folder.
Name an application to restore only that one, e.g. `mackeep-cli restore emacs`.

`mackeep-cli link install [application]`

Move your local config files into the Mackeep folder,
and link them to their original place.
Name an application to install only that one.

$${\color{red}warning}$$ _the `link` strategy [doesn't work correctly on macOS](#link-mode)_

`mackeep-cli link [application]`

On another workstation, links local config files from the Mackeep folder.
Name an application to link only that one.

`mackeep-cli link uninstall [application]`

Copy back any synced config file to its original place.
Removes the links and copies config files from the Mackeep folder back into your
home.
Name an application (e.g. `mackeep-cli link uninstall git`) to unlink only that one;
scoping to an application skips the global uninstall confirmation.

`mackeep-cli list`

Display the list of applications supported by Mackeep.

`mackeep-cli -h`

Get some help, obviously...

`mackeep-cli -v`, `mackeep-cli -V` or `mackeep-cli --version`

Display the version of Mackeep.

## What does it do

By only tracking pure configuration files, it keeps the crap out of your
freshly new installed workstation (no cache, temporary and locally specific
files are transferred).

Mackeep makes setting up the environment easy and simple.

There are 2 modes of operations: copy mode and link mode.

### Copy mode

Copy mode is used to back up and restore your files.
The files are backed up into the configured Mackeep folder,
which can be in Dropbox, iCloud, or wherever you configure it.

It is covered by the 2 commands:

- `mackeep-cli backup`
- `mackeep-cli restore`

### Link mode

> [!WARNING]
> If you are using Mackeep on a current version of macOS, link mode will BREAK
  YOUR PREFERENCES. macOS Sonoma (macOS 14) and later don't support symlinked
  preferences.

Link mode is used to move your config files into the Mackeep folder,
and link them back to their original place.

This mode is useful if you are using multiple workstations,
and want to keep your application settings in sync at all times.

- Backs up your application settings in a safe directory (e.g. Dropbox)
- Syncs your application settings among all your workstations
- Restores your configuration on any fresh install in one command line

Let's take `git` as an example. Your settings for `git` are saved in your home
folder, in the `.gitconfig` file.

It is covered by the 3 commands:

- `mackeep-cli link install`
- `mackeep-cli link`
- `mackeep-cli link uninstall`

#### `mackeep-cli link install`

If you have Dropbox, these things happen when you launch `mackeep-cli link install`:

1. `cp ~/.gitconfig ~/Dropbox/Mackeep/.gitconfig`
2. `rm ~/.gitconfig`
3. `ln -s ~/Dropbox/Mackeep/.gitconfig ~/.gitconfig`

Now your `git` config is always backed up and up to date on all your workstations.

#### `mackeep-cli link`

When you launch `mackeep-cli link`, here's what it's really doing:

1. `ln -s ~/Dropbox/Mackeep/.gitconfig ~/.gitconfig`

That's it, you got your `git` config setup on your new workstation.

`mackeep-cli` does the same for any supported application.

#### `mackeep-cli link uninstall`

You can revert all your files to their original state.

```bash
# Just run this
mackeep-cli link uninstall
```

This will remove the symlinks and copy back the files from the Mackeep folder in
Dropbox to their original places in your home. The Mackeep folder and the files
in it stay put, so that any other computer also running Mackeep is unaffected.

To revert a single application instead, name it, e.g.
`mackeep-cli link uninstall git`. Scoping the command to an application unlinks only
that app — the rest of your setup and the Mackeep config itself are left in
place, and the global uninstall confirmation is skipped.

## Supported Storages

- [Dropbox](https://www.dropbox.com/)
- [Google Drive](https://drive.google.com/)
- [iCloud](http://www.apple.com/icloud/)
- Anything able to sync a folder (e.g. [Git](http://git-scm.com/))

See the [README](doc/README.md) file in the doc directory for more info.

## Personalization & configuration

Have an application that shouldn't be generally supported but that you use?
Or some personal files you want to sync, e.g. various config files in a `~/.config/`
directory or your personal `~/.gitignore`?

- Create a `~/.mackeep` directory to [sync an application or any file or directory](doc#add-support-for-an-application-or-any-file-or-directory)

## What's new in Mackeep

Mackeep is a fork of [Mackup](https://github.com/lra/mackup) by
[Laurent Raufaste](https://github.com/lra), with the following additions:

- **Exclusions**: the `[exclude]` and `[xdg_exclude]` sections of the
  application config files list the files and the patterns that must never be
  backed up (caches, lock files, machine specific settings...). The patterns
  follow the `.gitignore` semantics. See
  [the documentation](doc/README.md#exclusions).
- **A JSON interface**: the `--json` option writes a machine-readable
  answer, so a graphical front-end can be built on top of Mackeep. See
  [the documentation](doc/README.md#json-interface).
- **A detailed dry-run**: the `--detail files` option describes the
  backup file by file, and tells which pattern excluded each file. See
  [the documentation](doc/README.md#the-detail-levels-of-the-dry-run).
- **Compatibility with Mackup**: the config files of Mackup are still
  read, and `mackeep-cli migrate` copies them to their new location. See
  [the documentation](doc/README.md#compatibility-with-mackup).

```bash
mackeep-cli --json list
mackeep-cli --json backup --dry-run
mackeep-cli --json backup --dry-run --detail files
mackeep-cli migrate
```

A graphical front-end is on the way.

The versioning follows the same idea: the small changes are released as
`0.12.X` and the big ones as `0.13.0`. See the
[release guide](doc/release.md).

## What platforms are supported

- macOS
- GNU/Linux

## Architecture

Want to understand how Mackeep works internally? Check out the
[Architecture Guide](doc/ARCHITECTURE.md) which includes:

- Visual architecture diagram
- Component breakdown
- Data flow diagrams
- Design decisions
- Extension points for contributors

Perfect for contributors who want to understand the codebase or users
curious about how their configs are managed.

## Credits

Mackeep is a fork of [Mackup](https://github.com/lra/mackup), written by
[Laurent Raufaste](https://github.com/lra). It is distributed under the
[GPL-3.0](LICENSE) license, like the original project. Thanks to all the
[contributors](https://github.com/lra/mackup/graphs/contributors) of Mackup.

## Where can I find more information

In the [doc](doc) directory.
