# Mackeep configuration

> 💡 **New to Mackeep?** Check out the
> [Architecture Guide](ARCHITECTURE.md) to understand how Mackeep works
> under the hood.

All the configuration is done in a file named `.mackeep.cfg` stored at the
root of your home folder. This location can be overridden via environment
variables or the `--config-file` command-line option.

To configure Mackeep, create a file named `.mackeep.cfg` in your home
directory.

```bash
vi ~/.mackeep.cfg
```

## Configuration file location

Config files are searched in the following order. If none is found, Mackeep will
use the default config location of `~/.mackeep.cfg`

- `~/.mackeep.cfg`
- `$MACKEEP_CONFIG`
- `$XDG_CONFIG_HOME/mackeep/mackeep.cfg` or `~/.config/mackeep/mackeep.cfg`
- `~/.mackup.cfg` (legacy, see [Compatibility with Mackup](#compatibility-with-mackup))
- `$XDG_CONFIG_HOME/mackup/mackup.cfg` (legacy)

You can also specify a custom config file location using the `--config-file`
command-line option:

```bash
mackeep-cli --config-file ~/.mackeep-custom.cfg backup
```

The path can be absolute or relative to your home directory. Note that the
config file must be located within your home directory for security reasons.

## Storage

You can specify the storage type Mackeep will use to store your configuration
files.

For now, you have 4 options: `dropbox`, `google_drive`, `icloud` and `file_system`.

If none is specified, Mackeep will try to use the default: `dropbox`.
With the `dropbox` storage engine, Mackeep will automatically figure out your
Dropbox folder.

### Dropbox

```ini
[storage]
engine = dropbox
```

### Google Drive

If you choose the `google_drive` storage engine instead, Mackeep will figure out
where your Google Drive is and store your configuration files in it.

```ini
[storage]
engine = google_drive
```

### iCloud

If you choose the `iCloud` storage engine, Mackeep will store your
configuration files in the `~/Library/Mobile\ Documents/com\~apple\~CloudDocs/`
folder.

```ini
[storage]
engine = icloud
```

You can check if your files are synced using:

```sh
brctl monitor com.apple.CloudDocs
```

### File System

If you want to specify another directory, you can use the `file_system` engine
and Mackeep won't try to detect any path for you: it will store your files where
you explicitly told it to, using the `path` setting.
The `path` can be absolute (from the `/` of your drive) or relative to your
home directory.
The `path` setting is mandatory when using the `file_system` engine.

```ini
[storage]
engine = file_system
path = some/folder/in/your/home
# or path = /some/folder/in/your/root
```

Note: you don't need to escape spaces or wrap the path in quotes.
For example, the following paths are valid:

```ini
path = some/path in your/home
path = /some path/in/your/root
```

### Custom Directory Name

You can customize the directory name in which Mackeep stores your files. By
default, if not specified, Mackeep creates a `Mackeep` directory in the storage
engine you chose, e.g. `~/Dropbox/Mackeep`.

```ini
[storage]
directory = Mackeep
```

For example:

```ini
[storage]
engine = file_system
path = dotfiles
directory = backup
```

This will store your files in the `~/dotfiles/backup` directory in your home.

You can also select a subfolder:

```ini
[storage]
engine = icloud
directory = .config/mackeep
```

### Switching Storage

If you ever change your mind and switch storage solutions after Mackeep is
already setup (ex: from `dropbox` to `icloud`), complete the following steps.

1. Run `mackeep-cli uninstall` on all computers
2. Copy your Mackeep files to the new storage location
3. Change the storage provider details in your `.mackeep.cfg` file (see above)
4. Run `mackeep-cli backup` on the main computer and `mackeep-cli restore` on all others

## Applications

### Only sync one or two applications

In your home folder, create a file named `.mackeep.cfg` and add the application
names to allow in the `[applications_to_sync]` section, one per line.

```ini
# Example, to only sync SSH and Adium:
[applications_to_sync]
ssh
adium
```

Use `mackeep-cli list` to get a list of valid application names. Don't use fancy
names (with spaces) here.

A [sample](.mackeep.cfg) of this file is available in this folder. Just copy it
to your home folder:

```bash
cp mackeep/doc/.mackeep.cfg ~/
```

### Don't sync an application

In your home folder, create a file named `.mackeep.cfg` and add the application
names to ignore in the `[applications_to_ignore]` section, one per line.

```ini
# Example, to not sync SSH and Adium:
[applications_to_ignore]
ssh
adium
```

Use `mackeep-cli list` to get a list of valid application names. Don't use fancy
names (with spaces) here.

A [sample](.mackeep.cfg) of this file is available in this folder. Just copy it
to your home folder:

```bash
cp mackeep/doc/.mackeep.cfg ~/
```

### Get official support for an application

Open a [new issue](https://github.com/Joynik/mackeep/issues) and ask for it, or
fork Mackeep and open a
[Pull Request](https://help.github.com/articles/using-pull-requests).
The stock application configs are in the `mackeep/applications` directory.

Remember to follow the guidelines in [CONTRIBUTING.md](https://github.com/Joynik/mackeep/blob/master/.github/CONTRIBUTING.md)
to get your Pull Request merged faster.

### Add support for an application or (almost) any file or directory

You can customize the Mackeep engine and add support for unsupported
applications or just custom files and directories you'd like to sync.

NOTE: Files and directories to be synced should be rooted at $HOME.

Let's say that you'd like to add support for Nethack (config file:
`.nethackrc`), for the `bin` and `.hidden` directories and for the
`.gitignore` file you keep in your home.

In your home, create a `.mackeep` directory and add a config file for the
application you'd like to support:

```bash
mkdir ~/.mackeep
touch ~/.mackeep/nethack.cfg
touch ~/.mackeep/my-files.cfg
```

#### Custom applications directory location

Custom application configs are searched in the following order:

1. `~/.mackeep/` (legacy location, takes priority)
2. `$XDG_CONFIG_HOME/mackeep/applications/` or `~/.config/mackeep/applications/`

If the same application config exists in both locations, the legacy location
(`~/.mackeep/`) takes priority.

For XDG-compliant setups, you can use:

```bash
mkdir -p ~/.config/mackeep/applications
touch ~/.config/mackeep/applications/nethack.cfg
```

Edit those files:

```bash
$ nano ~/.mackeep/nethack.cfg
[application]
name = Nethack

[configuration_files]
.nethackrc
```

```bash
$ nano ~/.mackeep/my-files.cfg
[application]
name = My personal synced files and dirs

[configuration_files]
bin
.hidden
.gitignore
```

Note that Mackeep assumes the file paths listed here are relative to your home
directory.

You can run mackeep-cli to see if they are listed:

```bash
$ mackeep-cli list
Supported applications:
[...]
 - my-files
 - nethack
[...]
```

All good, you can now sync your newly configured files:

```bash
mackeep-cli backup
```

If you override an application config that is already supported by Mackeep, your
new config for this application will replace the one provided by Mackeep.

You can find some sample configs in this directory.

### Locally test an application before submitting a Pull Request

You can add and test an application by following these steps:

- fork this project
- create a branch _(usually containing the name of the application)_
- add the appropriate application config file in the `mackeep/applications` folder
- from the top-most folder _(mackeep-cli)_ run `make develop` that replaces the
  currently installed mackeep-cli with the local modified one
- simply run `mackeep-cli backup` to test if everything is ok
- if everything works as expected:
  - run `make undevelop` to revert to the official version
  - commit and push the change to your fork and then create the Pulls Request

### Add support for an application using the XDG directory

For applications storing their configuration under the `~/.config` folder, you
should not hardcode it. The `.config` folder is the default location but it can
be named differently on other users' systems by setting the `XDG_CONFIG_HOME`
environment variable.

See <https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html>

Mackeep supports this mechanism and provides a dedicated `xdg_configuration_files`
section for those applications.

If any path starts with `.config`, remove the `.config` part and move the path
to a dedicated `xdg_configuration_files` section.

Instead of:

```ini
[application]
name = Git

[configuration_files]
.gitconfig
.config/git/config
.config/git/ignore
.config/git/attributes
```

Use this:

```ini
[application]
name = Git

[configuration_files]
.gitconfig

[xdg_configuration_files]
git/config
git/ignore
git/attributes
```

## Exclusions

Some files of an application should never be backed up: caches, lock files,
temporary files, machine specific settings... Mackeep lets you exclude them
with the `[exclude]` and `[xdg_exclude]` sections of the application config
files.

```ini
[application]
name = VS Code

[configuration_files]
Library/Application Support/Code/User

[exclude]
Library/Application Support/Code/User/workspaceStorage
Library/Application Support/Code/User/globalStorage/**
**/.DS_Store
*.log
```

The excluded files are not backed up and not restored. The excluded
directories are not even walked, so the backup is fast.

### The exclusion patterns

The patterns follow the same semantics as the ones of `.gitignore`:

- `*` matches anything but a slash, `?` matches a single character but a
  slash and `**` matches anything, slashes included.
- A pattern without any slash matches a _name_, at any depth. `*.log` matches
  every `*.log` file of the application.
- A pattern with a slash is relative to the root of the tree. A pattern
  starting with a slash is relative to the root too.
- A pattern ending with a slash only matches directories.
- A pattern starting with `!` re-includes a path that a previous pattern
  excluded. The last matching pattern wins.
- The matching is case sensitive: `.DS_Store` does not match `.ds_store`.

A pattern may also be written as a value, e.g. `*.log = the log files`.

The paths of the `[exclude]` section are relative to your home directory,
like the paths of the `[configuration_files]` section. The paths of the
`[xdg_exclude]` section are relative to `$XDG_CONFIG_HOME`, like the paths of
the `[xdg_configuration_files]` section.

```ini
[application]
name = VS Code

[xdg_configuration_files]
Code/User

[xdg_exclude]
Code/User/workspaceStorage
```

### Exclude the same files for every application

The `.mackeep.cfg` file may hold an `[exclude]` section too. It applies to
every application, which is handy to always skip the junk files:

```ini
[storage]
engine = dropbox

[exclude]
**/.DS_Store
**/Thumbs.db
```

### The link mode cannot exclude anything

A symlink cannot exclude anything: the excluded files would be synced with
the rest of the folder. So, in the link mode, an entry that contains
excluded files is skipped, with a warning:

```text
Skipping .config/Code/User, it contains excluded files and a symlink cannot exclude them
```

The files that are already in the backup and that are now excluded are not
deleted. They are only reported, e.g. with `mackeep-cli backup --dry-run`.

## JSON interface

Mackeep can write a machine-readable answer, so a graphical front-end can be
built on top of it. Use the `--json` option, before the command:

```bash
mackeep-cli --json list
```

Every answer holds a `schema_version` field, currently `1`. In this mode,
only JSON is written to `stdout`, the human-readable output is written to
`stderr` and no question is asked: the `--force-no` option is implied,
unless `--force` is given.

### `mackeep-cli --json config`

Describes the configuration of Mackeep:

```json
{
  "schema_version": 1,
  "version": "0.12.1",
  "config_file": "/home/user/.mackeep.cfg",
  "config_file_is_legacy": false,
  "custom_apps_dirs": [
    "/home/user/.mackeep",
    "/home/user/.config/mackeep/applications"
  ],
  "legacy_custom_apps_dirs": [
    "/home/user/.mackup",
    "/home/user/.config/mackup/applications"
  ],
  "storage": {
    "engine": "file_system",
    "path": "/home/user/dotfiles",
    "directory": "Mackeep",
    "resolved_backup_dir": "/home/user/dotfiles/Mackeep",
    "exists": true,
    "using_legacy_directory": false
  },
  "apps_to_sync": ["vim"],
  "apps_to_ignore": [],
  "global_exclude": ["**/.DS_Store"]
}
```

### `mackeep-cli --json list` and `mackeep-cli --json show <application>`

`list` writes an array with the description of every supported application,
`show` writes the description of a single one:

```json
{
  "schema_version": 1,
  "name": "vscode",
  "display_name": "VS Code",
  "source": "custom",
  "cfg_path": "/home/user/.mackeep/vscode.cfg",
  "files": [
    {"path": "Library/Application Support/Code/User", "exists": true, "is_dir": true}
  ],
  "xdg_files": [],
  "exclude": ["**/.DS_Store"],
  "xdg_exclude": []
}
```

The `name` is the identifier of the application, as shown by `mackeep-cli list`.
The `source` is `builtin` for the applications of Mackeep and `custom` for
the ones of the user.

### `mackeep-cli --json backup` and `mackeep-cli --json restore`

With `--dry-run`, the operations that would be done are described:

```json
{
  "schema_version": 1,
  "actions": [
    {
      "app": "vscode",
      "action": "copy",
      "src": "/home/user/Library/Application Support/Code/User",
      "dst": "/home/user/dotfiles/Mackeep/Library/Application Support/Code/User",
      "size_bytes": 4096
    }
  ],
  "summary": {
    "apps": ["vscode"],
    "actions": {"copy": 1, "skip_excluded": 2},
    "total_actions": 3,
    "total_bytes": 4096
  }
}
```

The `action` of an operation is one of `copy`, `skip_excluded`,
`skip_missing`, `conflict` or `stale_in_backup`.

### The detail levels of the dry-run

The `--detail` option tells how detailed the plan of the dry-run is:

- `entries` (the default): one entry per top level path, a folder is
  described by a single entry.
- `files`: one entry per file, so a graphical front-end can show exactly
  what is copied and what is skipped.

```bash
mackeep-cli --json backup --dry-run --detail files
```

The excluded paths tell which pattern excluded them, and the section and
the config file it comes from:

```json
{
  "schema_version": 1,
  "app": "vscode",
  "action": "skip_excluded",
  "src": "/home/user/Library/Application Support/Code/User/cache",
  "dst": "/home/user/dotfiles/Mackeep/Library/Application Support/Code/User/cache",
  "reason": {
    "pattern": "Library/Application Support/Code/User/cache",
    "section": "exclude",
    "file": "/home/user/.mackeep/vscode.cfg"
  }
}
```

An excluded directory stays a single entry, as it is not walked. A file
that already exists in the destination is reported as a `conflict`, with
the `would_overwrite` flag, and not as a `copy`.

The `--max-actions` option limits the number of actions of the plan (5000
by default). The plan is truncated when there are more actions than the
limit, and the summary is always computed on the whole plan:

```json
{
  "schema_version": 1,
  "actions": [],
  "summary": {
    "apps": ["vscode"],
    "actions": {"copy": 12000},
    "total_actions": 12000,
    "total_bytes": 4096,
    "files": 12000,
    "truncated": true,
    "limit": 5000
  }
}
```

Without `--dry-run`, the operations are streamed, one JSON document per
line, so a front-end can show the progress:

```json
{"schema_version": 1, "event": "start", "app": "vscode", "action": "backup"}
{"schema_version": 1, "event": "file", "app": "vscode", "action": "copy", "src": "...", "dst": "...", "size_bytes": 4096}
{"schema_version": 1, "event": "done", "app": "vscode", "action": "backup", "files": 1, "bytes": 4096, "skipped": 0}
```

### The errors

When something goes wrong, the exit code is not zero and the error is
written as a JSON document:

```json
{
  "schema_version": 1,
  "error": {"code": "unsupported_application", "message": "Unsupported application: nope"}
}
```

## Compatibility with Mackup

Mackeep is a fork of [Mackup](https://github.com/lra/mackup). The config
files of Mackup are still read, so nothing has to be done to keep using
them.

### The config file

The config file is looked up in the following order, the first one that
exists wins:

1. `~/.mackeep.cfg`
2. `$MACKEEP_CONFIG`
3. `$XDG_CONFIG_HOME/mackeep/mackeep.cfg`
4. `~/.mackup.cfg` (legacy)
5. `$XDG_CONFIG_HOME/mackup/mackup.cfg` (legacy)

The `--config-file` option has the priority over all of them.

### The custom applications

The custom application configs are read from:

1. `~/.mackeep/`
2. `$XDG_CONFIG_HOME/mackeep/applications/`
3. `~/.mackup/` (legacy)
4. `$XDG_CONFIG_HOME/mackup/applications/` (legacy)

An application of a Mackeep directory wins over the legacy one with the
same name. The legacy one is then ignored, without any warning.

### The storage folder

When the config file does not set a `directory`, the `Mackeep` folder of
the storage is used. The legacy `Mackup` folder is used instead when it
exists and the `Mackeep` one does not. A `directory` that is explicitly
set in the config file is never replaced.

### The warnings

When a legacy path is used, Mackeep warns about it once, in `stderr`, and
tells how to migrate.

### `mackeep-cli migrate`

The `migrate` command copies the legacy config file and the custom
application configs to their new location:

```bash
# See what would be done
mackeep-cli migrate --dry-run

# Do it
mackeep-cli migrate
```

The files are **copied**, never moved nor deleted, so the old ones stay
where they are until you remove them. The files that already exist in
their new location are never overwritten, they are skipped.

With `--json`, the plan and the result are written as JSON:

```json
{
  "schema_version": 1,
  "actions": [
    {
      "action": "copy",
      "src": "/home/user/.mackup.cfg",
      "dst": "/home/user/.mackeep.cfg"
    }
  ],
  "summary": {
    "copied": 1,
    "skipped": 0,
    "total_actions": 1,
    "dry_run": false
  }
}
```

## The desktop application

The desktop application of Mackeep is written in SwiftUI for macOS 15 and
above. It is not released yet, but it is built from the `desktop/` folder of
the repository:

```bash
cd desktop
make project   # The project of XcodeGen is generated
make build     # The application is built
make test      # The unit tests and the UI tests are run
```

The application does not keep its own copy of the configuration: it edits
`~/.mackeep.cfg` and the files of `~/.mackeep/` and it drives the terminal
version through the JSON interface. The terminal version must be installed
and found in `/opt/homebrew/bin` or `/usr/local/bin`, the path can be set in
the settings of the application.
