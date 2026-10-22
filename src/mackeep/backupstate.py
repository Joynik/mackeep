"""Track backup ownership so removed definitions cannot delete shared files."""

import json
import os
from pathlib import Path
from typing import TYPE_CHECKING

from . import utils
from .config import ConfigError
from .paths import STATE_DIRECTORY, inside

if TYPE_CHECKING:
    from .transaction import Transaction


class BackupState:
    """A validated index of leaf paths owned by each backed-up application."""

    def __init__(self, root: str) -> None:
        self.root = root
        self.path = os.path.join(root, STATE_DIRECTORY, "owners.json")
        self.owners: dict[str, list[str]] = {}
        if os.path.lexists(self.path):
            if os.path.islink(self.path) or os.path.islink(os.path.dirname(self.path)):
                raise ConfigError("The backup ownership index cannot be a symlink")
            with open(self.path, encoding="utf-8") as file:
                data = json.load(file)
            if (
                not isinstance(data, dict)
                or data.get("version") != 1
                or not isinstance(data.get("owners"), dict)
            ):
                raise ConfigError("Invalid backup ownership index; refusing cleanup")
            for app, paths in data["owners"].items():
                if not isinstance(app, str) or not isinstance(paths, list):
                    raise ConfigError("Invalid backup ownership record")
                for path in paths:
                    if (
                        not isinstance(path, str)
                        or not path
                        or os.path.isabs(path)
                        or ".." in Path(path).parts
                        or path == "."
                        or os.path.normpath(path) != path
                    ):
                        raise ConfigError("Unsafe path in backup ownership index")
                    if path.split(os.sep)[0] == STATE_DIRECTORY:
                        raise ConfigError("The ownership index cannot own itself")
                self.owners[app] = paths

    def relative(self, path: str) -> str:
        """Return a safe path relative to the backup root."""
        if not inside(path, self.root):
            raise ConfigError(f"Backup path leaves storage: {path}")
        return os.path.relpath(path, self.root)

    def others(self, app: str) -> set[str]:
        """Return leaf entries owned by other applications."""
        return {
            path
            for owner, paths in self.owners.items()
            if owner != app
            for path in paths
        }

    def keep_previous(self, app: str, root: str, owned: set[str]) -> None:
        """Retain ownership when an entry was skipped or replacement declined."""
        owned.update(
            path
            for path in self.owners.get(app, [])
            if inside(os.path.join(self.root, path), root)
        )

    def preserve_shared(self, app: str, destination: str, staged: str) -> None:
        """Keep other applications' leaves during replacement of a shared tree."""
        for path in self.others(app):
            previous = os.path.join(self.root, path)
            if not inside(previous, destination) or not os.path.lexists(previous):
                continue
            suffix = os.path.relpath(previous, destination)
            target = staged if suffix == "." else os.path.join(staged, suffix)
            if not os.path.lexists(target):
                utils.copy(previous, target, preserve_link=True)

    def prune_empty_parents(self, app: str, owned: set[str]) -> None:
        """Remove obsolete empty directories after all temporary versions are gone."""
        for path in set(self.owners.get(app, [])) - owned - self.others(app):
            parent = os.path.dirname(os.path.join(self.root, path))
            while parent != self.root and inside(parent, self.root):
                try:
                    os.rmdir(parent)
                except OSError:
                    break
                parent = os.path.dirname(parent)

    def save(self, transaction: Transaction, app: str, paths: set[str]) -> None:
        """Stage the updated index in the same transaction as the data."""
        owners = dict(self.owners)
        owners[app] = sorted(paths)
        payload = json.dumps({"version": 1, "owners": owners}, indent=2) + "\n"

        def write(destination: str) -> None:
            Path(destination).write_text(payload, encoding="utf-8")
            os.chmod(destination, 0o600)

        transaction.prepare(self.path, write)
