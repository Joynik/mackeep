# Mackeep desktop

Native SwiftUI front-end for macOS 15+ on Apple Silicon. Install the release
image and CLI using the [installation guide](../INSTALL.md).

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

`project.yml` is the source of the generated, untracked Xcode project. Build
products live in `desktop/build/`. Signing defaults refer to the maintainer's
Apple Development identity; adjust signing for your own environment. UI tests
need suitable signing and permission to control the app.

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
