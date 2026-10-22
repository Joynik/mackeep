# Mackeep desktop

Native SwiftUI front-end for macOS 15+ on Apple Silicon. Install with
`brew install joynik/tap/mackeep`; the CLI is installed separately. See the
[installation guide](../INSTALL.md) for CLI setup and manual disk images.

## What it controls

- **Applications:** add definitions from the built-in library and choose which
  applications to back up. Built-in definitions must be copied before editing.
- **Editor:** change a custom application's paths and exclusions, and search
  for its files in known locations or with Spotlight.
- **Backup/Restore:** preview operations and execute them through the CLI.
- **Settings:** storage, shared exclusions, external-path permission, language,
  and appearance.

Backup configuration lives in the same INI files as the CLI (`~/.mackeep.cfg`,
`~/.mackeep/*.cfg`, or the locations reported by CLI configuration). Language,
appearance, and onboarding state are desktop preferences in `UserDefaults`.

The CLI is installed separately. At launch the app searches, in order,
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `/bin`, trying
`mackeep-cli` then `mackeep` in each. It does not search the shell's arbitrary
`PATH` and currently has no executable-path picker. Settings shows the detected
path. If discovery fails, install the CLI in a supported location and reopen
the app.

The desktop and CLI share release versions and currently use JSON schema 4.
Security controls depending on new CLI fields are disabled with older tools
that do not advertise them. See the [CLI reference](../doc/README.md) for
replacement, cleanup, exclusions, and external-path behavior.

Selection saves finish before preview or execution; a failed save restores the
persisted checkboxes and prevents that operation. Editing an application does
not enable it. Restore confirmation requires a successful preview for the same
application scope. After pending selection saves finish, the app rechecks the
configuration and plan. A changed result refreshes the preview and requires
another confirmation. This is not a filesystem lock: changes to file contents,
especially with unchanged sizes, can escape a plan comparison.
External edits to an open definition require reload or explicit overwrite.

Cancellation stops previews immediately. During backup/restore it waits for the
current application to finish, then stops before the next one. This requires a
CLI advertising `supports_safe_cancellation`; older tools have no execution
cancel button. Ordinary Quit and logout wait for preparation to stop or the
running CLI to finish safely; older tools are allowed to finish without a signal.
An activity prevents idle system sleep and automatic termination during an
operation. Force Quit, forced shutdown, and power loss are not covered.
File-size estimates are calculated when an application is selected.

Dry runs, backups, and restores share an action table with an operation heading.
Execution rows come from CLI events; up to 5,000 rows are shown, with a truncation
notice and full-run totals. History can be cleared from its window without
removing backup files. History is private (`0600`); read/write errors are shown.
Before replacing damaged history, the app preserves it as `history.json.bak`
(or a distinct `.bak` file if one exists) in the same directory. The information icon explains copy mode and the CLI-only
link mode.

## Build and test

Use Xcode with a macOS SDK compatible with the sources and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Release CI currently uses the
`xcode-27` runner. From the repository root:

```bash
cd desktop
make build     # Generate the Xcode project and build Debug
make test      # Unit and UI tests
make run       # Build and open the application
```

The unit suite includes a real CLI round trip using the repository's
`.venv/bin/python`. Prepare the existing development environment with
`uv sync --locked --dev` from the repository root before running Swift tests.
This integration test uses temporary HOME/storage and never invokes an installed
Mackeep binary. CI runs the unit target separately from UI tests:

```bash
xcodebuild -project MackeepDesktop.xcodeproj -scheme MackeepDesktop \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  MACKEEP_BUNDLE_IDENTIFIER=com.joynik.mackeep.testing CODE_SIGNING_ALLOWED=NO \
  -only-testing:MackeepDesktopTests test
```

`project.yml` is the source of the generated, untracked Xcode project. Build
products live in `desktop/build/`. Signing defaults refer to the maintainer's
Apple Development identity; adjust signing for your own environment. UI tests
need suitable signing and permission to control the app.

`make test` builds a separate `com.joynik.mackeep.testing` application. The scheme
sets `MACKEEP_TESTING=1`: unit tests use injected or disabled CLI discovery and
temporary paths, while UI tests launch a fake CLI in their own temporary HOME.
UI tests terminate only their test instance. For direct `xcodebuild test`, also
set `MACKEEP_BUNDLE_IDENTIFIER=com.joynik.mackeep.testing`. Never give a test CLI
access to production definitions or backups.

For a local ad-hoc Release build:

```bash
make release XCODEBUILD_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="
```

Here `make release` only builds the desktop app. The **repository-root**
`make release` publishes a project release. See [release instructions](../doc/release.md).
`make clean` removes the generated Xcode project and build products.

## Source layout and localization

| Directory | Content |
| --- | --- |
| `Sources/App/` | `MackeepDesktopApp.swift`, `AppEnvironment.swift`, Core, Features, Resources |
| `Tests/Unit/` | Model, configuration, command, and feature tests |
| `Tests/UI/` | Application interaction tests |
| `Tools/languages/` | Translation source files |

After editing translations, run `python3 Tools/apply_translations.py` from
`desktop/` and review the generated `Localizable.xcstrings`. Keep the Python
translation sources and string catalog together in changes.
