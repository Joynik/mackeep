"""Independent project definitions and root-relative transactional profiles."""

import json
import os
import uuid
from pathlib import Path
from typing import Any

from .application import ApplicationProfile
from .config import ConfigError
from .excludes import Matcher
from .jsonapi import SCHEMA_VERSION
from .locking import storage_lock
from .mackeep import Mackeep
from .paths import inside, validate_pair
from .transaction import Transaction

PREFIX = "project:"


class ProjectStore:
    """Keep definitions beside the selected config, outside the application catalog."""

    def __init__(self, config_path: str) -> None:
        self.path = Path(config_path).with_name(Path(config_path).name + ".projects.json")

    def load(self) -> list[dict[str, Any]]:
        """Read all definitions without creating files."""
        if not self.path.exists():
            return []
        try:
            values = json.loads(self.path.read_text())
            if not isinstance(values, list):
                raise ValueError("Expected a project list")
            if any(not isinstance(value, dict) or not value.get("id") for value in values):
                raise ValueError("Stored projects require persistent identifiers")
            projects = [validate(value) for value in values]
            ids = [value["id"] for value in projects]
            names = [value["name"].casefold() for value in projects]
            if len(set(ids)) != len(ids) or len(set(names)) != len(names):
                raise ValueError("Project identifiers and names must be unique")
        except (ValueError, TypeError, KeyError) as exc:
            raise ConfigError(f"Invalid project definitions: {exc}") from exc
        return projects

    def update(self, value: dict[str, Any] | None, identifier: str = "") -> list[dict[str, Any]]:
        """Atomically save or delete one definition, retaining existing backups."""
        with storage_lock(str(self.path)):
            projects = self.load()
            if value is None:
                if not any(project["id"] == identifier for project in projects):
                    raise ConfigError(f"Unknown project: {identifier}")
                projects = [project for project in projects if project["id"] != identifier]
            else:
                project = validate(value)
                if any(
                    old["id"] != project["id"]
                    and old["name"].casefold() == project["name"].casefold()
                    for old in projects
                ):
                    raise ConfigError("Project names must be unique")
                projects = [old for old in projects if old["id"] != project["id"]]
                projects.append(project)

            def write(staged: str) -> None:
                Path(staged).write_text(json.dumps(projects, indent=2) + "\n")

            transaction = Transaction()
            try:
                transaction.prepare(
                    str(self.path),
                    write,
                )
                transaction.commit()
            finally:
                transaction.close()
        return projects


def validate(value: Any) -> dict[str, Any]:
    """Validate definition data without imposing application HOME/XDG restrictions."""
    if not isinstance(value, dict):
        raise ConfigError("Expected a project object")
    identifier = value.get("id") or str(uuid.uuid4())
    try:
        identifier = str(uuid.UUID(identifier))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ConfigError("Invalid project identifier") from exc
    name = value.get("name", "")
    root = value.get("root", "")
    if not isinstance(name, str) or not name.strip() or any(c in name for c in "\n\r\0"):
        raise ConfigError("A project name is required")
    if name.strip() in {".", ".."} or any(c in name for c in "/\\"):
        raise ConfigError("Project names must be valid folder names")
    if not isinstance(root, str) or not os.path.isabs(root) or "\0" in root:
        raise ConfigError("The project root must be an absolute path")
    files = value.get("files", [])
    exclude = value.get("exclude", [])
    if not isinstance(files, list) or not isinstance(exclude, list):
        raise ConfigError("Project paths and exclusions must be lists")
    for entry in files:
        if (
            not isinstance(entry, str)
            or not entry.strip()
            or os.path.isabs(entry)
            or ".." in Path(entry).parts
            or "\0" in entry
        ):
            raise ConfigError("Project paths must be relative to the project root")
    if any(not isinstance(pattern, str) or "\0" in pattern for pattern in exclude):
        raise ConfigError("Invalid project exclusion")
    enabled = value.get("enabled", True)
    if not isinstance(enabled, bool):
        raise ConfigError("Project enabled must be true or false")
    return {
        "schema_version": SCHEMA_VERSION,
        "id": identifier,
        "name": name.strip(),
        "root": os.path.normpath(root),
        "files": list(dict.fromkeys(files)),
        "exclude": exclude,
        "enabled": enabled,
    }


class ProjectProfile(ApplicationProfile):
    """Reuse the copy engine while mapping paths from a project's own root."""

    def __init__(
        self, mackeep: Mackeep, project: dict[str, Any], dry_run: bool, verbose: bool
    ) -> None:
        super().__init__(mackeep, set(project["files"]), dry_run, verbose)
        self.project = project
        self.configure(exclude=Matcher(project["exclude"]), app_name=PREFIX + project["id"])

    def get_filepaths(self, filename: str) -> tuple[str, str]:
        """Map a project-relative path into its isolated backup namespace."""
        return (
            os.path.normpath(os.path.join(self.project["root"], filename)),
            os.path.normpath(
                os.path.join(
                    self.mackeep.mackeep_folder,
                    "Project",
                    self.project["name"],
                    filename,
                )
            ),
        )

    def preflight(self, action: str) -> None:
        """Reject overlapping roots and escaping parents before any writes."""
        root = self.project["root"]
        storage = self.mackeep.mackeep_folder
        validate_pair(root, storage)
        namespace = os.path.join(storage, "Project", self.project["name"])
        expected = os.path.join(os.path.realpath(storage), "Project", self.project["name"])
        if os.path.realpath(namespace) != expected:
            raise ConfigError(f"Project backup namespace contains a symbolic link: {namespace}")
        for filename in self.files:
            local, backup = self.get_filepaths(filename)
            for path, boundary in ((local, root), (backup, storage)):
                if not inside(os.path.realpath(path), os.path.realpath(boundary)):
                    raise ConfigError(f"Project path escapes its root: {path}")
            if action == "copy_files_to_mackeep_folder" and not os.path.isdir(root):
                raise ConfigError(f"Project root does not exist: {root}")
            validate_pair(local, backup)
