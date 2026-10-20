"""
Migration of the legacy Mackup files to their new Mackeep location.

The files of Mackup are copied, never moved nor deleted, so the user can
check them before removing the old ones.
"""

import os
import shutil

from .constants import (
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
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

    Returns:
        list of dict: The action ("copy" or "skip"), the source and the
        destination of every file.
    """
    actions: list[dict[str, str]] = []

    for legacy, new in _config_files():
        if not os.path.isfile(legacy):
            continue
        actions.append(_action(legacy, new))
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

    Args:
        actions (list): The actions of the plan.

    Returns:
        int: The number of copied files.
    """
    copied: int = 0
    for action in actions:
        if action["action"] != "copy":
            continue
        os.makedirs(os.path.dirname(action["dst"]), exist_ok=True)
        shutil.copy2(action["src"], action["dst"])
        copied += 1
    return copied
