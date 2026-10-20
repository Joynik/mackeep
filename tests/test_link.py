"""Tests for the link modes of Mackeep."""

import json
import os
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep_cli.main import main

# The content of the config file of the test application
APP_CONFIG = (
    "[application]\n"
    "name = Test App\n"
    "\n"
    "[configuration_files]\n"
    ".testrc\n"
)

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


def setup(home, files=(".testrc",), apps="test-app", content=MAIN_CONFIG):
    """Set up a home directory with a config file and a test application."""
    write_config(home, home / ".mackeep.cfg", content)
    write_config(home, home / ".mackeep" / "test-app.cfg", APP_CONFIG)
    for name in files:
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("test_config=value\n")

    backup = home / "storage" / "Mackeep"
    backup.mkdir(parents=True, exist_ok=True)

    return backup


def run(*args):
    """Run the Mackeep command line with the given arguments."""
    with patch("sys.argv", ["mackeep-cli", *args]):
        main()


def run_json(capsys, *args):
    """Run a command in JSON mode and return the parsed stdout and the code."""
    code: int = 0
    try:
        run("--json", *args)
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else 1
    captured = capsys.readouterr()
    return json.loads(captured.out), code


def test_the_link_install_moves_the_file_to_the_backup(home):
    """The link install command moves the file to the backup and links it."""
    backup = setup(home)

    run("link", "install")

    assert (backup / ".testrc").exists()
    assert (home / ".testrc").is_symlink()
    assert os.path.samefile(home / ".testrc", backup / ".testrc")


def test_the_link_install_of_one_application(home):
    """The link install command can be limited to one application."""
    backup = setup(home)

    run("link", "install", "test-app")

    assert (backup / ".testrc").exists()
    assert (home / ".testrc").is_symlink()


def test_the_link_install_replaces_the_old_backup(home):
    """The link install command replaces a backup that already exists."""
    backup = setup(home)
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("old content\n")

    run("link", "install")

    assert (backup / ".testrc").read_text() == "test_config=value\n"
    assert (home / ".testrc").is_symlink()


def test_the_link_install_keeps_the_old_backup_when_the_user_says_no(home):
    """The link install command keeps the backup when the user says no."""
    backup = setup(home)
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("old content\n")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    run("link", "install")

    assert (backup / ".testrc").read_text() == "old content\n"
    assert not (home / ".testrc").is_symlink()
    assert (home / ".testrc").read_text() == "test_config=value\n"


def test_the_link_install_does_nothing_in_the_dry_run(home):
    """The dry-run of the link install command changes nothing."""
    backup = setup(home)

    run("--dry-run", "link", "install")

    assert not (backup / ".testrc").exists()
    assert not (home / ".testrc").is_symlink()


def test_the_link_install_does_nothing_when_the_file_is_already_linked(home):
    """The link install command does nothing when the file is already linked."""
    backup = setup(home)
    run("link", "install")

    run("--verbose", "link", "install")

    assert (home / ".testrc").is_symlink()
    assert (backup / ".testrc").exists()


def test_the_link_install_does_nothing_when_the_file_is_missing(home):
    """The link install command says that the file does not exist."""
    setup(home, files=())

    run("--verbose", "link", "install")

    # The output is checked by the other tests, here we only check that
    # the command does not fail
    assert not (home / ".testrc").exists()


def test_the_link_install_skips_a_broken_link(home):
    """The link install command warns about a broken link."""
    setup(home, files=())
    os.symlink(str(home / "missing"), str(home / ".testrc"))

    run("--verbose", "link", "install")

    assert (home / ".testrc").is_symlink()


def test_the_link_install_skips_the_excluded_files(home):
    """The link install command skips the files that are excluded."""
    backup = setup(home)
    write_config(
        home,
        home / ".mackeep" / "test-app.cfg",
        APP_CONFIG + "\n[exclude]\n.testrc\n",
    )

    run("link", "install")

    assert not (backup / ".testrc").exists()
    assert not (home / ".testrc").is_symlink()


def test_the_link_creates_the_link(home):
    """The link command links the file of the backup to the home."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("test_config=value\n")

    run("link")

    assert (home / ".testrc").is_symlink()
    assert os.path.samefile(home / ".testrc", backup / ".testrc")


def test_the_link_replaces_the_file_of_the_home(home):
    """The link command replaces a file that is not a link."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("backup content\n")
    (home / ".testrc").write_text("home content\n")

    run("link")

    assert (home / ".testrc").is_symlink()
    assert (home / ".testrc").read_text() == "backup content\n"


def test_the_link_keeps_the_file_of_the_home_when_the_user_says_no(home):
    """The link command keeps the file of the home when the user says no."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("backup content\n")
    (home / ".testrc").write_text("home content\n")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    run("link")

    assert not (home / ".testrc").is_symlink()
    assert (home / ".testrc").read_text() == "home content\n"


def test_the_link_does_nothing_in_the_dry_run(home):
    """The dry-run of the link command changes nothing."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("test_config=value\n")

    run("--dry-run", "link")

    assert not (home / ".testrc").exists()


def test_the_link_does_nothing_when_the_file_is_already_linked(home):
    """The link command does nothing when the file is already linked."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("test_config=value\n")
    os.symlink(str(backup / ".testrc"), str(home / ".testrc"))

    run("--verbose", "link")

    assert (home / ".testrc").is_symlink()


def test_the_link_does_nothing_when_the_backup_is_missing(home):
    """The link command says that the backup does not exist."""
    setup(home, files=())

    run("--verbose", "link")

    assert not (home / ".testrc").exists()


def test_the_link_skips_a_broken_link(home):
    """The link command warns about a broken link."""
    setup(home, files=())
    os.symlink(str(home / "missing"), str(home / ".testrc"))

    run("--verbose", "link")

    assert (home / ".testrc").is_symlink()


def test_the_link_skips_the_excluded_files(home):
    """The link command skips the files that are excluded."""
    backup = setup(home, files=())
    (backup / ".testrc").parent.mkdir(parents=True, exist_ok=True)
    (backup / ".testrc").write_text("test_config=value\n")
    write_config(
        home,
        home / ".mackeep" / "test-app.cfg",
        APP_CONFIG + "\n[exclude]\n.testrc\n",
    )

    run("link")

    assert not (home / ".testrc").exists()


def test_the_link_uninstall_copies_the_file_back(home):
    """The link uninstall command copies the file of the backup back."""
    backup = setup(home)
    run("link", "install")

    run("link", "uninstall")

    assert not (home / ".testrc").is_symlink()
    assert (home / ".testrc").read_text() == "test_config=value\n"
    assert (backup / ".testrc").exists()


def test_the_link_uninstall_does_nothing_in_the_dry_run(home):
    """The dry-run of the link uninstall command changes nothing."""
    backup = setup(home)
    run("link", "install")

    run("--dry-run", "link", "uninstall")

    assert (home / ".testrc").is_symlink()
    assert (backup / ".testrc").exists()


def test_the_link_uninstall_does_nothing_when_the_backup_is_missing(home):
    """The link uninstall command says that the backup does not exist."""
    setup(home, files=())

    run("--verbose", "link", "uninstall")

    assert not (home / ".testrc").exists()


def test_the_link_uninstall_of_one_application(home):
    """The link uninstall command can be limited to one application."""
    backup = setup(home)
    run("link", "install")

    run("link", "uninstall", "test-app")

    assert not (home / ".testrc").is_symlink()
    assert (backup / ".testrc").exists()


def test_the_link_uninstall_of_every_application(home):
    """The link uninstall command unlinks every application."""
    setup(home)
    run("link", "install")

    run("link", "uninstall")

    assert not (home / ".testrc").is_symlink()
    assert (home / ".testrc").read_text() == "test_config=value\n"


def test_the_link_uninstall_asks_before_it_starts(home):
    """The link uninstall command asks the user before it unlinks everything."""
    backup = setup(home)
    run("link", "install")
    utils.FORCE_YES = False
    utils.FORCE_NO = True

    run("link", "uninstall")

    assert (home / ".testrc").is_symlink()
    assert (backup / ".testrc").exists()


def test_the_link_of_every_application(home):
    """The link command links the config of Mackeep and the other ones."""
    backup = setup(home, files=())
    (backup / ".mackeep.cfg").write_text(
        MAIN_CONFIG.format(storage=home / "storage"),
    )

    run("link")

    # The config of Mackeep is linked first, the other ones are linked
    # with the config that was restored.
    assert (home / ".mackeep.cfg").is_symlink()
    assert os.path.samefile(home / ".mackeep.cfg", backup / ".mackeep.cfg")


def test_the_link_of_an_unknown_application_fails(home):
    """The link command fails when the application is not supported."""
    setup(home)

    with pytest.raises(SystemExit):
        run("link", "unknown-app")


def test_the_json_link_install_is_not_supported(home, capsys):
    """The JSON mode does not support the link commands."""
    setup(home)

    data, code = run_json(capsys, "link", "install")

    assert code == 1
    assert data["error"]["code"] == "error"
    assert "not supported" in data["error"]["message"]
