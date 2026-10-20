# Detailed install instructions for Mackeep

There are 2 ways to run mackeep:

1. Install it with Homebrew (macOS and GNU/Linux)
2. Install it with PIP (macOS and GNU/Linux)

## Install

### With Homebrew

```bash
# Easy
brew install mackeep

# Now just run it
mackeep -h
```

### With Homebrew master branch for latest updates

Want to install the latest master release instead of waiting on the homebrew
package version?

[Homebrew reference](https://docs.brew.sh/Manpage#install-options-formulacask)

```bash
# Install master
brew install --HEAD
# Check if you are using the master or stale package
brew switch mackeep <HEAD-XXXX>

mackeep -h
```

### With Python's PIP

```bash
# Easy too
pip install mackeep

# Now you can run it
mackeep -h
```

## Upgrade

### Upgrade with Homebrew

```bash
brew update
brew upgrade
mackeep -h
```

### Upgrade with Python's PIP

```bash
pip install --upgrade mackeep
mackeep -h
```

## Uninstall

### Uninstall with Homebrew

```bash
brew uninstall mackeep
```

### Uninstall with Python's PIP

```bash
pip uninstall mackeep
```
