"""Backup reconciliation preserves data when its settings disappear."""

import io
import json
from pathlib import Path
from unittest.mock import patch

import pytest

from mackeep.projects import ProjectStore
from mackeep_cli.summary import BackupSummary
from tests.test_audit_regressions import definition, run, setup


def test_project_save_keeps_backup_without_moving_live_file(home):
    store = ProjectStore(str(home / ".mackeep.cfg"))
    value = {"name": "Example", "root": str(home / "project"), "files": []}
    store.update(value)
    original = store.path.read_bytes()
    value = store.load()[0]
    value["name"] = "Renamed"
    with (
        patch("mackeep.projects.os.replace", side_effect=OSError("interrupted")),
        pytest.raises(OSError, match="interrupted"),
    ):
        store.update(value)
    assert store.path.read_bytes() == original
    assert Path(str(store.path) + ".bak").read_bytes() == original


def test_global_backup_removes_deselected_owner_and_unindexed_files(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    (backup / "untracked").write_text("keep")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    assert run("--force", "backup") == 0
    assert not (backup / "app").exists()
    assert not (backup / "untracked").exists()


def test_full_scan_removes_unindexed_trees_and_links_without_following_them(home):
    backup = setup(home)
    (home / "app").write_text("current")
    assert run("--force", "backup") == 0
    (backup / "old/nested").mkdir(parents=True)
    (backup / "old/nested/file").write_text("obsolete")
    (backup / "empty").mkdir()
    outside = home / "outside"
    outside.mkdir()
    (outside / "file").write_text("safe")
    (backup / "link").symlink_to(outside, target_is_directory=True)
    assert run("--force", "backup") == 0
    assert not (backup / "old").exists()
    assert not (backup / "empty").exists()
    assert not (backup / "link").is_symlink()
    assert (outside / "file").read_text() == "safe"
    assert (backup / "app").read_text() == "current"


def test_full_scan_keeps_disabled_projects_and_recovery_data(home):
    backup = setup(home)
    (home / "app").write_text("current")
    assert run("--force", "backup") == 0
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.path.write_text("[]\n")
    (backup / "Project/Legacy").mkdir(parents=True)
    (backup / "Project/Legacy/file").write_text("protected")
    (backup / ".mackeep-recovery").mkdir()
    (backup / ".mackeep-recovery/previous").write_text("recovery")
    assert run("--force", "backup") == 0
    assert (backup / "Project/Legacy/file").read_text() == "protected"
    assert (backup / ".mackeep-recovery/previous").read_text() == "recovery"


@pytest.mark.parametrize("summary", [False, True])
def test_missing_project_file_preserves_snapshot_and_reports_error(home, capsys, summary):
    backup = setup(home, extra="[projects]\nenabled = true\n")
    (home / "app").write_text("app")
    root = home / "project"
    root.mkdir()
    (root / "file").write_text("project")
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.update({"name": "Example", "root": str(root), "files": ["file"]})
    assert run("--force", "backup") == 0
    store.path.unlink()
    capsys.readouterr()
    flags = ("--summary",) if summary else ()
    assert run("--force", "backup", *flags) == 1
    output = capsys.readouterr()
    assert "Missing settings file" in output.out + output.err
    assert str(store.path) in output.out + output.err
    assert (backup / "Project/Example/file").read_text() == "project"
    assert not store.path.exists()


def test_missing_main_config_is_not_recreated(home, capsys):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    config = home / ".mackeep.cfg"
    config.unlink()
    capsys.readouterr()
    assert run("--force", "backup", "--summary") == 1
    output = capsys.readouterr()
    assert "Missing settings file" in output.out + output.err
    assert not config.exists()
    assert (backup / "app").read_text() == "old"


def test_empty_project_list_removes_old_snapshot(home):
    backup = setup(home, extra="[projects]\nenabled = true\n")
    root = home / "project"
    root.mkdir()
    (root / "file").write_text("project")
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.update({"name": "Example", "root": str(root), "files": ["file"]})
    assert run("--force", "backup") == 0
    store.path.write_text(json.dumps([]))
    assert run("--force", "backup") == 0
    assert not (backup / "Project").exists()


def test_failed_backup_does_not_clean_deselected_owner(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    definition(home, "other", name="other")
    (home / "other").write_text("new")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\nother\n"))
    with patch("mackeep.application.utils.copy", side_effect=PermissionError("blocked")):
        assert run("--force", "backup") == 1
    assert (backup / "app").read_text() == "old"


def test_shared_backup_survives_removing_one_owner(home):
    backup = setup(home)
    definition(home, "app", name="other")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text() + "other\n")
    (home / "app").write_text("shared")
    assert run("--force", "backup") == 0
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    assert run("--force", "backup") == 0
    assert (backup / "app").read_text() == "shared"


def test_disabling_projects_tab_retains_project_backups(home):
    backup = setup(home, extra="[projects]\nenabled = true\n")
    root = home / "project"
    root.mkdir()
    (root / "file").write_text("project")
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.update({"name": "Example", "root": str(root), "files": ["file"]})
    assert run("--force", "backup") == 0
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("enabled = true", "enabled = false"))
    assert run("--force", "backup") == 0
    assert (backup / "Project/Example/file").exists()


def test_cleanup_dry_run_does_not_remove_snapshots(home, capsys):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    capsys.readouterr()
    assert run("backup", "--json", "--dry-run") == 0
    plan = json.loads(capsys.readouterr().out)
    assert any(action["action"] == "stale_in_backup" for action in plan["actions"])
    assert (backup / "app").exists()


def test_cleanup_rolls_back_when_index_write_fails(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    (backup / "untracked/nested").mkdir(parents=True)
    (backup / "untracked/nested/file").write_text("restore on failure")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    import os

    replace = os.replace

    def fail_index(source, destination):
        if str(destination).endswith("owners.json") and str(source).endswith("/new"):
            raise OSError("index blocked")
        return replace(source, destination)

    with patch("mackeep.transaction.os.replace", side_effect=fail_index):
        assert run("--force", "backup") == 1
    assert (backup / "app").read_text() == "old"
    assert (backup / "untracked/nested/file").read_text() == "restore on failure"


def test_settings_warning_is_red_and_follows_table():
    output = io.StringIO()
    errors = io.StringIO()
    summary = BackupSummary()
    summary("error", {"app": "Settings", "message": "Missing settings file: example"})
    with (
        patch("sys.stdout", output),
        patch("sys.stderr", errors),
        patch.object(errors, "isatty", return_value=True),
    ):
        summary.display()
    assert output.getvalue().rstrip().endswith("+------------------------+----------+")
    assert "\033[31mWarning: Missing settings file: example\033[0m" in errors.getvalue()


def test_missing_project_settings_is_a_json_error(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (backup / "Project").mkdir()
    capsys.readouterr()
    assert run("--force", "backup", "--json") == 1
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert any(
        event.get("event") == "error" and "Missing settings file" in event["message"]
        for event in events
    )


def test_named_backup_does_not_clean_other_owners(home):
    backup = setup(home)
    definition(home, "other", name="other")
    (home / "app").write_text("app")
    (home / "other").write_text("other")
    assert run("--force", "backup", "other") == 0
    assert run("--force", "backup", "audit") == 0
    assert (backup / "other").read_text() == "other"


def test_settings_changed_during_copy_prevents_post_cleanup(home, capsys):
    from mackeep import utils

    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    definition(home, "other", name="other")
    (home / "other").write_text("new")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\nother\n"))
    copy = utils.copy

    def change_settings(source, destination, **kwargs):
        copy(source, destination, **kwargs)
        config.write_text(config.read_text() + "# changed during backup\n")

    with patch("mackeep.application.utils.copy", side_effect=change_settings):
        assert run("--force", "backup") == 1
    assert (backup / "app").read_text() == "old"
    output = capsys.readouterr()
    assert "Settings changed during backup" in output.err


def test_force_no_prevents_post_cleanup(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    assert run("--force-no", "backup") == 1
    assert (backup / "app").read_text() == "old"


def test_missing_project_settings_keeps_its_own_backup_copy(home):
    backup = setup(home, files=".mackeep.cfg.projects.json")
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.update({"name": "Example", "root": str(home), "files": []})
    assert run("--force", "backup") == 0
    previous = (backup / store.path.name).read_bytes()
    store.path.unlink()
    assert run("--force", "backup") == 1
    assert (backup / store.path.name).read_bytes() == previous


def test_dry_run_uses_current_manifest_even_without_previous_index(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (home / "app").write_text("current")
    (backup / "app").write_text("previous")
    (backup / "untracked").write_text("obsolete")
    capsys.readouterr()
    assert run("--json", "--dry-run", "backup") == 0
    plan = json.loads(capsys.readouterr().out)
    removals = [
        action["dst"] for action in plan["actions"] if action["action"] == "stale_in_backup"
    ]
    assert str(backup / "untracked") in removals
    assert str(backup / "app") not in removals
    assert (backup / "untracked").exists()
    assert not (backup / ".mackeep-state").exists()
    assert run("--force", "backup") == 0
    assert not (backup / "untracked").exists()
    assert (backup / "app").read_text() == "current"


def test_scan_failure_retains_unindexed_data(home):
    backup = setup(home)
    (home / "app").write_text("current")
    assert run("--force", "backup") == 0
    (backup / "untracked").write_text("keep on error")
    with patch("mackeep.cleanup._obsolete_paths", side_effect=PermissionError("scan blocked")):
        assert run("--force", "backup") == 1
    assert (backup / "untracked").read_text() == "keep on error"
