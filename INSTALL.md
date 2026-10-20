# Install

## With Homebrew (macOS and GNU/Linux)

```bash
# Install
brew install Joynik/tap/mackeep

# Now just run it
mackeep -h
```

### Upgrade

```bash
# Get the latest version
brew update
brew upgrade mackeep

mackeep -h
```

### Uninstall

```bash
brew uninstall mackeep
```

## From the sources

If you want to work on Mackeep itself, clone the repository and use
[uv](https://docs.astral.sh/uv/):

```bash
# Clone the repository
git clone https://github.com/Joynik/mackeep.git
cd mackeep

# Install the dependencies and run it
uv run mackeep -h
```

See the [development guide](doc/develop.md) for the details.
