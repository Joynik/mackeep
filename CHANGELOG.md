# Changelog

## Unreleased

## 0.26.2 — 2026-11-18

### Fixed

- Use project names for backup folders instead of UUIDs.

## 0.26.1 — 2026-11-18

### Fixed

- Match the Projects list and editor layout to Applications, including toolbar placement and the
  settings toggle size.

## 0.26.0 — 2026-11-18

### Added

- Optional Projects tab with independent definitions, root-relative files and exclusions, and
  separate project backup storage. Projects can be created, copied, renamed, disabled, and deleted
  without changing application definitions. Disabling projects retains their settings and backups.

### Fixed

- Include gmailctl configuration and credentials stored under XDG_CONFIG_HOME in backups.
- Explain Full Disk Access requirements when macOS blocks a file operation.
- Report CLI failures clearly when diagnostic output is not valid UTF-8.
