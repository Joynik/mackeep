# Contributing

Use the [development guide](../doc/develop.md) for setup and checks and the
[architecture guide](../doc/ARCHITECTURE.md) for the code layout. Python 3.14+
is required for source development.

## Application definitions

Add or update a `.cfg` in `src/mackeep/applications/`. The filename without
`.cfg` is the application's CLI identifier; `mackeep-cli list` is the catalog,
so there is no separate application list to update in the README.

- Keep an application-definition PR focused on one application.
- Select the smallest portable set of settings; omit caches, sessions, large
  application data, machine-specific state, and secrets.
- Use `[xdg_configuration_files]` for paths under `$XDG_CONFIG_HOME` instead of
  hardcoding `.config`.
- Paths are relative to HOME or XDG. Do not rely on external-path permission
  for built-in definitions.
- Add exclusions when a selected directory also holds disposable files.
- Test with a disposable HOME, including a dry-run, backup, and restore.

See the [configuration format](../doc/README.md#custom-applications).

## Code and documentation

Keep runtime dependencies limited to the standard library and `docopt-ng`.
Use English for code and documentation, type annotations, and Google-style
docstrings. Follow the existing style rather than introducing unrelated
formatting changes.

For a bug, add a reproducing test before fixing it. Preserve public CLI options
and JSON field names; a breaking JSON change needs a schema version bump,
documentation, and a matching desktop update.

Before submitting, run `make check`, explain the resulting behavior and relevant
validation, and update documentation for changed features. Do not include real
credentials, user configuration, backup data, or generated build artifacts.
