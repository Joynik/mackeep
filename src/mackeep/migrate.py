"""
Migration of the legacy files to their new Mackeep location.

The files are copied, never moved nor deleted, so the user can check them
before removing the old ones.
"""

import configparser
import os
import shutil

from .config import Config, ConfigError
from .constants import (
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    LEGACY_BACKUP_PATH,
    LEGACY_CONFIG_FILE,
    LEGACY_CUSTOM_APPS_DIR,
    LEGACY_CUSTOM_APPS_DIR_XDG,
    MACKEEP_CONFIG_FILE,
)

# The application of Mackup itself is now named mackeep
LEGACY_APP_NAME: str = "mackup.cfg"
APP_NAME: str = "mackeep.cfg"


def _config_files() -> list[tuple[str, str]]:
    """
    Get the legacy config files and their new location.

    Returns:
        list of (str, str): The legacy path and the new path.
    """
    home: str = os.environ["HOME"]
    xdg_config_home: str = os.environ.get(
        "XDG_CONFIG_HOME", os.path.join(home, ".config"),
    )
    return [
        (
            os.path.join(home, LEGACY_CONFIG_FILE),
            os.path.join(home, MACKEEP_CONFIG_FILE),
        ),
        (
            os.path.join(xdg_config_home, "mackup", LEGACY_CONFIG_FILE.lstrip(".")),
            os.path.join(xdg_config_home, "mackeep", MACKEEP_CONFIG_FILE.lstrip(".")),
        ),
    ]


def _apps_dirs() -> list[tuple[str, str]]:
    """
    Get the legacy application config directories and their new location.

    Returns:
        list of (str, str): The legacy path and the new path.
    """
    home: str = os.environ["HOME"]
    xdg_config_home: str = os.environ.get(
        "XDG_CONFIG_HOME", os.path.join(home, ".config"),
    )
    return [
        (
            os.path.join(home, LEGACY_CUSTOM_APPS_DIR),
            os.path.join(home, CUSTOM_APPS_DIR),
        ),
        (
            os.path.join(xdg_config_home, LEGACY_CUSTOM_APPS_DIR_XDG),
            os.path.join(xdg_config_home, CUSTOM_APPS_DIR_XDG),
        ),
    ]


def plan() -> list[dict[str, str]]:
    """
    Build the plan of the migration.

    The files that already exist in their new location are skipped, they
    are never overwritten.

    When the storage folder of Mackup is used, the name of that folder is
    written in the new config file, so the backup stays in the same place.

    Returns:
        list of dict: The action ("copy", "skip" or "set_directory"), the
        source and the destination of every file.
    """
    actions: list[dict[str, str]] = []

    for legacy, new in _config_files():
        if not os.path.isfile(legacy):
            continue
        action: dict[str, str] = _action(legacy, new)
        actions.append(action)
        if action["action"] == "copy":
            directory: str | None = _storage_directory(legacy)
            if directory:
                actions.append({
                    "action": "set_directory",
                    "src": legacy,
                    "dst": new,
                    "directory": directory,
                })
        # Only the first legacy config file is migrated.
        break

    for legacy_dir, new_dir in _apps_dirs():
        if not os.path.isdir(legacy_dir):
            continue
        for filename in sorted(os.listdir(legacy_dir)):
            if not filename.endswith(".cfg"):
                continue
            name: str = APP_NAME if filename == LEGACY_APP_NAME else filename
            actions.append(_action(os.path.join(legacy_dir, filename),
                                   os.path.join(new_dir, name)))

    return actions


def _storage_directory(config_path: str) -> str | None:
    """
    Get the name of the storage directory to keep in the new config file.

    When the storage folder of Mackup is used and the config file does not
    set a directory, the name of the legacy folder has to be written in the
    new config file, so the backup stays in the same folder.

    Args:
        config_path (str): The path of the legacy config file.

    Returns:
        str or None: The name of the storage directory, None when there is
        nothing to keep.
    """
    try:
        config: Config = Config(config_path)
    except (ConfigError, SystemExit):
        return None

    if _has_directory_option(config_path):
        # The directory is explicitly set, it is never replaced.
        return None

    legacy_directory: str = os.path.join(config.path, LEGACY_BACKUP_PATH)
    if not os.path.isdir(legacy_directory):
        return None

    return LEGACY_BACKUP_PATH


def _has_directory_option(config_path: str) -> bool:
    """
    Whether the config file sets the name of the storage directory.

    Args:
        config_path (str): The path of the config file.

    Returns:
        bool
    """
    parser: configparser.ConfigParser = configparser.ConfigParser(
        allow_no_value=True, inline_comment_prefixes=(";", "#"),
    )
    try:
        parser.read(config_path)
    except configparser.Error:
        return False

    return parser.has_option("storage", "directory")


def _action(src: str, dst: str) -> dict[str, str]:
    """
    Build the action of a file of the plan.

    Args:
        src (str): The path of the legacy file.
        dst (str): The path of the new file.

    Returns:
        dict
    """
    return {
        "action": "skip" if os.path.exists(dst) else "copy",
        "src": src,
        "dst": dst,
    }


def run(actions: list[dict[str, str]]) -> int:
    """
    Copy the files of the plan to their new location.

    The name of the storage directory is written in the config files that
    were just copied.

    Args:
        actions (list): The actions of the plan.

    Returns:
        int: The number of copied files.
    """
    copied: int = 0
    updated: set[str] = set()
    for action in actions:
        if action["action"] == "copy":
            os.makedirs(os.path.dirname(action["dst"]), exist_ok=True)
            shutil.copy2(action["src"], action["dst"])
            copied += 1
            updated.add(action["dst"])
        elif action["action"] == "set_directory" and action["dst"] in updated:
            _set_directory(action["dst"], action["directory"])
    return copied


def _set_directory(path: str, directory: str) -> None:
    """
    Write the name of the storage directory in a config file.

    The other options and the comments of the file are kept.

    Args:
        path (str): The path of the config file.
        directory (str): The name of the storage directory.
    """
    with open(path, encoding="utf-8") as file:
        lines: list[str] = file.read().splitlines()

    start, end = _storage_section(lines)

    # The option is already there, it is replaced
    for index in range(start + 1, end):
        stripped: str = lines[index].strip()
        if "=" not in stripped:
            continue
        key: str = stripped.split("=", 1)[0].strip().lower()
        if key == "directory":
            lines[index] = f"directory = {directory}"
            _write_lines(path, lines)
            return

    # The option is not there yet
    if start < 0:
        # There is no storage section in the file yet
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("[storage]")
        lines.append(f"directory = {directory}")
    else:
        # The option is added after the last option of the section
        position: int = end
        while position > start + 1 and not lines[position - 1].strip():
            position -= 1
        lines.insert(position, f"directory = {directory}")

    _write_lines(path, lines)


def _storage_section(lines: list[str]) -> tuple[int, int]:
    """
    Get the bounds of the storage section of a config file.

    Args:
        lines (list): The lines of the config file.

    Returns:
        tuple: The index of the first line of the section and the index of
        the line after its last one. Both are -1 when there is no section.
    """
    start: int = -1
    end: int = -1
    section: str = ""

    for index, line in enumerate(lines):
        stripped: str = line.strip()
        if not (stripped.startswith("[") and stripped.endswith("]")):
            continue
        if section == "storage":
            end = index
            break
        section = stripped[1:-1].strip().lower()
        if section == "storage":
            start = index

    if start >= 0 and end < 0:
        end = len(lines)

    return start, end


def _write_lines(path: str, lines: list[str]) -> None:
    """
    Write the lines in a config file.

    Args:
        path (str): The path of the config file.
        lines (list): The lines of the file.
    """
    with open(path, "w", encoding="utf-8") as file:
        file.write("\n".join(lines) + "\n")
