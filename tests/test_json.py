"""Tests for the machine-readable JSON output."""

import json
import os
import shutil
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.main import main

# The number of directories where the custom application configs are looked up
CUSTOM_APPS_DIRS_COUNT = 2

# The counters of the events of a backup
ONE_FILE = 1
NO_FILE = 0
TWO_BYTES = 2
FIVE_BYTES = 5

# The number of files of a test tree
FIVE_FILES = 5

# The sizes of the test plans
TWO_ACTIONS = 2
THREE_ACTIONS = 3


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


def write_app_config(home, body, name="test-app"):
    """Write a custom application config file."""
    apps_dir = home / ".mackeep"
    apps_dir.mkdir(exist_ok=True)
    (apps_dir / f"{name}.cfg").write_text(body)


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


def test_the_json_backup_counters_are_per_application(home, capsys):
    """The counters of the done event are the ones of the application."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".first\n"
        "\n"
        "[exclude]\n"
        ".first/skipped.log\n",
    )
    write_app_config(
        home,
        "[application]\n"
        "name = Test App 2\n"
        "\n"
        "[configuration_files]\n"
        ".second\n",
        name="test-app-2",
    )

    # Both applications are synced
    (home / ".mackeep.cfg").write_text(
        (home / ".mackeep.cfg").read_text() + "test-app-2\n",
    )

    first = home / ".first"
    first.mkdir()
    (first / "keep.txt").write_text("12345")
    (first / "skipped.log").write_text("nope")

    second = home / ".second"
    second.mkdir()
    (second / "other.txt").write_text("ab")

    run("--json", "--force", "backup")
    captured = capsys.readouterr()

    events = [json.loads(line) for line in captured.out.splitlines() if line]
    done = {event["app"]: event for event in events if event["event"] == "done"}

    assert done["test-app"]["files"] == ONE_FILE
    assert done["test-app"]["bytes"] == FIVE_BYTES
    assert done["test-app"]["skipped"] == ONE_FILE

    assert done["test-app-2"]["files"] == ONE_FILE
    assert done["test-app-2"]["bytes"] == TWO_BYTES
    assert done["test-app-2"]["skipped"] == NO_FILE


def test_the_json_backup_dry_run_does_not_need_the_backup_folder(home, capsys):
    """A dry-run works before the backup folder exists, and creates nothing."""
    shutil.rmtree(home / "storage" / "Mackeep")
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    data, code = run_json(capsys, "backup", "--dry-run")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["actions"][0]["action"] == "copy"
    assert not (home / "storage" / "Mackeep").exists()


def test_the_json_restore_dry_run_does_not_need_the_backup_folder(home, capsys):
    """A dry-run of the restore works before the backup folder exists."""
    shutil.rmtree(home / "storage" / "Mackeep")
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )

    data, code = run_json(capsys, "restore", "--dry-run")

    assert code == 0
    assert data["schema_version"] == 1
    assert data["actions"][0]["action"] == "skip_missing"


def test_the_backup_dry_run_does_not_create_the_backup_folder(home, capsys):
    """A dry-run does not create the backup folder."""
    shutil.rmtree(home / "storage" / "Mackeep")
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n",
    )
    (home / ".testrc").write_text("config")

    run("backup", "--dry-run")

    assert not (home / "storage" / "Mackeep").exists()


def test_the_json_dry_run_detail_files(home, capsys):
    """The files detail level describes every file."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n",
    )
    tree = home / ".tree"
    (tree / "sub" / "deep").mkdir(parents=True)
    (tree / "keep.txt").write_text("keep")
    (tree / "sub" / "middle.txt").write_text("middle")
    (tree / "sub" / "deep" / "leaf.txt").write_text("leaf")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    assert data["schema_version"] == 1

    copied = [a for a in data["actions"] if a["action"] == "copy"]
    assert len(copied) == THREE_ACTIONS
    assert {os.path.basename(a["src"]) for a in copied} == {
        "keep.txt",
        "middle.txt",
        "leaf.txt",
    }
    for action in copied:
        assert action["size_bytes"] > 0
        assert action["app"] == "test-app"

    assert data["summary"]["files"] == THREE_ACTIONS
    assert data["summary"]["total_actions"] == THREE_ACTIONS


def test_the_json_dry_run_detail_files_reports_the_reason(home, capsys):
    """The excluded files tell which pattern excluded them."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n"
        "\n"
        "[exclude]\n"
        ".tree/*.tmp\n"
        "**/secret.key\n",
    )
    tree = home / ".tree"
    (tree / "sub").mkdir(parents=True)
    (tree / "drop.tmp").write_text("tmp")
    (tree / "sub" / "secret.key").write_text("key")
    (tree / "keep.txt").write_text("keep")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    skipped = [a for a in data["actions"] if a["action"] == "skip_excluded"]
    assert len(skipped) == TWO_ACTIONS

    reasons = {os.path.basename(a["src"]): a["reason"] for a in skipped}
    assert reasons["drop.tmp"]["pattern"] == ".tree/*.tmp"
    assert reasons["secret.key"]["pattern"] == "**/secret.key"
    for reason in reasons.values():
        assert reason["section"] == "exclude"
        assert reason["file"] == str(home / ".mackeep" / "test-app.cfg")


def test_the_json_dry_run_detail_files_keeps_the_negated_files(home, capsys):
    """A negated pattern gives its files back."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n"
        "\n"
        "[exclude]\n"
        "*.tmp\n"
        "!keep.tmp\n",
    )
    tree = home / ".tree"
    tree.mkdir()
    (tree / "keep.tmp").write_text("keep")
    (tree / "drop.tmp").write_text("drop")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    copied = [a for a in data["actions"] if a["action"] == "copy"]
    assert len(copied) == 1
    assert os.path.basename(copied[0]["src"]) == "keep.tmp"

    skipped = [a for a in data["actions"] if a["action"] == "skip_excluded"]
    assert len(skipped) == 1
    assert os.path.basename(skipped[0]["src"]) == "drop.tmp"


def test_the_json_dry_run_detail_files_does_not_expand_the_excluded_dirs(
    home, capsys,
):
    """An excluded directory is a single entry, its content is not walked."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n"
        "\n"
        "[exclude]\n"
        ".tree/cache\n",
    )
    tree = home / ".tree"
    (tree / "cache").mkdir(parents=True)
    (tree / "cache" / "data.bin").write_text("data")
    (tree / "keep.txt").write_text("keep")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    skipped = [a for a in data["actions"] if a["action"] == "skip_excluded"]
    assert len(skipped) == 1
    assert skipped[0]["src"].endswith("cache")
    assert not any("data.bin" in a["src"] for a in data["actions"])


def test_the_json_dry_run_detail_files_reports_the_conflicts(home, capsys):
    """A file that already exists is a conflict, and not a copy."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n",
    )
    tree = home / ".tree"
    tree.mkdir()
    (tree / "keep.txt").write_text("keep")

    # The file is already in the backup
    backup = home / "storage" / "Mackeep" / ".tree"
    backup.mkdir(parents=True)
    (backup / "keep.txt").write_text("old")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    assert len(data["actions"]) == 1
    action = data["actions"][0]
    assert action["action"] == "conflict"
    assert action["would_overwrite"] is True
    assert action["size_bytes"] == len("keep")


def test_the_json_dry_run_detail_files_reports_the_stale_files(home, capsys):
    """The files of the backup that are now excluded are reported."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n"
        "\n"
        "[exclude]\n"
        ".tree/old.log\n",
    )
    tree = home / ".tree"
    tree.mkdir()
    (tree / "keep.txt").write_text("keep")

    backup = home / "storage" / "Mackeep" / ".tree"
    backup.mkdir(parents=True)
    (backup / "old.log").write_text("stale")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    stale = [a for a in data["actions"] if a["action"] == "stale_in_backup"]
    assert len(stale) == 1
    assert stale[0]["src"].endswith("old.log")


def test_the_json_dry_run_truncates_the_actions(home, capsys):
    """The plan is truncated, but the summary is computed on the whole plan."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n",
    )
    tree = home / ".tree"
    tree.mkdir()
    for index in range(FIVE_FILES):
        (tree / f"file{index}.txt").write_text("x")

    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "files")

    assert code == 0
    assert len(data["actions"]) == FIVE_FILES
    assert "truncated" not in data["summary"]

    data, code = run_json(
        capsys, "backup", "--dry-run", "--detail", "files", "--max-actions", "2",
    )

    assert code == 0
    assert len(data["actions"]) == TWO_ACTIONS
    assert data["summary"]["truncated"] is True
    assert data["summary"]["limit"] == TWO_ACTIONS
    # The summary is computed on the whole plan
    assert data["summary"]["total_actions"] == FIVE_FILES
    assert data["summary"]["files"] == FIVE_FILES


def test_the_json_dry_run_entries_stays_the_same(home, capsys):
    """The entries detail level keeps the previous behavior."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n",
    )
    tree = home / ".tree"
    (tree / "sub").mkdir(parents=True)
    (tree / "keep.txt").write_text("keep")
    (tree / "sub" / "leaf.txt").write_text("leaf")

    data, code = run_json(capsys, "backup", "--dry-run")

    assert code == 0
    # One entry per top level path, not per file
    assert len(data["actions"]) == 1
    action = data["actions"][0]
    assert action["action"] == "copy"
    assert action["src"].endswith(".tree")
    assert action["size_bytes"] == len("keep") + len("leaf")


def test_the_json_dry_run_detail_entries_is_the_default(home, capsys):
    """The default detail level is entries."""
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".tree\n",
    )
    tree = home / ".tree"
    tree.mkdir()
    (tree / "keep.txt").write_text("keep")

    default, _ = run_json(capsys, "backup", "--dry-run")
    explicit, _ = run_json(capsys, "backup", "--dry-run", "--detail", "entries")

    assert default == explicit


def test_an_unknown_detail_level_is_an_error(home, capsys):
    """An unknown detail level is rejected."""
    data, code = run_json(capsys, "backup", "--dry-run", "--detail", "nope")

    assert code != 0
    assert data["error"]["code"] == "error"
