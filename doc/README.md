# Configuration and CLI reference

Start with the [quickstart](../README.md#quickstart) or
[installation guide](../INSTALL.md). This page describes the files and behavior
shared by the CLI and desktop application.

## Configuration file location

`--config-file` selects an existing file explicitly; relative paths are relative
to HOME. The config must be inside HOME. Without that option, the first existing
file in this order wins:

1. `~/.mackeep.cfg`
2. `$MACKEEP_CONFIG`
3. `$XDG_CONFIG_HOME/mackeep/mackeep.cfg` (default `~/.config/mackeep/mackeep.cfg`)

An ordinary first run creates `~/.mackeep.cfg` and `~/.mackeep/`. The new config
uses `engine = unconfigured`; backup storage waits for the user to choose it.
Backup and restore with `--dry-run` do not create configuration, data, or
ownership records. `config` reports the active config path and resolved storage.

See the [sample config](.mackeep.cfg). Config paths containing spaces do not
need shell escaping or quotes inside the INI file.

## Storage

The storage engine determines the base folder. `directory`, default `Mackeep`,
is appended to it. The base folder must exist before backup; Mackeep asks to
create its backup subdirectory when needed.

| Engine | Base folder |
| --- | --- |
| `unconfigured` | No storage selected; backup/restore cannot run |
| `file_system` | Explicit `path`, absolute or relative to HOME |
| `dropbox` | Detected from the local Dropbox configuration |
| `google_drive` | Detected from the supported local Google Drive database |
| `icloud` | `~/Library/Mobile Documents/com~apple~CloudDocs` |

```ini
[storage]
engine = file_system
path = dotfiles
directory = Mackeep
```

This stores backups under `~/dotfiles/Mackeep`. The file-system `path` option
is required; an empty value is unconfigured, not HOME. Older configs without
an engine retain the implicit Dropbox behavior. Provider detection depends on
the local client layout; use `file_system` when detection cannot find the
folder. Mackeep copies files locally; the storage provider handles remote sync.

### Switching storage

For copy mode, wait for active operations to finish, copy the entire backup
folder (including `.mackeep-state`) to the new storage, and update `[storage]`
on each machine. Preview the next operation before running it. Keep the old
folder until you verify the new one. Restore only when you want to replace
local settings with the stored version.

For legacy link mode, first run `mackeep-cli link uninstall` on each machine
while the old storage is accessible. Change storage, then use copy mode or
explicitly reinstall links. Changing the config alone does not retarget links.

## Applications

Use identifiers from `mackeep-cli list`, not display names:

```ini
[applications_to_sync]
git
vim

[applications_to_ignore]
vim
```

- An absent `[applications_to_sync]` means all supported applications.
- A present but empty section means none.
- Ignored applications are removed from the selection.
- Naming an application, such as `mackeep-cli backup vim`, overrides both lists
  for that command. An unsupported name fails before backup data is changed.
- Disabling an application does not delete its existing backup.

### Custom applications

Create `~/.mackeep/my-editor.cfg`:

```ini
[application]
name = My editor

[configuration_files]
.my-editorrc

[xdg_configuration_files]
my-editor

[xdg_exclude]
my-editor/cache/
```

`my-editor` becomes the CLI identifier. `[configuration_files]` paths are
relative to HOME; `[xdg_configuration_files]` paths are relative to
`$XDG_CONFIG_HOME`, default `~/.config`. Prefer XDG entries to hardcoded `.config`.
Directories are recursive; shell glob expansion is not applied to file entries.

Definition precedence for a matching filename is:

1. `~/.mackeep/`
2. `$XDG_CONFIG_HOME/mackeep/applications/`
3. Built-in `src/mackeep/applications/`

A custom definition replaces the built-in file entirely; it is not merged.
Inspect it with `mackeep-cli show my-editor`, then preview
`mackeep-cli --dry-run backup my-editor`. Examples are in [.mackeep/](.mackeep/).

## Exclusions

Use `[exclude]` for HOME-relative patterns and `[xdg_exclude]` for XDG-relative
patterns. Both sections work globally in `.mackeep.cfg` and per application;
global rules precede application rules within each matcher.

```ini
[exclude]
**/.DS_Store
*.log

[xdg_exclude]
my-editor/cache/
```

| Pattern feature | Meaning |
| --- | --- |
| `*` | Any characters except `/` |
| `?` | One character except `/` |
| `**` | Any characters, including `/` |
| No slash, such as `*.log` | Match a name at any depth |
| A slash, such as `my-editor/cache` | Match relative to the section's root |
| Trailing `/` | Match directories only |
| Leading `!` | Re-include a path excluded by an earlier rule |

Matching is case-sensitive. The last matching rule within a matcher wins.
An excluded parent directory is not walked: re-include the directory before
trying to re-include its children. A HOME exclusion still excludes a path even
if an XDG rule would re-include it. Leading absolute-path patterns are rejected
by the config loader. Do not assume all Git pattern features are supported.

Patterns normally appear as bare lines. If an INI entry has a value, that value
is the pattern: `cache_rule = my-editor/cache/`. Text after `=` is not a
comment describing the pattern.

Backup omits excluded files and cleans their previous tracked backup entries
after successful replacement. Restore preserves excluded local files.
Link mode skips entries containing excluded files because a link cannot filter
the contents of its target.

Malformed definitions and duplicate or unsupported rules produce warnings in
`stderr`. Other usable rules can still be loaded; invalid application paths
block an operation selecting that application. JSON exposes application
problems in `error` and main-config problems in `errors`.

## External paths

By default, absolute application entries, parent traversal (`..`), and sources
resolving outside HOME are rejected. To explicitly allow them:

```ini
[security]
allow_external_paths = true
```

Desktop exposes the same setting under Security. It is unavailable when an
older CLI does not advertise the capability. It does not grant OS permissions
or bypass source/destination overlap checks.

Paths outside HOME map into
`.mackeep-external/<absolute-path-without-leading-slash>` inside storage.
Restore uses the absolute local path from the active definition; verify it on
each machine. External XDG roots require this permission, too. Their exclusion
patterns remain relative to XDG. `.mackeep-external` and `.mackeep-state` are
reserved backup namespaces.

## Backup and restore behavior

Copy mode prepares fresh replacements beside the destinations before replacing
existing data. A preparation failure leaves previous destinations intact. A
commit failure attempts to roll back changes for that application. Ordinary
I/O failures allow other applications to run, but the command exits nonzero
when any application fails. Backup is not incremental: selected entries are
copied again even if their contents have not changed.

Existing destinations require confirmation. `--force` accepts replacements;
`--force-no` declines them. Declining preserves the old data and ownership.
Both options together are invalid. CLI rejects superuser execution unless
`--root` is explicitly provided.

### Cleanup and ownership

Ownership is recorded in `.mackeep-state/owners.json` inside the backup. Data
and the index are updated in the same application transaction. A successful
backup removes that application's previously tracked leaves that are now
excluded or no longer listed. Another application's owned leaves are retained
when a shared directory is replaced. A still-listed but missing top-level
source is skipped and its previous backup retained.

An old backup without an index is initialized from currently listed definitions,
including configured ignored applications. Paths removed before ownership was
recorded cannot be identified automatically. Files outside replaced paths are
not guessed to belong to an application. Inspect old backups manually when
upgrading. Keep the ownership index with the data and do not edit it by hand;
a malformed index refuses cleanup.

### Links, metadata, and limits

Nested symlinks are copied as links, including dangling and cyclic links;
their targets are not traversed. Explicit top-level symlinks copy their target
when allowed by path policy. Backup skips a link already installed by legacy
link mode. Restoring an absolute symlink does not rewrite its target for a new
machine.

Copies retain timestamps and owner execution: ordinary files use `0600`,
owner-executable files use `0700`, and directories use `0700`. This does not
promise preservation of every ACL or extended attribute across filesystems.

Only one writer to a storage folder is supported. Transactions are per
application, not for the entire command, and are not a power-loss recovery
journal. If rollback fails, temporary previous versions are kept and the error
reports their locations. Successful replacement removes the rollback copy;
there is no version history. Leave enough free space for old and staged data.

### Legacy link mode

| Command | Behavior |
| --- | --- |
| `link install [application]` | Back up local data and replace it with links to storage |
| `link [application]` | Create local links to existing stored data |
| `link uninstall [application]` | Restore copies in place of installed links; keep storage |

Use copy mode for macOS 14+ because symlinked application preferences can fail.
An application-specific uninstall skips the global uninstall confirmation and
acts only on that application's installed links.

## Compatibility with Mackup

Mackup's `.mackup.cfg` and `.mackup/` definitions are not read automatically.
Preview migration before creating a fresh Mackeep config if you intend to
preserve the old configuration:

```bash
mackeep-cli migrate --dry-run
mackeep-cli migrate
```

Migration copies the first legacy main config found and legacy custom configs
to their Mackeep locations. It never deletes the originals or overwrites an
existing destination. If the detected old storage uses `Mackup` and no directory
is explicitly set, migration writes `directory = Mackup` into the new copy to
keep that storage location. Review the result before backup or restore.

Migration preview does not copy legacy files. Reading a legacy storage config
can still initialize `~/.mackeep/`; it is not the same read-only initialization
path as backup/restore dry-run.

## Sensitive files

Backups are unencrypted. Known sensitive HOME/XDG paths are marked by
`sensitive` and `sensitive_reason` in JSON; text output warns once when copying
a known sensitive file. Public-key `.pub` files are not marked. Detection is
advisory and does not discover arbitrary secrets inside file contents.

Review the selected paths and storage permissions. See the
[private-key example](syncing-private-keys.md) before overriding key definitions.

## JSON interface

`--json` is supported for `config`, `list`, `show`, `backup`, `restore`, and
`migrate`. Stdout contains JSON only; diagnostics go to stderr. No prompts are
asked. `--force-no` is implied unless `--force` is supplied. Check both JSON
errors and process exit status.

### Schema and configuration

Current `schema_version` is **4**. Consumers must handle unsupported schema
versions rather than assume deletion semantics from an older response.

```bash
mackeep-cli --json config
```

```json
{
  "schema_version": 4,
  "version": "0.22.1",
  "config_file": "/home/user/.mackeep.cfg",
  "custom_apps_dir": "/home/user/.mackeep",
  "custom_apps_dirs": ["/home/user/.mackeep", "/home/user/.config/mackeep/applications"],
  "errors": [],
  "storage": {
    "engine": "file_system",
    "path": "/home/user/storage",
    "directory": "Mackeep",
    "resolved_backup_dir": "/home/user/storage/Mackeep",
    "exists": true
  },
  "apps_to_sync": ["vim"],
  "apps_to_ignore": [],
  "allow_external_paths": false,
  "storage_configured": true,
  "global_exclude": [],
  "global_xdg_exclude": []
}
```

`storage_configured` means a nonempty storage path was resolved, not that the
folder exists or is writable. Check `storage.exists` for the backup directory.
New configurations use `unconfigured` with an empty resolved backup path.

### Application descriptions

`--json list` returns an array; `--json show vim` returns one object:

```json
{
  "schema_version": 4,
  "name": "vim",
  "display_name": "Vim",
  "source": "builtin",
  "cfg_path": "/path/to/mackeep/applications/vim.cfg",
  "files": [
    {"path": ".vimrc", "exists": true, "is_dir": false, "sensitive": false, "sensitive_reason": null}
  ],
  "xdg_files": [],
  "exclude": [],
  "xdg_exclude": [],
  "error": null
}
```

The example is shortened; actual definitions may select more paths.
`source` is `builtin` or `custom`; `files` is HOME-relative, `xdg_files` is
XDG-relative unless external entries are explicitly enabled. `error` is null
when the definition has no reported problems.

### Dry-run plans

```bash
mackeep-cli --json --dry-run backup vim --detail files --max-actions 5000
```

`--detail entries` (default) summarizes each top-level entry; `files` describes
individual files. Excluded directories remain a single action and are not
walked.

```json
{
  "schema_version": 4,
  "actions": [
    {"app": "vim", "action": "copy", "src": "/home/user/.vimrc", "dst": "/home/user/storage/Mackeep/.vimrc", "size_bytes": 128, "sensitive": false, "sensitive_reason": null}
  ],
  "summary": {
    "apps": ["vim"],
    "actions": {"copy": 1},
    "total_actions": 1,
    "total_bytes": 128,
    "files": 1
  }
}
```

| Action | Meaning |
| --- | --- |
| `copy` | Planned copy |
| `conflict` | Destination exists or replacement was declined |
| `skip_missing` | Source is missing |
| `skip_excluded` | Exclusion prevented copying |
| `stale_in_backup` | Stale backup data; `will_remove: true` marks planned cleanup |
| `error` | Application operation failed |

Detailed exclusion actions can include `reason` with `pattern`, `section`, and
`file`. In file detail, an existing destination is a `conflict` with
`would_overwrite: true` instead of `copy`. Entry detail may report a copy and a
conflict for the same entry; its bytes contribute once to the summary.
`summary.files` counts copy actions, not all files in the filesystem.

`--max-actions` is a positive retained-action limit, default 5000. If exceeded,
`summary` adds `truncated: true` and `limit`. Totals cover all visited actions;
the limit does not stop traversal or bound all memory used by planning.
Dry-run does not predict what a later interactive confirmation will accept.

### Execution events and errors

Without `--dry-run`, backup and restore emit NDJSON, one object per line:

```json
{"schema_version": 4, "event": "start", "app": "vim", "action": "backup"}
{"schema_version": 4, "event": "file", "app": "vim", "action": "copy", "src": "/home/user/.vimrc", "dst": "/home/user/storage/Mackeep/.vimrc", "size_bytes": 128, "sensitive": false, "sensitive_reason": null}
{"schema_version": 4, "event": "done", "app": "vim", "action": "backup", "files": 1, "bytes": 128, "skipped": 0}
```

Committed file events are emitted after the application's transaction commits,
not as a byte-by-byte transfer stream. `done` counters are per application;
consumers sum them for a run. `done` alone does not prove success: a failed
application can emit an error event and then `done`, followed by a final error
document and a nonzero process exit.

```json
{"schema_version": 4, "error": {"code": "unsupported_application", "message": "Unsupported application: unknown-app"}}
```

Error codes include `unsupported_application`, `config_error`, and `error`.
Unexpected exceptions also produce a traceback in stderr.

`--json migrate` returns a single object with `schema_version`, `actions`, and
`summary`. Actions are `copy`, `skip`, or `set_directory`, with `src` and `dst`
(and `directory` for the latter). Summary fields are `copied`, `skipped`,
`updated`, `total_actions`, and `dry_run`; counts in a preview describe the
plan, while `copied` remains zero.

### Schema changes

- **4:** Adds `allow_external_paths` and `storage_configured`; permits
  `unconfigured` storage; `stale_in_backup` can now mean deletion when
  `will_remove: true`. Clients must check the flag before presenting removal.
- **3:** Adds application `error` and configuration `errors`.
- **2:** Removes `config_file_is_legacy`, `legacy_custom_apps_dirs`, and
  `storage.using_legacy_directory`; adds `custom_apps_dir`.
