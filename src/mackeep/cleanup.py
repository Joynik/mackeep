"""Reconcile the whole backup with the successfully copied manifest."""

import os
from pathlib import Path

from .application import Reporter
from .backupstate import BackupState
from .config import ConfigError
from .paths import STATE_DIRECTORY, inside
from .projects import PREFIX
from .transaction import Transaction


def _obsolete_paths(root: str, retained: set[str], *, preserve_projects: bool) -> list[str]:
    """Scan without following links; retain metadata and rollback recovery workspaces."""
    keep = set(retained)
    entries: set[str] = set()

    def protect(relative: str) -> None:
        keep.add(relative)
        keep.update(str(parent) for parent in Path(relative).parents)

    for relative in retained:
        protect(relative)
    if os.path.islink(os.path.join(root, STATE_DIRECTORY)):
        raise ConfigError("The backup state directory cannot be a symlink")

    def scan(directory: str) -> None:
        with os.scandir(directory) as children:
            for entry in children:
                relative = os.path.relpath(entry.path, root)
                is_directory = entry.is_dir(follow_symlinks=False)
                recovery = (
                    is_directory
                    and entry.name.startswith(".mackeep-")
                    and any(
                        os.path.lexists(os.path.join(entry.path, name))
                        for name in ("previous", "failed", "new")
                    )
                )
                if (
                    relative == STATE_DIRECTORY
                    or (preserve_projects and relative == "Project")
                    or recovery
                ):
                    protect(relative)
                    continue
                entries.add(relative)
                if is_directory:
                    scan(entry.path)

    scan(root)
    obsolete = entries - keep
    return sorted(path for path in obsolete if str(Path(path).parent) not in obsolete)


def cleanup_backup(
    root: str,
    active: set[str],
    *,
    preserve_projects: bool,
    dry_run: bool,
    replace_backup: bool,
    reporter: Reporter | None,
    planned_owners: dict[str, set[str]] | None = None,
) -> None:
    """Delete everything outside the current manifest, preserving protected groups."""
    state = BackupState(root)
    if dry_run and not os.path.lexists(root):
        return
    if dry_run and planned_owners is not None:
        state.owners.update({owner: sorted(paths) for owner, paths in planned_owners.items()})
    removed = frozenset(
        owner
        for owner in state.owners
        if owner not in active and not (preserve_projects and owner.startswith(PREFIX))
    )
    retained = {
        path for owner, paths in state.owners.items() if owner not in removed for path in paths
    }
    obsolete = _obsolete_paths(root, retained, preserve_projects=preserve_projects)
    if not removed and not obsolete:
        return
    if obsolete and not dry_run and not replace_backup:
        raise ConfigError("Backup cleanup declined by --force-no; previous snapshots retained")
    transaction = Transaction()
    events = []
    try:
        for relative in obsolete:
            path = os.path.join(root, relative)
            if not inside(os.path.realpath(os.path.dirname(path)), os.path.realpath(root)):
                raise ConfigError(f"Cleanup path escapes storage: {path}")
            if not os.path.lexists(path):
                continue
            events.append(
                {
                    "app": "Backup cleanup",
                    "action": "stale_in_backup",
                    "src": path,
                    "dst": path,
                    "will_remove": True,
                }
            )
            if not dry_run:
                transaction.prepare(path, None)
        if not dry_run:
            state.save(transaction, None, set(), remove=removed)
            transaction.commit()
    finally:
        transaction.close()
    if reporter:
        reporter("start", {"app": "Backup cleanup", "action": "backup"})
        for details in events:
            reporter("stale_in_backup", details)
        reporter("done", {"app": "Backup cleanup", "action": "backup"})
