"""Serialize local writes to one storage without creating cloud lock files."""

import fcntl
import hashlib
import os
import stat
from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator

from .config import ConfigError


@contextmanager
def storage_lock(root: str) -> Generator[None]:
    """Reject concurrent operations by this user on the same resolved storage."""
    directory = Path.home() / ".local/state/mackeep/locks"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    identity = hashlib.sha256(os.fsencode(os.path.realpath(root))).hexdigest()
    descriptor = os.open(
        directory / identity, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600,
    )
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise ConfigError("Unsafe local storage lock file")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ConfigError(
                f"Another Mackeep operation is using {root}; wait for it to finish",
            ) from exc
        yield
    finally:
        os.close(descriptor)
