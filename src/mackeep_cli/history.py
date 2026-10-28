"""Private run records read alongside the desktop's existing history."""

import json
import os
import platform
import stat
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4


def history_directory() -> Path:
    """Use the desktop support directory on macOS, XDG state elsewhere."""
    if platform.system() == "Darwin":
        return Path.home() / "Library/Application Support/Mackeep/cli-history"
    return (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "mackeep/cli-history"
    )


@dataclass
class OperationHistory:
    """Collect committed copies without changing the command's output."""

    command: str
    application: str | None
    date: str = field(
        default_factory=lambda: datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    files: int = 0
    bytes: int = 0
    message: str | None = None

    def report(self, event: str, details: dict[str, Any]) -> None:
        """Copy events arrive only after the application transaction commits."""
        if event == "copy":
            self.files += 1
            self.bytes += int(details.get("size_bytes") or 0)
        elif event == "error":
            self.message = str(details.get("message", "Operation failed."))
        elif event == "conflict":
            self.message = "Replacement declined."

    def save(self) -> None:
        """Separate atomic files avoid racing the desktop history writer."""
        directory = history_directory()
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        if not stat.S_ISDIR(directory.lstat().st_mode):
            raise OSError("CLI history directory must not be a symbolic link.")
        identifier = str(uuid4())
        record = {
            "id": identifier,
            "date": self.date,
            "command": self.command,
            "application": self.application,
            "succeeded": self.message is None,
            "files": self.files,
            "bytes": self.bytes,
            "message": self.message,
        }
        temporary = directory / f".{identifier}.tmp"
        try:
            with temporary.open("x", encoding="utf-8") as stream:
                os.chmod(temporary, 0o600)
                json.dump(record, stream)
                stream.write("\n")
            temporary.replace(directory / f"{identifier}.json")
        finally:
            temporary.unlink(missing_ok=True)
        records = []
        for path in directory.glob("*.json"):
            try:
                UUID(path.stem)
                info = path.lstat()
                if stat.S_ISREG(info.st_mode):
                    records.append((info.st_mtime_ns, path))
            except ValueError, FileNotFoundError:
                continue
        for _, path in sorted(records, reverse=True)[50:]:
            path.unlink(missing_ok=True)
