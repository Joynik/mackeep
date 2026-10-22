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

Config files are searched in the following order. If none is found, Mackeep
creates the default config location of `~/.mackeep.cfg`:

- `~/.mackeep.cfg`
- `$MACKEEP_CONFIG`
- `$XDG_CONFIG_HOME/mackeep/mackeep.cfg` or `~/.config/mackeep/mackeep.cfg`

The config file of Mackup is not used, the legacy file of Mackup can be
copied with [mackeep-cli migrate](#mackeep-cli-migrate).

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

When the section is there, only the applications of it are backed up, even
when it is empty. Without the section, every application of the database is
backed up.

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

### The broken rules

A rule that cannot be used, e.g. an absolute path in an `[exclude]` section,
is skipped: the other rules of the file are still used and the rest of
Mackeep keeps working. The problem is reported, with the name of the file it
is in:

```text
Warning: Invalid exclusion pattern in /home/user/.mackeep/vscode.cfg: unsupported absolute path: /home/user/foo
```

The warnings are written to `stderr`, so the other output is not disturbed.
In the JSON answers, the problems of the config file of an application are in
its `error` field, and the problems of the `.mackeep.cfg` file are in the
`errors` field of the configuration.

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

Every answer holds a `schema_version` field, currently `3`. In this mode,
only JSON is written to `stdout`, the human-readable output is written to
`stderr` and no question is asked: the `--force-no` option is implied,
unless `--force` is given.

The version `2` of the schema removed the fields about the legacy paths of
Mackup, they are not used any more: `config_file_is_legacy`,
`legacy_custom_apps_dirs` and `storage.using_legacy_directory` are gone. The
field `custom_apps_dir` was added, it is the main directory of the custom
applications.

The version `3` of the schema added the field `error` to the applications
and the field `errors` to the configuration. They tell what is not used of
the config files, see [the broken rules](#the-broken-rules).

### `mackeep-cli --json config`

Describes the configuration of Mackeep:

```json
{
  "schema_version": 3,
  "version": "0.12.1",
  "config_file": "/home/user/.mackeep.cfg",
  "custom_apps_dir": "/home/user/.mackeep",
  "custom_apps_dirs": [
    "/home/user/.mackeep",
    "/home/user/.config/mackeep/applications"
  ],
  "storage": {
    "engine": "file_system",
    "path": "/home/user/dotfiles",
    "directory": "Mackeep",
    "resolved_backup_dir": "/home/user/dotfiles/Mackeep",
    "exists": true
  },
  "apps_to_sync": ["vim"],
  "apps_to_ignore": [],
  "global_exclude": ["**/.DS_Store"],
  "errors": []
}
```

### `mackeep-cli --json list` and `mackeep-cli --json show <application>`

`list` writes an array with the description of every supported application,
`show` writes the description of a single one:

```json
{
  "schema_version": 3,
  "name": "vscode",
  "display_name": "VS Code",
  "source": "custom",
  "cfg_path": "/home/user/.mackeep/vscode.cfg",
  "files": [
    {
      "path": "Library/Application Support/Code/User",
      "exists": true,
      "is_dir": true,
      "sensitive": false,
      "sensitive_reason": null
    }
  ],
  "xdg_files": [],
  "exclude": ["**/.DS_Store"],
  "xdg_exclude": [],
  "error": null
}
```

The `name` is the identifier of the application, as shown by `mackeep-cli list`.
The `source` is `builtin` for the applications of Mackeep and `custom` for
the ones of the user.

The `sensitive` tells if the path holds secrets, the `sensitive_reason` says
why. See [the sensitive files](#the-sensitive-files).

The `error` tells why the config file of the application is not used
entirely, it is `null` when there is no problem. See
[the broken rules](#the-broken-rules).

### `mackeep-cli --json backup` and `mackeep-cli --json restore`

With `--dry-run`, the operations that would be done are described:

```json
{
  "schema_version": 3,
  "actions": [
    {
      "app": "vscode",
      "action": "copy",
      "src": "/home/user/Library/Application Support/Code/User",
      "dst": "/home/user/dotfiles/Mackeep/Library/Application Support/Code/User",
      "size_bytes": 4096,
      "sensitive": false,
      "sensitive_reason": null
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

Every operation has a `sensitive` field and a `sensitive_reason` field, they
tell if the file holds secrets. See [the sensitive files](#the-sensitive-files).

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
  "schema_version": 3,
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
  "schema_version": 3,
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
{"schema_version": 3, "event": "start", "app": "vscode", "action": "backup"}
{"schema_version": 3, "event": "file", "app": "vscode", "action": "copy", "src": "...", "dst": "...", "size_bytes": 4096}
{"schema_version": 3, "event": "done", "app": "vscode", "action": "backup", "files": 1, "bytes": 4096, "skipped": 0}
```

### The errors

When something goes wrong, the exit code is not zero and the error is
written as a JSON document:

```json
{
  "schema_version": 3,
  "error": {"code": "unsupported_application", "message": "Unsupported application: nope"}
}
```

## Compatibility with Mackup

Mackeep is a fork of [Mackup](https://github.com/lra/mackup). The files of
Mackup are not used, but they can be copied to their new location with
`mackeep-cli migrate`.

### The config file

The config file of Mackup is not used. When there is no `~/.mackeep.cfg`,
Mackeep creates one with the default backup folder:

```ini
[storage]
directory = Mackeep
```

The `mackeep-cli migrate` command copies the config file of Mackup to
`~/.mackeep.cfg`.

### The custom applications

The custom application configs are read from:

1. `~/.mackeep/`
2. `$XDG_CONFIG_HOME/mackeep/applications/`

The legacy directories of Mackup are not read any more. The custom
applications they hold are ignored, and Mackeep warns about them once, so
they can be migrated with `mackeep-cli migrate`.

An application of the first directory wins over the one of the second, when
they have the same name.

### The storage folder

When the config file does not set a `directory`, the `Mackeep` folder of
the storage is used. A `directory` that is explicitly set in the config file
is never replaced.

The legacy `Mackup` folder is not used any more. When the backup of Mackup
is still there, the `mackeep-cli migrate` command writes its name in the new
config file, so the backup stays in the same place.

### The warnings

When a legacy path is found, Mackeep warns about it once, in `stderr`, and
tells how to migrate. The `stdout` stays clean, so the output of `--json`
can be piped.

A legacy custom application config is only warned about when it has to be
migrated: a file that is shadowed by a new one with the same name is not
used at all, and a file that is the same as the default config of the
application does not have to be copied.

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

When the storage folder of Mackup is used, the name of that folder is
written in the new config file:

```ini
[storage]
directory = Mackup
```

Without it, the backup would move to a new folder and the files of the old
one would look like they were lost. A config file that already has a
`directory` option is never changed.

With `--json`, the plan and the result are written as JSON:

```json
{
  "schema_version": 3,
  "actions": [
    {
      "action": "copy",
      "src": "/home/user/.mackup.cfg",
      "dst": "/home/user/.mackeep.cfg"
    },
    {
      "action": "set_directory",
      "src": "/home/user/.mackup.cfg",
      "dst": "/home/user/.mackeep.cfg",
      "directory": "Mackup"
    }
  ],
  "summary": {
    "copied": 1,
    "skipped": 0,
    "updated": 1,
    "total_actions": 2,
    "dry_run": false
  }
}
```

## The sensitive files

Some of the files of Mackeep hold secrets: the private keys of SSH, the
keys of GnuPG, the credentials of AWS, the keychain of macOS... They are
copied in plain text to the backup, like every other file.

Mackeep knows a list of such paths and tells about them:

- in the JSON interface, every file has a `sensitive` field and a
  `sensitive_reason` field, see [`--json list`](#mackeep-cli---json-list-and-mackeep-cli---json-show-application)
  and the [dry-run](#mackeep-cli---json-backup-and-mackeep-cli---json-restore);
- in the human-readable output, the backup warns about them once.

The list of the paths is in `SENSITIVE_PATTERNS`, in
`src/mackeep/constants.py`. The paths are relative to the home directory
(or to the XDG config home), the keys are the patterns and the values are
the reason why the path is sensitive.

The public keys (`.pub`) are not secrets, they are never marked.

## The desktop application

The desktop application of Mackeep is written in SwiftUI for macOS 15 and
above. It is not released yet, but it is built from the `desktop/` folder of
the repository:

```bash
cd desktop
make project   # The project of XcodeGen is generated
make build     # The application is built
make release   # The application is built for the release
make test      # The unit tests and the UI tests are run
```

The application does not keep its own copy of the configuration: it edits
`~/.mackeep.cfg` and the files of `~/.mackeep/` and it drives the terminal
version through the JSON interface. The terminal version must be installed
and found in `/opt/homebrew/bin` or `/usr/local/bin`, the path can be set in
the settings of the application.
