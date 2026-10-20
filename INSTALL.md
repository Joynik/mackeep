# Install

## With Homebrew (macOS and GNU/Linux)

```bash
# Install
brew install Joynik/tap/mackeep-cli

# Now just run it
mackeep-cli -h
```

### Upgrade

```bash
# Get the latest version
brew update
brew upgrade mackeep-cli

mackeep-cli -h
```

### Uninstall

```bash
brew uninstall mackeep-cli
```

## From the sources

If you want to work on Mackeep itself, clone the repository and use
[uv](https://docs.astral.sh/uv/):

```bash
# Clone the repository
git clone https://github.com/Joynik/mackeep.git
cd mackeep

# Install the dependencies and run it
uv run mackeep-cli -h
```

See the [development guide](doc/develop.md) for the details.
