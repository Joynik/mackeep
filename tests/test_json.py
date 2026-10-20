"""Tests for the machine-readable JSON output."""

import json
import os
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.main import main

# The number of directories where the custom application configs are looked up
CUSTOM_APPS_DIRS_COUNT = 2


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Set up a temporary home directory with a Mackeep config file."""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".config"))
    monkeypatch.delenv("MACKEEP_CONFIG", raising=False)

    utils.FORCE_YES = False
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = True

    storage = tmp_path / "storage"
    storage.mkdir(exist_ok=True)
    (storage / "Mackeep").mkdir(exist_ok=True)
    (tmp_path / ".mackeep.cfg").write_text(
        "[storage]\n"
        "engine = file_system\n"
        f"path = {storage}\n"
        "directory = Mackeep\n"
        "\n"
        "[applications_to_sync]\n"
        "test-app\n",
    )

    yield tmp_path

    utils.FORCE_YES = False
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = False


def write_app_config(home, body):
    """Write a custom application config file."""
    apps_dir = home / ".mackeep"
    apps_dir.mkdir(exist_ok=True)
    (apps_dir / "test-app.cfg").write_text(body)


def run(*args):
    """Run the Mackeep command line with the given arguments."""
    with patch("sys.argv", ["mackeep", *args]):
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


def test_the_version_is_shown(capsys):
    """mackeep --version shows the version of Mackeep."""
    with pytest.raises(SystemExit), patch("sys.argv", ["mackeep", "--version"]):
        main()

    assert "Mackeep" in capsys.readouterr().out


def test_the_json_config(home, capsys):
    """mackeep --json config describes the configuration of Mackeep."""
    data, code = run_json(capsys, "config")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["version"]
    assert data["config_file"] == str(home / ".mackeep.cfg")
    assert len(data["custom_apps_dirs"]) == CUSTOM_APPS_DIRS_COUNT
    assert data["storage"]["engine"] == "file_system"
    assert data["storage"]["directory"] == "Mackeep"
    assert data["storage"]["resolved_backup_dir"] == str(
        home / "storage" / "Mackeep",
    )
    assert data["storage"]["exists"] is True
    assert data["apps_to_sync"] == ["test-app"]
    assert data["apps_to_ignore"] == []
    assert data["global_exclude"] == []


def test_the_json_config_of_a_missing_backup_dir(home, capsys):
    """The JSON config tells if the backup directory exists."""
    (home / "storage" / "Mackeep").rmdir()

    data, code = run_json(capsys, "config")

    assert code == 0
    assert data["storage"]["exists"] is False


def test_the_json_config_holds_the_global_exclusions(home, capsys):
    """The global exclusions are part of the JSON config."""
    (home / ".mackeep.cfg").write_text(
        (home / ".mackeep.cfg").read_text() + "\n[exclude]\n**/.DS_Store\n",
    )

    data, code = run_json(capsys, "config")

    assert code == 0
    assert data["global_exclude"] == ["**/.DS_Store"]


def test_the_json_list(home, capsys):
    """mackeep --json list describes every supported application."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )

    data, code = run_json(capsys, "list")

    assert code == 0
    assert isinstance(data, list)

    apps = {app["name"]: app for app in data}
    assert "test-app" in apps
    assert "vim" in apps

    app = apps["test-app"]
    assert app["schema_version"] == 1
    assert app["display_name"] == "Test App"
    assert app["source"] == "custom"
    assert app["cfg_path"] == str(home / ".mackeep" / "test-app.cfg")
    assert app["exclude"] == [".testdir/skip.log"]
    assert app["xdg_exclude"] == []
    assert app["files"][0]["path"] == ".testdir"

    assert apps["vim"]["source"] == "builtin"


def test_the_json_show(home, capsys):
    """mackeep --json show describes an application and its paths."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        ".testrc\n"
        "\n"
        "[xdg_configuration_files]\n"
        "test-app/config\n",
    )
    (home / ".testdir").mkdir()
    (home / ".testrc").write_text("config")

    data, code = run_json(capsys, "show", "test-app")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["name"] == "test-app"
    assert data["display_name"] == "Test App"

    files = {file["path"]: file for file in data["files"]}
    assert files[".testdir"]["exists"] is True
    assert files[".testdir"]["is_dir"] is True
    assert files[".testrc"]["exists"] is True
    assert files[".testrc"]["is_dir"] is False

    xdg_files = {file["path"]: file for file in data["xdg_files"]}
    assert xdg_files["test-app/config"]["exists"] is False
    assert xdg_files["test-app/config"]["is_dir"] is False


def test_the_json_show_of_an_unknown_app(home, capsys):
    """An unknown application is an error."""
    data, code = run_json(capsys, "show", "not-an-app")

    assert code != 0
    assert data["schema_version"] == 1
    assert data["error"]["code"] == "unsupported_application"
    assert "not-an-app" in data["error"]["message"]


def test_the_json_backup_dry_run(home, capsys):
    """mackeep --json backup --dry-run describes the planned operations."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )
    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")
    (testdir / "skip.log").write_text("skip")

    data, code = run_json(capsys, "--force", "backup", "--dry-run")

    assert code == 0
    assert data["schema_version"] == 1
    assert isinstance(data["actions"], list)
    assert data["summary"]["apps"] == ["test-app"]
    assert data["summary"]["actions"]["copy"] >= 1
    assert data["summary"]["actions"]["skip_excluded"] == 1

    actions = {action["action"] for action in data["actions"]}
    assert "copy" in actions
    assert "skip_excluded" in actions

    for action in data["actions"]:
        assert action["app"] == "test-app"
        assert "src" in action
        assert "dst" in action


def test_the_json_backup_dry_run_does_not_copy_anything(home, capsys):
    """The dry-run does not copy anything."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    run_json(capsys, "--force", "backup", "--dry-run")

    assert not (home / "storage" / "Mackeep" / ".testrc").exists()


def test_the_json_backup_streams_the_events(home, capsys):
    """mackeep --json backup streams the events as NDJSON."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    run("--json", "--force", "backup")
    captured = capsys.readouterr()

    events = [json.loads(line) for line in captured.out.splitlines() if line]
    assert events
    for event in events:
        assert event["schema_version"] == 1

    kinds = [event["event"] for event in events]
    assert kinds[0] == "start"
    assert "file" in kinds
    assert kinds[-1] == "done"

    assert (home / "storage" / "Mackeep" / ".testrc").exists()


def test_the_json_backup_reports_the_excluded_files(home, capsys):
    """The excluded files are not copied but are reported."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )
    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")
    (testdir / "skip.log").write_text("skip")

    run("--json", "--force", "backup")
    captured = capsys.readouterr()

    events = [json.loads(line) for line in captured.out.splitlines() if line]
    skipped = [event for event in events if event["action"] == "skip_excluded"]
    assert len(skipped) == 1
    assert skipped[0]["src"].endswith("skip.log")

    backup = home / "storage" / "Mackeep" / ".testdir"
    assert (backup / "keep.txt").exists()
    assert not (backup / "skip.log").exists()


def test_the_json_restore_dry_run(home, capsys):
    """mackeep --json restore --dry-run describes the planned operations."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )
    backup = home / "storage" / "Mackeep" / ".testdir"
    backup.mkdir(parents=True)
    (backup / "keep.txt").write_text("keep")
    (backup / "skip.log").write_text("skip")

    data, code = run_json(capsys, "restore", "--dry-run")

    assert code == 0
    assert data["schema_version"] == 1
    actions = {action["action"] for action in data["actions"]}
    assert "skip_excluded" in actions
    assert not (home / ".testdir").exists()


def test_the_json_error(home, capsys):
    """An error is reported as a JSON document."""
    with pytest.raises(SystemExit) as context:
        run("--json", "backup", "not-an-app")

    captured = capsys.readouterr()
    data = json.loads(captured.out)

    assert context.value.code != 0
    assert data["schema_version"] == 1
    assert data["error"]["code"]
    assert data["error"]["message"]


def test_only_json_is_written_to_stdout(home, capsys):
    """In JSON mode, stdout only holds JSON."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    run("--json", "--force", "backup")
    captured = capsys.readouterr()

    # Every line of stdout is a JSON document
    for line in captured.out.splitlines():
        if line:
            json.loads(line)

    # The human-readable output went to stderr
    assert "Backing up" in captured.err


def test_the_human_output_is_not_impacted(home, capsys):
    """Without --json, the output is the same as before."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    run("backup")
    captured = capsys.readouterr()

    assert "Backing up .testrc ..." in captured.out
    assert captured.err == ""
    assert (home / "storage" / "Mackeep" / ".testrc").exists()


def test_the_json_link_is_not_supported(home, capsys):
    """The link commands are not supported in JSON mode."""
    data, code = run_json(capsys, "link", "install")

    assert code != 0
    assert data["schema_version"] == 1
    assert data["error"]["code"] == "error"
    assert "--json" in data["error"]["message"]


def test_the_config_command(home, capsys):
    """mackeep config shows the configuration of Mackeep."""
    run("config")
    captured = capsys.readouterr()

    assert "Config file:" in captured.out
    assert "Backup directory:" in captured.out
    assert "file_system" in captured.out


def test_the_json_show_of_a_builtin_app(home, capsys):
    """The applications of the database are described too."""
    data, code = run_json(capsys, "show", "vim")

    assert code == 0
    assert data["name"] == "vim"
    assert data["source"] == "builtin"
    assert data["cfg_path"].endswith("vim.cfg")
    assert os.path.isabs(data["cfg_path"])
