"""Stage replacements on the destination filesystem and roll back failed commits."""

import os
import shutil
import stat
import sys
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
    previous_mode: int | None = None
    staged_mode: int | None = None

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
            replacement.staged_mode = _make_movable(staged)

    def commit(self) -> None:
        """Install staged values, restoring previous values on failure."""
        try:
            for item in self.replacements:
                if os.path.lexists(item.destination):
                    item.previous_mode = _make_movable(item.destination)
                    os.replace(item.destination, item.previous)
                    item.moved_previous = True
                    if item.previous_mode is not None:
                        os.chmod(item.previous, item.previous_mode)
                if item.staged is not None:
                    os.replace(item.staged, item.destination)
                    item.installed = True
                    if item.staged_mode is not None:
                        os.chmod(item.destination, item.staged_mode)
        except BaseException:
            try:
                for item in reversed(self.replacements):
                    if item.installed:
                        _make_movable(item.destination)
                        os.replace(
                            item.destination,
                            os.path.join(item.workspace, "failed"),
                        )
                    if item.moved_previous:
                        _make_movable(item.previous)
                        os.replace(item.previous, item.destination)
                    if item.previous_mode is not None:
                        os.chmod(item.destination, item.previous_mode)
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
                try:
                    shutil.rmtree(item.workspace, onexc=_retry_cleanup)
                except OSError as exc:
                    print(
                        "Warning: Unable to remove temporary data after the operation: "
                        f"{item.workspace}: {exc}",
                        file=sys.stderr,
                    )


def _retry_cleanup(
    function: Callable[..., object], path: str, error: BaseException,
) -> None:
    """Retry cleanup of read-only directories without following symbolic links."""
    if not isinstance(error, PermissionError) or os.path.islink(path):
        raise error
    parent = os.path.dirname(path)
    if not os.path.islink(parent):
        os.chmod(parent, os.stat(parent).st_mode | stat.S_IRWXU)
    if os.path.isdir(path):
        os.chmod(path, os.stat(path).st_mode | stat.S_IRWXU)
    function(path)


def _make_movable(path: str) -> int | None:
    """Temporarily allow renaming read-only directories on macOS."""
    if os.path.islink(path) or not os.path.isdir(path):
        return None
    mode = stat.S_IMODE(os.stat(path).st_mode)
    if mode & stat.S_IWUSR:
        return None
    os.chmod(path, mode | stat.S_IWUSR)
    return mode
