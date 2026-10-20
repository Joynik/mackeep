# Mackeep desktop

The native macOS application of Mackeep. It is a graphical editor of the
configuration files of Mackeep, and a front-end of the `mackeep-cli`
command line tool: it runs the backups and the restores, and it shows what
they are about to do.

The application does not store anything of its own: it edits the same files
as Mackeep (`~/.mackeep.cfg`, `~/.mackup/*.cfg`, ...) and it calls the
command line tool.

## Requirements

- macOS 15 or later
- Xcode 15 or later (built and tested with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```sh
# Generate the Xcode project and build the application
make build

# Run the tests
make test

# Run the application
make run
```

The Xcode project is generated from `project.yml`, it is not tracked.

## Structure

```text
Sources/App/
├── MackeepDesktopApp.swift   # The entry point of the application
├── AppEnvironment.swift       # The state of the application
├── Core/                      # The logic: INI files, the mackeep command, the services
├── Features/                  # The sections of the interface
└── Resources/                 # The assets and the localization
Tests/
├── Unit/                      # The unit tests
└── UI/                        # The UI tests
```
