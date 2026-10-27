"""Compact human-readable backup output, using committed operation events."""

import io
import sys
from dataclasses import dataclass, field
from typing import Any


class SummaryOutput(io.TextIOBase):
    """Hide progress lines while retaining diagnostics from the copy engine."""

    def __init__(self) -> None:
        super().__init__()
        self.pending = ""

    def write(self, text: str) -> int:
        self.pending += text
        while "\n" in self.pending:
            line, self.pending = self.pending.split("\n", 1)
            if not line.startswith("Backing up "):
                print(line, file=sys.stderr)
        return len(text)

    def flush(self) -> None:
        if self.pending:
            print(self.pending, file=sys.stderr)
            self.pending = ""


@dataclass
class BackupSummary:
    """Count files only after commit; errors and skips have separate units."""

    completed: set[str] = field(default_factory=set)
    failed: set[str] = field(default_factory=set)
    sensitive: set[str] = field(default_factory=set)
    copied: int = 0
    skipped: int = 0

    def __call__(self, event: str, details: dict[str, Any]) -> None:
        app = str(details.get("app", ""))
        if event == "done":
            self.completed.add(app)
        elif event in {"error", "conflict"}:
            self.failed.add(app)
            if event == "conflict":
                print(
                    f"Error: {app}: replacement declined: {details['dst']}",
                    file=sys.stderr,
                )
        elif event == "copy":
            self.copied += 1
            if details.get("sensitive"):
                self.sensitive.add(app)
        elif event.startswith("skip_"):
            self.skipped += 1

    def display(self) -> None:
        """Print an English result without claiming file counts on rollback."""
        for app in sorted(self.sensitive):
            print(
                f"Warning: {app} holds secrets. Backups are unencrypted.",
                file=sys.stderr,
            )
        rows = (
            ("Applications processed", len(self.completed)),
            ("Applications succeeded", len(self.completed - self.failed)),
            ("Applications failed", len(self.failed)),
            ("Files copied", self.copied),
            ("Paths skipped", self.skipped),
        )
        print("Backup summary")
        border = "+------------------------+----------+"
        print(border)
        for label, count in rows:
            print(f"| {label:<22} | {count:>8} |")
        print(border)
