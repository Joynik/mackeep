"""Stage replacements on the destination filesystem and roll back failed commits."""

import os
import shutil
import tempfile
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable


@dataclass
class Replacement:
    """A staged file or directory and its temporary previous version."""

    destination: str
    workspace: str
    staged: str | None
    installed: bool = False
    moved_previous: bool = False

    @property
    def previous(self) -> str:
        """Return the location of the previous destination."""
        return os.path.join(self.workspace, "previous")


class Transaction:
    """Prepare all writes before changing any existing destination."""

    def __init__(self) -> None:
        self.replacements: list[Replacement] = []
        self.keep_workspaces = False

    def prepare(self, destination: str, build: Callable[[str], None] | None) -> None:
        """Stage a replacement, or schedule removal with rollback."""
        parent = os.path.dirname(destination)
        os.makedirs(parent, mode=0o700, exist_ok=True)
        workspace = tempfile.mkdtemp(prefix=".mackeep-", dir=parent)
        staged = os.path.join(workspace, "new") if build is not None else None
        replacement = Replacement(destination, workspace, staged)
        self.replacements.append(replacement)
        if build is not None and staged is not None:
            build(staged)

    def commit(self) -> None:
        """Install staged values, restoring previous values on failure."""
        try:
            for item in self.replacements:
                if os.path.lexists(item.destination):
                    os.replace(item.destination, item.previous)
                    item.moved_previous = True
                if item.staged is not None:
                    os.replace(item.staged, item.destination)
                    item.installed = True
        except BaseException:
            try:
                for item in reversed(self.replacements):
                    if item.installed:
                        os.replace(
                            item.destination, os.path.join(item.workspace, "failed"),
                        )
                    if item.moved_previous:
                        os.replace(item.previous, item.destination)
            except BaseException as rollback_error:
                self.keep_workspaces = True
                locations = ", ".join(item.workspace for item in self.replacements)
                raise OSError(
                    f"Rollback failed; previous data retained in {locations}",
                ) from rollback_error
            raise

    def close(self) -> None:
        """Remove temporary versions only after successful rollback or commit."""
        if not self.keep_workspaces:
            for item in self.replacements:
                shutil.rmtree(item.workspace)
