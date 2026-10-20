"""Tests for the backward compatibility with the Mackup config files."""

import json
import os
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.appsdb import ApplicationsDatabase
from mackeep.config import Config
from mackeep_cli.main import main

# The content of a config file of an application
APP_CONFIG = (
    "[application]\n"
    "name = Test App\n"
    "\n"
    "[configuration_files]\n"
    ".testrc\n"
)

# The number of files of a migration
TWO_FILES = 2

# The content of the main config file
MAIN_CONFIG = (
    "[storage]\n"
    "engine = file_system\n"
    "path = {storage}\n"
    "\n"
    "[applications_to_sync]\n"
    "test-app\n"
)


@pytest.fixture(autouse=True)
def clear_warnings():
    """The legacy warnings are kept in a module level list."""
    utils.LEGACY_WARNINGS.clear()
    yield
    utils.LEGACY_WARNINGS.clear()


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Set up a temporary home directory."""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".config"))
    monkeypatch.delenv("MACKEEP_CONFIG", raising=False)

    utils.FORCE_YES = True
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = True

    storage = tmp_path / "storage"
    storage.mkdir(exist_ok=True)

    yield tmp_path

    utils.FORCE_YES = False
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = False


def write_config(home, path, content=MAIN_CONFIG):
    """Write a config file, creating its directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.format(storage=home / "storage"))


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


def test_the_new_config_file_has_the_priority(home):
    """The Mackeep config file wins over the legacy one."""
    write_config(home, home / ".mackeep.cfg")
    write_config(home, home / ".mackup.cfg")

    config = Config()

    assert config.config_path == str(home / ".mackeep.cfg")
    assert config.is_legacy is False


def test_the_xdg_config_file_is_used(home):
    """The XDG config file is used when there is no config in the home."""
    write_config(home, home / ".config" / "mackeep" / "mackeep.cfg")

    config = Config()

    assert config.config_path == str(
        home / ".config" / "mackeep" / "mackeep.cfg",
    )
    assert config.is_legacy is False


def test_the_legacy_config_file_is_used(home):
    """The legacy config file is used when there is nothing else."""
    write_config(home, home / ".mackup.cfg")

    config = Config()

    assert config.config_path == str(home / ".mackup.cfg")
    assert config.is_legacy is True


def test_the_legacy_xdg_config_file_is_used(home):
    """The legacy XDG config file is the last resort."""
    write_config(home, home / ".config" / "mackup" / "mackup.cfg")

    config = Config()

    assert config.config_path == str(
        home / ".config" / "mackup" / "mackup.cfg",
    )
    assert config.is_legacy is True


def test_the_config_file_option_has_the_priority(home):
    """The --config-file option works as before."""
    write_config(home, home / ".mackeep.cfg")
    write_config(home, home / "custom.cfg")

    config = Config("custom.cfg")

    assert config.config_path == str(home / "custom.cfg")
    assert config.is_legacy is False


def test_the_mackeep_apps_dir_has_the_priority(home):
    """The Mackeep applications directory wins over the legacy one."""
    write_config(home, home / ".mackeep" / "test-app.cfg", APP_CONFIG)
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    db = ApplicationsDatabase()

    assert db.get_config_file("test-app") == str(
        home / ".mackeep" / "test-app.cfg",
    )


def test_the_legacy_apps_dir_is_read(home):
    """The legacy applications directory is read when it is the only one."""
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    db = ApplicationsDatabase()

    assert db.get_config_file("test-app") == str(
        home / ".mackup" / "test-app.cfg",
    )


def test_the_xdg_apps_dir_has_the_priority_over_the_legacy_one(home):
    """The XDG Mackeep directory wins over the legacy home one."""
    write_config(
        home, home / ".config" / "mackeep" / "applications" / "test-app.cfg",
        APP_CONFIG,
    )
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    db = ApplicationsDatabase()

    assert db.get_config_file("test-app") == str(
        home / ".config" / "mackeep" / "applications" / "test-app.cfg",
    )


def test_the_legacy_storage_folder_is_used(home):
    """The legacy storage folder is used when the new one does not exist."""
    write_config(home, home / ".mackeep.cfg")
    (home / "storage" / "Mackup").mkdir(parents=True)

    config = Config()

    assert config.directory == "Mackup"
    assert config.using_legacy_directory is True
    assert config.fullpath == str(home / "storage" / "Mackup")


def test_the_new_storage_folder_has_the_priority(home):
    """The new storage folder is used when it exists."""
    write_config(home, home / ".mackeep.cfg")
    (home / "storage" / "Mackeep").mkdir(parents=True)
    (home / "storage" / "Mackup").mkdir(parents=True)

    config = Config()

    assert config.directory == "Mackeep"
    assert config.using_legacy_directory is False


def test_an_explicit_storage_folder_is_never_replaced(home):
    """An explicit directory is never replaced by the legacy one."""
    write_config(
        home,
        home / ".mackeep.cfg",
        "[storage]\n"
        "engine = file_system\n"
        "path = {storage}\n"
        "directory = Other\n",
    )
    (home / "storage" / "Mackup").mkdir(parents=True)

    config = Config()

    assert config.directory == "Other"
    assert config.using_legacy_directory is False


def test_a_warning_is_printed_once(home, capsys):
    """The legacy paths are warned about once per run."""
    write_config(home, home / ".mackup.cfg")
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    run("--json", "config")
    captured = capsys.readouterr()

    assert "legacy" in captured.err.lower()
    assert captured.err.count("Warning:") == 1


def test_no_warning_without_the_legacy_paths(home, capsys):
    """Nothing is warned about when the legacy paths are not used."""
    write_config(home, home / ".mackeep.cfg")

    run("--json", "config")
    captured = capsys.readouterr()

    assert "legacy" not in captured.err.lower()


def test_the_json_config_holds_the_legacy_paths(home, capsys):
    """The JSON config tells which legacy paths are used."""
    write_config(home, home / ".mackup.cfg")
    (home / "storage" / "Mackup").mkdir(parents=True)

    data, code = run_json(capsys, "config")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["config_file_is_legacy"] is True
    assert data["legacy_custom_apps_dirs"] == [
        str(home / ".mackup"),
        str(home / ".config" / "mackup" / "applications"),
    ]
    assert data["storage"]["using_legacy_directory"] is True


def test_the_json_config_of_a_new_setup(home, capsys):
    """The JSON config of a new setup does not use the legacy paths."""
    write_config(home, home / ".mackeep.cfg")

    data, code = run_json(capsys, "config")

    assert code == 0
    assert data["config_file_is_legacy"] is False
    assert data["storage"]["using_legacy_directory"] is False


def test_migrate_copies_the_legacy_files(home, capsys):
    """The migrate command copies the legacy files to their new location."""
    write_config(home, home / ".mackup.cfg")
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    data, code = run_json(capsys, "migrate")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["summary"]["copied"] == TWO_FILES
    assert data["summary"]["dry_run"] is False

    assert (home / ".mackeep.cfg").exists()
    assert (home / ".mackeep" / "test-app.cfg").exists()
    # The old files are kept
    assert (home / ".mackup.cfg").exists()
    assert (home / ".mackup" / "test-app.cfg").exists()


def test_migrate_does_not_overwrite(home, capsys):
    """The migrate command never overwrites an existing file."""
    write_config(home, home / ".mackup.cfg", MAIN_CONFIG + "# legacy\n")
    write_config(home, home / ".mackeep.cfg", MAIN_CONFIG + "# new\n")

    data, code = run_json(capsys, "migrate")

    assert code == 0
    assert data["summary"]["copied"] == 0
    assert data["summary"]["skipped"] == 1
    assert (home / ".mackeep.cfg").read_text().endswith("# new\n")


def test_migrate_is_idempotent(home, capsys):
    """Running the migrate command twice does not change anything."""
    write_config(home, home / ".mackup.cfg")
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    run_json(capsys, "migrate")
    data, code = run_json(capsys, "migrate")

    assert code == 0
    assert data["summary"]["copied"] == 0
    assert data["summary"]["skipped"] == TWO_FILES


def test_migrate_dry_run_copies_nothing(home, capsys):
    """The dry-run of the migrate command copies nothing."""
    write_config(home, home / ".mackup.cfg")
    write_config(home, home / ".mackup" / "test-app.cfg", APP_CONFIG)

    data, code = run_json(capsys, "migrate", "--dry-run")

    assert code == 0
    assert data["summary"]["copied"] == 0
    assert data["summary"]["dry_run"] is True
    assert len(data["actions"]) == TWO_FILES

    assert not (home / ".mackeep.cfg").exists()
    assert not (home / ".mackeep" / "test-app.cfg").exists()


def test_migrate_renames_the_application_of_mackup(home, capsys):
    """The application of Mackup itself is renamed."""
    write_config(home, home / ".mackup.cfg")
    write_config(
        home,
        home / ".mackup" / "mackup.cfg",
        "[application]\nname = Mackup\n\n[configuration_files]\n.mackup.cfg\n",
    )

    data, code = run_json(capsys, "migrate")

    assert code == 0
    destinations = [action["dst"] for action in data["actions"]]
    assert str(home / ".mackeep" / "mackeep.cfg") in destinations
    assert str(home / ".mackeep" / "mackup.cfg") not in destinations


def test_migrate_without_the_legacy_files(home, capsys):
    """There is nothing to migrate when there is no legacy file."""
    write_config(home, home / ".mackeep.cfg")

    data, code = run_json(capsys, "migrate")

    assert code == 0
    assert data["actions"] == []
    assert data["summary"]["total_actions"] == 0


def test_migrate_keeps_the_legacy_files_in_place(home, capsys):
    """The migrate command does not move nor delete the legacy files."""
    write_config(home, home / ".mackup.cfg")

    run_json(capsys, "migrate")

    assert os.path.isfile(home / ".mackup.cfg")
