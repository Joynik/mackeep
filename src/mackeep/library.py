"""Download independently published, declarative library definitions."""

import configparser
import hashlib
import json
import os
import re
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.request import urlopen

from .config import Config, ConfigError
from .constants import APPS_DIR
from .jsonapi import SCHEMA_VERSION
from .locking import storage_lock

SOURCE = "https://raw.githubusercontent.com/Joynik/mackeep"
MANIFEST_URL = f"{SOURCE}/library-index/library-manifest.json"
MANIFEST_VERSION = 1
MAX_MANIFEST_BYTES = 2 * 1024 * 1024
MAX_DEFINITION_BYTES = 256 * 1024
NAME = re.compile(r"[a-z0-9][a-z0-9_.+-]*\.cfg\Z")
SHA256 = re.compile(r"[a-f0-9]{64}\Z")
REVISION = re.compile(r"[a-f0-9]{40}\Z")


def directory() -> Path:
    """Return the managed library, separate from user definitions."""
    return Path.home() / ".local/share/mackeep/library"


def bundled_directory() -> Path:
    """Return the fallback library shipped with the CLI."""
    return Path(__file__).resolve().parent / APPS_DIR


def hidden_definitions() -> set[str]:
    """Read explicit user removals; bundled files themselves remain read-only."""
    path = directory() / "removed.json"
    if not path.exists():
        return set()
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as exc:
        raise ConfigError("Invalid removed library definitions index") from exc
    if not isinstance(value, list) or any(
        not isinstance(name, str) or not NAME.fullmatch(name) for name in value
    ):
        raise ConfigError("Invalid removed library definitions index")
    return set(value)


def _local_files() -> dict[str, Path]:
    """Index library files without including personal definitions."""
    return {
        path.name: path
        for root in (bundled_directory(), directory())
        for path in root.glob("*.cfg")
        if path.is_file()
    }


def _writable_directory() -> Path:
    """Reject linked components before writing managed library files."""
    target = directory()
    for component in (target, *target.parents):
        if component == Path.home():
            break
        if component.is_symlink():
            raise ConfigError(
                "The managed library path must not contain symbolic links",
            )
    return target


def _download(url: str, limit: int) -> bytes:
    """Bound network time and response size for the fixed upstream source."""
    with urlopen(url, timeout=20) as response:
        data: bytes = response.read(limit + 1)
    if len(data) > limit:
        raise ConfigError("Library response exceeds the size limit")
    return data


def validate_definition(data: bytes) -> None:
    """Reject malformed definitions before replacing an active file."""
    parser = configparser.ConfigParser(allow_no_value=True, strict=False)
    try:
        parser.read_string(data.decode("utf-8"))
        name = parser.get("application", "name")
        if not isinstance(name, str) or not name.strip():
            raise ConfigError("Library definition has an empty application name")
        for section in ("configuration_files", "xdg_configuration_files"):
            if parser.has_section(section):
                for path in parser.options(section):
                    if path.startswith("/") or ".." in path.split("/"):
                        raise ConfigError(f"Invalid library definition path: {path}")
        for section in ("exclude", "xdg_exclude"):
            if parser.has_section(section):
                for option, value in parser.items(section, raw=True):
                    if (value if value is not None else option).strip().startswith("/"):
                        raise ConfigError("Invalid absolute library exclusion")
    except (UnicodeError, configparser.Error) as exc:
        raise ConfigError(f"Invalid library definition: {exc}") from exc


def read_manifest() -> dict[str, Any]:
    """Read and validate metadata without trusting paths or URLs from JSON."""
    try:
        manifest = json.loads(_download(MANIFEST_URL, MAX_MANIFEST_BYTES))
    except (ValueError, UnicodeError) as exc:
        raise ConfigError("Invalid library manifest JSON") from exc
    if not isinstance(manifest, dict):
        raise ConfigError("Invalid library manifest")
    if manifest.get("version") != MANIFEST_VERSION:
        raise ConfigError("Unsupported library manifest version; update MacKeep")
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ConfigError("This library requires a different MacKeep version")
    revision = manifest.get("revision")
    files = manifest.get("files")
    if not isinstance(revision, str) or not REVISION.fullmatch(revision):
        raise ConfigError("Invalid library revision")
    if not isinstance(files, dict) or not files:
        raise ConfigError("Invalid library file index")
    for name, digest in files.items():
        if not isinstance(name, str) or not NAME.fullmatch(name):
            raise ConfigError("Invalid library filename")
        if not isinstance(digest, str) or not SHA256.fullmatch(digest):
            raise ConfigError("Invalid library checksum")
    names = manifest.get("names", {})
    if not isinstance(names, dict) or any(
        filename not in files or not isinstance(title, str) or not title.strip()
        for filename, title in names.items()
    ):
        raise ConfigError("Invalid library display names")
    return manifest


def _updates(manifest: dict[str, Any]) -> list[dict[str, str]]:
    """Compare the active library contents, independently of personal rules."""
    result = []
    hidden = hidden_definitions()
    for filename, digest in sorted(manifest["files"].items()):
        path = directory() / filename
        if not path.is_file():
            path = bundled_directory() / filename
        if (
            filename in hidden
            or not path.is_file()
            or hashlib.sha256(path.read_bytes()).hexdigest() != digest
        ):
            result.append({"name": filename[:-4], "sha256": digest})
    return result


def _status(manifest: dict[str, Any]) -> dict[str, Any]:
    hidden = hidden_definitions()
    local = _local_files()
    return {
        "schema_version": SCHEMA_VERSION,
        "revision": manifest["revision"],
        "updates": _updates(manifest),
        "new": [
            {
                "name": filename[:-4],
                "display_name": manifest.get("names", {}).get(filename, filename[:-4]),
            }
            for filename in sorted(manifest["files"])
            if filename not in local or filename in hidden
        ],
        "removed": [
            filename[:-4]
            for filename in sorted(local)
            if filename not in manifest["files"] and filename not in hidden
        ],
        "checked_at": datetime.now(UTC).isoformat(),
    }


def check() -> dict[str, Any]:
    """Check upstream without writing files or changing personal settings."""
    return _status(read_manifest())


def update(name: str | None = None) -> dict[str, Any]:
    """Validate all changed downloads, then atomically replace each definition."""
    manifest = read_manifest()
    if name is not None and f"{name}.cfg" not in manifest["files"]:
        raise ConfigError(f"Unknown library definition: {name}")
    target = _writable_directory()
    with storage_lock(str(target)):
        changes = _updates(manifest)
        if name is not None:
            changes = [change for change in changes if change["name"] == name]
        if not changes:
            return _status(manifest)
        target.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".download-", dir=target) as temporary:
            staged = Path(temporary)
            for change in changes:
                filename = f"{change['name']}.cfg"
                data = _download(
                    f"{SOURCE}/{manifest['revision']}/src/mackeep/applications/{filename}",
                    MAX_DEFINITION_BYTES,
                )
                if hashlib.sha256(data).hexdigest() != change["sha256"]:
                    raise ConfigError(f"Library checksum mismatch: {filename}")
                validate_definition(data)
                (staged / filename).write_bytes(data)
            for change in changes:
                filename = f"{change['name']}.cfg"
                os.replace(staged / filename, target / filename)
            hidden = hidden_definitions() - {
                f"{change['name']}.cfg" for change in changes
            }
            _write_hidden(hidden, staged)
    return _status(manifest)


def _write_hidden(hidden: set[str], staged: Path) -> None:
    path = staged / "removed.json"
    path.write_text(json.dumps(sorted(hidden)) + "\n", encoding="utf-8")
    os.replace(path, directory() / "removed.json")


def remove(name: str, config_file: str | None = None) -> dict[str, Any]:
    """Remove a retired definition only on request; never touch app settings."""
    filename = f"{name}.cfg"
    if not NAME.fullmatch(filename):
        raise ConfigError("Invalid library definition name")
    manifest = read_manifest()
    if filename in manifest["files"]:
        raise ConfigError("This definition is still available in the library")
    config = Config(config_file, read_only=True)
    if name in config.apps_to_sync - config.apps_to_ignore:
        raise ConfigError("Remove this application from the backup selection first")
    target = _writable_directory()
    with storage_lock(str(target)):
        if filename not in _local_files():
            raise ConfigError(f"Unknown library definition: {name}")
        target.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".remove-", dir=target) as temporary:
            _write_hidden(hidden_definitions() | {filename}, Path(temporary))
            (target / filename).unlink(missing_ok=True)
    return _status(manifest)
