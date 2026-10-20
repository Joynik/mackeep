"""Tests for the Mackeep class, the state of the program."""

import os
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.mackeep import Mackeep

# The content of the main config file
MAIN_CONFIG = (
    "[storage]\n"
    "engine = file_system\n"
    "path = {storage}\n"
    "directory = Mackeep\n"
)


def write_config(home, path, content=MAIN_CONFIG):
    """Write a config file, creating its directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.format(storage=home / "storage"))


def test_the_environment_is_not_usable_as_root(home):
    """Mackeep does not run as root without the root option."""
    write_config(home, home / ".mackeep.cfg")
    utils.CAN_RUN_AS_ROOT = False

    mackeep = Mackeep()

    with patch("os.geteuid", return_value=0), pytest.raises(SystemExit):
        mackeep.check_for_usable_environment()


def test_the_environment_is_usable_as_root_with_the_option(home):
    """Mackeep runs as root with the root option."""
    write_config(home, home / ".mackeep.cfg")
    utils.CAN_RUN_AS_ROOT = True

    mackeep = Mackeep()

    with patch("os.geteuid", return_value=0):
        mackeep.check_for_usable_environment()


def test_the_environment_is_not_usable_without_the_storage_folder(home):
    """Mackeep needs the storage folder to work."""
    write_config(
        home,
        home / ".mackeep.cfg",
        "[storage]\nengine = file_system\npath = {storage}/missing\n"
        "directory = Mackeep\n",
    )

    mackeep = Mackeep()

    with pytest.raises(SystemExit):
        mackeep.check_for_usable_environment()


def test_the_backup_environment_needs_a_home(home):
    """Mackeep needs a folder to store the configuration files."""
    write_config(home, home / ".mackeep.cfg")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    mackeep = Mackeep()

    with pytest.raises(SystemExit):
        mackeep.check_for_usable_backup_env()


def test_the_backup_environment_creates_the_home(home):
    """The backup environment creates the folder of the backup."""
    write_config(home, home / ".mackeep.cfg")

    mackeep = Mackeep()
    mackeep.check_for_usable_backup_env()

    assert os.path.isdir(mackeep.mackeep_folder)


def test_the_restore_environment_needs_the_backup_folder(home):
    """Mackeep needs the folder of the backup to restore the files."""
    write_config(home, home / ".mackeep.cfg")

    mackeep = Mackeep()

    with pytest.raises(SystemExit):
        mackeep.check_for_usable_restore_env()


def test_the_ignored_applications_are_not_backed_up(home):
    """The applications of the ignore list are not backed up."""
    write_config(
        home,
        home / ".mackeep.cfg",
        MAIN_CONFIG + "\n[applications_to_ignore]\ntest-app\n",
    )

    mackeep = Mackeep()

    assert "test-app" not in mackeep.get_apps_to_backup()
