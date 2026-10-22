"""Resolve application entries without allowing backup paths to escape storage."""

import os
from pathlib import Path

from .config import ConfigError

EXTERNAL_DIRECTORY = ".mackeep-external"
STATE_DIRECTORY = ".mackeep-state"


def inside(path: str, root: str) -> bool:
    """Return whether a normalized path is within a root."""
    root = os.path.abspath(root)
    return os.path.commonpath(
        (os.path.abspath(path), root),
    ) == root


def entry_paths(
    entry: str, backup: str, *, allow_external: bool = False,
) -> tuple[str, str]:
    """Map a local entry to a contained backup path.

    Args:
        entry: A HOME-relative or explicitly enabled external path.
        backup: The backup root.
        allow_external: Whether external sources are allowed.

    Returns:
        The absolute local path and backup path.
    """
    home = os.path.expanduser("~")
    local = os.path.abspath(os.path.join(home, entry))
    external = os.path.isabs(entry) or ".." in Path(entry).parts
    if external and not allow_external:
        raise ConfigError(f"External paths are disabled: {entry}")
    if inside(local, home):
        relative = os.path.relpath(local, home)
        if relative.split(os.sep)[0] in {EXTERNAL_DIRECTORY, STATE_DIRECTORY}:
            raise ConfigError(f"Reserved backup path: {entry}")
    else:
        if not allow_external:
            raise ConfigError(f"External paths are disabled: {entry}")
        relative = os.path.join(EXTERNAL_DIRECTORY, local.lstrip(os.sep))
    return local, os.path.join(backup, relative)


def validate_pair(source: str, destination: str) -> None:
    """Reject overlapping paths, hard links, and unsafe destination parents."""
    source = os.path.realpath(source)
    destination = os.path.realpath(destination)
    if inside(source, destination) or inside(destination, source):
        raise ConfigError(f"Source and destination overlap: {source} and {destination}")
    if (
        os.path.exists(source)
        and os.path.exists(destination)
        and os.path.samefile(source, destination)
    ):
        raise ConfigError(f"Source and destination are the same file: {source}")
