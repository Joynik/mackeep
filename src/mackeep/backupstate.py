"""Track backup ownership so removed definitions cannot delete shared files."""

import json
import os
import stat
from pathlib import Path
from typing import TYPE_CHECKING

from . import utils
from .config import ConfigError
from .paths import STATE_DIRECTORY, inside

PERMISSION_BITS = 0o777

if TYPE_CHECKING:
    from .transaction import Transaction


class BackupState:
    """A validated index of leaf paths owned by each backed-up application."""

    def __init__(self, root: str) -> None:
        self.root = root
        self.path = os.path.join(root, STATE_DIRECTORY, "owners.json")
        self.owners: dict[str, list[str]] = {}
        self.modes: dict[str, int] = {}
        if os.path.lexists(self.path):
            if os.path.islink(self.path) or os.path.islink(os.path.dirname(self.path)):
                raise ConfigError("The backup ownership index cannot be a symlink")
            try:
                with open(self.path, encoding="utf-8") as file:
                    data = json.load(file)
            except (ValueError, UnicodeError) as exc:
                raise ConfigError(
                    f"Invalid backup ownership index at {self.path}; "
                    "restore a valid index before retrying",
                ) from exc
            if (
                not isinstance(data, dict)
                or data.get("version") != 1
                or not isinstance(data.get("owners"), dict)
            ):
                raise ConfigError("Invalid backup ownership index; refusing cleanup")
            modes = data.get("modes", {})
            if not isinstance(modes, dict) or any(
                not isinstance(path, str)
                or not path
                or os.path.isabs(path)
                or ".." in Path(path).parts
                or path == "."
                or os.path.normpath(path) != path
                or path.split(os.sep)[0] == STATE_DIRECTORY
                or type(mode) is not int
                or not 0 <= mode <= PERMISSION_BITS
                for path, mode in modes.items()
            ):
                raise ConfigError("Invalid permissions in backup ownership index")
            self.modes = modes
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
        leaves = {path for entries in owners.values() for path in entries}
        retained = set(leaves)
        for leaf in leaves:
            retained.update(str(parent) for parent in Path(leaf).parents)
        modes = {path: mode for path, mode in self.modes.items() if path in retained}
        payload = (
            json.dumps({"version": 1, "owners": owners, "modes": modes}, indent=2)
            + "\n"
        )

        def write(destination: str) -> None:
            Path(destination).write_text(payload, encoding="utf-8")
            os.chmod(destination, 0o600)

        transaction.prepare(self.path, write)

    def record_modes(self, source: str, staged: str, destination: str) -> None:
        """Record source permissions only for entries actually copied into staging."""
        paths = [staged]
        if os.path.isdir(staged) and not os.path.islink(staged):
            for parent, directories, files in os.walk(staged):
                paths.extend(os.path.join(parent, name) for name in directories + files)
        for path in paths:
            suffix = os.path.relpath(path, staged)
            original = source if suffix == "." else os.path.join(source, suffix)
            target = destination if suffix == "." else os.path.join(destination, suffix)
            if not os.path.islink(path) and os.path.exists(original):
                self.modes[self.relative(target)] = (
                    stat.S_IMODE(os.stat(original).st_mode) & 0o777
                )
