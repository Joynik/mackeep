"""Tests for the conflicts and the edge cases of the backup and the restore."""

import json
import os
from unittest.mock import Mock, patch

import pytest

from mackeep import utils
from mackeep.application import ApplicationProfile
from mackeep.mackeep import Mackeep
from mackeep_cli.main import main

# The content of the config file of the test application
APP_CONFIG = "[application]\nname = Test App\n\n[configuration_files]\n.testrc\n"

# The content of the main config file
MAIN_CONFIG = (
    "[storage]\n"
    "engine = file_system\n"
    "path = {storage}\n"
    "directory = Mackeep\n"
    "\n"
    "[applications_to_sync]\n"
    "test-app\n"
)


def write_config(home, path, content=MAIN_CONFIG):
    """Write a config file, creating its directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.format(storage=home / "storage"))


def setup(home, files=(".testrc",), folders=(), app_config=APP_CONFIG):
    """Set up a home directory with a config file and a test application."""
    write_config(home, home / ".mackeep.cfg")
    write_config(home, home / ".mackeep" / "test-app.cfg", app_config)
    for name in files:
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("content\n")
    for name in folders:
        (home / name).mkdir(parents=True, exist_ok=True)

    return home / "storage" / "Mackeep"


def run(*args):
    """Run the Mackeep command line with the given arguments."""
    with patch("sys.argv", ["mackeep-cli", *args]):
        main()


def events_of(captured):
    """Read the events of a JSON output."""
    return [json.loads(line) for line in captured.out.splitlines() if line]


def test_the_backup_reports_a_conflict(home, capsys):
    """The backup reports the conflict when the user says no."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("old content\n")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    with pytest.raises(SystemExit):
        run("--json", "--force-no", "backup", "test-app")
    captured = capsys.readouterr()

    conflicts: list[dict] = [
        event for event in events_of(captured) if event.get("action") == "conflict"
    ]

    assert len(conflicts) == 1
    assert conflicts[0]["dst"].endswith(".testrc")
    # The old file is kept
    assert (backup / ".testrc").read_text() == "old content\n"


def test_the_backup_replaces_a_folder(home):
    """The backup replaces a folder of the backup with a file."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").mkdir()

    run("backup", "test-app")

    assert (backup / ".testrc").is_file()
    assert (backup / ".testrc").read_text() == "content\n"


def test_the_backup_of_a_folder(home):
    """The backup copies a folder of the home."""
    backup = setup(
        home,
        files=(),
        folders=(".testfolder",),
        app_config=APP_CONFIG.replace(".testrc", ".testfolder"),
    )
    backup.mkdir(parents=True, exist_ok=True)
    (home / ".testfolder" / "config").write_text("content\n")

    run("backup", "test-app")

    assert (backup / ".testfolder" / "config").read_text() == "content\n"


def test_the_verbose_backup(home, capsys):
    """The verbose backup tells what it does."""
    setup(home)
    (home / "storage" / "Mackeep").mkdir(parents=True, exist_ok=True)

    run("--verbose", "backup", "test-app")
    captured = capsys.readouterr()

    assert "Backing up" in captured.out


def test_the_restore_reports_a_conflict(home, capsys):
    """The restore reports the conflict when the user says no."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("backup content\n")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    with pytest.raises(SystemExit):
        run("--json", "restore", "test-app")
    captured = capsys.readouterr()

    conflicts: list[dict] = [
        event for event in events_of(captured) if event.get("action") == "conflict"
    ]

    assert len(conflicts) == 1
    # The file of the home is kept
    assert (home / ".testrc").read_text() == "content\n"


def test_the_restore_replaces_a_folder(home):
    """The restore replaces a folder of the home with a file."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("backup content\n")
    (home / ".testrc").unlink()
    (home / ".testrc").mkdir()

    run("restore", "test-app")

    assert (home / ".testrc").is_file()
    assert (home / ".testrc").read_text() == "backup content\n"


def test_the_restore_of_a_folder(home):
    """The restore copies a folder of the backup."""
    backup = setup(
        home,
        files=(),
        folders=(".testfolder",),
        app_config=APP_CONFIG.replace(".testrc", ".testfolder"),
    )
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testfolder").mkdir(parents=True, exist_ok=True)
    (backup / ".testfolder" / "config").write_text("content\n")

    run("restore", "test-app")

    assert (home / ".testfolder" / "config").read_text() == "content\n"


def test_the_verbose_restore(home, capsys):
    """The verbose restore tells what it does."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("content\n")

    run("--verbose", "restore", "test-app")
    captured = capsys.readouterr()

    assert "Recovering" in captured.out


def test_the_verbose_link_install(home, capsys):
    """The verbose link install tells what it does."""
    setup(home)
    (home / "storage" / "Mackeep").mkdir(parents=True, exist_ok=True)

    run("--verbose", "link", "install")
    captured = capsys.readouterr()

    assert "Backing up" in captured.out


def test_the_verbose_link(home, capsys):
    """The verbose link tells what it does."""
    backup = setup(home, files=())
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("content\n")

    run("--verbose", "link")
    captured = capsys.readouterr()

    assert "Restoring" in captured.out


def test_the_verbose_link_uninstall(home, capsys):
    """The verbose link uninstall tells what it does."""
    setup(home)
    (home / "storage" / "Mackeep").mkdir(parents=True, exist_ok=True)
    run("link", "install")

    run("--verbose", "link", "uninstall")
    captured = capsys.readouterr()

    assert "Reverting" in captured.out


def test_the_link_install_replaces_a_folder(home):
    """The link install replaces a folder of the backup with a file."""
    backup = setup(home)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").mkdir()

    run("link", "install")

    assert (backup / ".testrc").is_file()
    assert (home / ".testrc").is_symlink()


def test_the_link_replaces_a_link(home):
    """The link replaces a link of the home that points somewhere else."""
    backup = setup(home, files=())
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("content\n")
    other = home / "other"
    other.write_text("other content\n")
    os.symlink(str(other), str(home / ".testrc"))

    run("link")

    assert (home / ".testrc").is_symlink()
    assert os.path.samefile(home / ".testrc", backup / ".testrc")


def test_the_xdg_home_is_used(home, monkeypatch):
    """The XDG config home is relative to the home directory."""
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / ".config"))

    profile = ApplicationProfile(
        mackeep=Mock(spec=Mackeep),
        files={".testrc"},
        dry_run=False,
        verbose=False,
    )

    # The private members are the ones that are tested here
    assert profile._xdg_home == ".config"  # noqa: SLF001
    assert profile._xdg_relative(".config") == ""  # noqa: SLF001
    assert profile._xdg_relative(".config/app/config") == "app/config"  # noqa: SLF001
    assert profile._xdg_relative(".other") is None  # noqa: SLF001


def test_the_xdg_home_outside_of_the_home_is_ignored(home, monkeypatch):
    """The XDG config home outside of the home directory is ignored."""
    monkeypatch.setenv("XDG_CONFIG_HOME", "/somewhere/else")

    profile = ApplicationProfile(
        mackeep=Mock(spec=Mackeep),
        files={".testrc"},
        dry_run=False,
        verbose=False,
    )

    assert profile._xdg_home is None  # noqa: SLF001
    assert profile._xdg_relative(".config/app") is None  # noqa: SLF001
