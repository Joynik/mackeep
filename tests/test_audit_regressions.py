"""Regression coverage for the agreed CLI audit fixes."""

import io
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from unittest.mock import patch

import pytest

from mackeep import migrate, utils
from mackeep.backupstate import BackupState
from mackeep.config import ConfigError
from mackeep.paths import entry_paths
from mackeep.transaction import Transaction
from mackeep_cli.main import _JsonReporter, main


def setup(home: Path, files: str = "app", extra: str = "") -> Path:
    """Create one custom application and explicit local storage."""
    (home / ".mackeep").mkdir(exist_ok=True)
    (home / ".mackeep.cfg").write_text(
        f"[storage]\nengine = file_system\npath = {home / 'storage'}\n"
        "[applications_to_sync]\naudit\n" + extra,
    )
    definition(home, files)
    return home / "storage" / "Mackeep"


def definition(home: Path, files: str, exclude: str = "", name: str = "audit") -> None:
    """Write the current application definition."""
    (home / ".mackeep" / f"{name}.cfg").write_text(
        f"[application]\nname = Audit\n[configuration_files]\n{files}\n"
        + (f"[exclude]\n{exclude}\n" if exclude else ""),
    )


def run(*args: str) -> int:
    """Run the real CLI and return its status."""
    with patch("sys.argv", ["mackeep-cli", *args]):
        try:
            main()
        except SystemExit as exc:
            return exc.code if isinstance(exc.code, int) else 1
    return 0


def test_backup_removes_excluded_and_removed_roots(home):
    backup = setup(home, "app\nold")
    (home / "app").mkdir()
    (home / "app/keep").write_text("new")
    (home / "app/cache").write_text("cache")
    (home / "old").write_text("old")
    assert run("--force", "backup") == 0
    definition(home, "app", "app/cache")
    assert run("--force", "backup") == 0
    assert (backup / "app/keep").read_text() == "new"
    assert not (backup / "app/cache").exists()
    assert not (backup / "old").exists()


def test_cleanup_keeps_shared_ownership(home):
    backup = setup(home, "shared")
    definition(home, "shared", name="other")
    (home / "shared").write_text("shared")
    assert run("--force", "backup", "audit") == 0
    assert run("--force", "backup", "other") == 0
    definition(home, "")
    assert run("--force", "backup", "audit") == 0
    assert (backup / "shared").read_text() == "shared"


def test_restore_preserves_excluded_local_files(home):
    backup = setup(home)
    definition(home, "app", "app/cache")
    (backup / "app").mkdir(parents=True)
    (backup / "app/keep").write_text("backup")
    (home / "app").mkdir()
    (home / "app/cache").write_text("local")
    assert run("--force", "restore") == 0
    assert (home / "app/cache").read_text() == "local"


@pytest.mark.parametrize("operation", ["backup", "restore"])
def test_copy_failure_keeps_previous_destination_and_fails(home, operation):
    backup = setup(home)
    backup.mkdir()
    (home / "app").write_text("home")
    (backup / "app").write_text("backup")
    destination = backup / "app" if operation == "backup" else home / "app"
    original = destination.read_text()
    with patch(
        "mackeep.application.utils.copy",
        side_effect=PermissionError("injected"),
    ):
        assert run("--force", operation) != 0
    assert destination.read_text() == original


def test_preflight_rejects_same_path_before_any_copy(home):
    setup(home)
    (home / "app").write_text("only copy")
    (home / ".mackeep.cfg").write_text(
        f"[storage]\nengine = file_system\npath = {home}\ndirectory = .\n"
        "[applications_to_sync]\naudit\n",
    )
    assert run("--force", "backup") != 0
    assert (home / "app").read_text() == "only copy"


def test_external_paths_are_disabled_by_default(home):
    backup = setup(home, "../outside")
    outside = home.parent / f"{home.name}-outside"
    # Keep the source outside HOME but within pytest's temporary directory.
    definition(home, f"../{outside.name}")
    outside.write_text("external")
    assert run("--force", "backup") != 0
    assert not (backup.parent / outside.name).exists()


def test_explicit_external_paths_round_trip(home):
    outside = home.parent / f"{home.name}-outside"
    backup = setup(home, str(outside), "[security]\nallow_external_paths = true\n")
    outside.write_text("external")
    assert run("--force", "backup") == 0
    assert not (backup.parent / outside.name).exists()
    outside.write_text("changed")
    assert run("--force", "restore") == 0
    assert outside.read_text() == "external"


def test_nested_links_are_preserved_without_following(home):
    backup = setup(home)
    app = home / "app"
    app.mkdir()
    (app / "broken").symlink_to("missing")
    (app / "cycle").symlink_to(".", target_is_directory=True)
    assert run("--json", "--dry-run", "backup") == 0
    assert run("--force", "backup") == 0
    assert (backup / "app/broken").is_symlink()
    assert os.readlink(backup / "app/cycle") == "."


def test_fresh_dry_run_does_not_initialize(home):
    assert run("--dry-run", "backup") != 0  # Storage has not been configured.
    assert not (home / ".mackeep.cfg").exists()
    assert not (home / ".mackeep").exists()


def test_first_normal_start_initializes_only_configuration(home):
    assert run("--json", "config") == 0
    assert (home / ".mackeep.cfg").is_file()
    assert (home / ".mackeep").is_dir()
    assert not (home / "Mackeep").exists()


def test_link_install_dry_run_does_not_create_backup(home):
    backup = setup(home)
    (home / "app").write_text("value")
    assert run("--force", "--dry-run", "link", "install") == 0
    assert not backup.exists()


@pytest.mark.parametrize("args", [("config",), ("--unknown-option",)])
def test_json_errors_are_structured(home, capsys, args):
    setup(home)
    (home / ".mackeep.cfg").write_text("malformed INI")
    assert run("--json", *args) != 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["error"]["message"]


def test_round_trip_restores_bytes_execution_and_time(home):
    setup(home)
    file = home / "app"
    file.write_text("#!/bin/sh\n")
    file.chmod(0o755)
    original_time = 1_600_000_000
    os.utime(file, (original_time, original_time))
    assert run("--force", "backup") == 0
    file.write_bytes(b"changed local content")
    file.chmod(0o600)
    os.utime(file, (original_time + 100, original_time + 100))
    assert run("--force", "restore") == 0
    assert file.read_bytes() == b"#!/bin/sh\n"
    private_executable = 0o700
    assert file.stat().st_mode & 0o777 == private_executable
    assert int(file.stat().st_mtime) == original_time


def test_migration_does_not_follow_dangling_destination(home):
    target = home / "target"
    (home / ".mackeep.cfg").symlink_to(target)
    (home / ".mackup.cfg").write_text("[storage]\ndirectory = Legacy\n")
    assert run("migrate") == 0
    assert not target.exists()


def test_restore_marks_sensitive_paths(home, capsys):
    backup = setup(home, ".aws/credentials")
    (backup / ".aws").mkdir(parents=True)
    (backup / ".aws/credentials").write_text("synthetic credentials")
    assert run("--json", "--dry-run", "restore") == 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["actions"][0]["sensitive"] is True


def test_default_plan_does_not_double_conflict_bytes(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (home / "app").write_text("12345")
    (backup / "app").write_text("old")
    assert run("--json", "--dry-run", "backup") == 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["summary"]["total_bytes"] == len("12345")


def test_collector_bounds_memory_and_keeps_totals():
    limit, total = 2, 10
    reporter = _JsonReporter(io.StringIO(), collect=True, max_actions=limit)
    for index in range(total):
        reporter(
            "copy",
            {"app": "audit", "action": "copy", "src": str(index), "size_bytes": 1},
        )
    assert len(reporter.actions) == limit
    assert reporter.summary({"audit"})["total_actions"] == total
    assert reporter.summary({"audit"})["total_bytes"] == total


def test_config_distinguishes_explicit_empty_selection(home, capsys):
    setup(home)
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\n"))
    assert run("config") == 0
    assert "Applications to sync: none" in capsys.readouterr().out


def test_cleanup_removes_empty_parent_directories(home):
    backup = setup(home, "old")
    (home / "old").mkdir()
    (home / "old/file").write_text("obsolete")
    assert run("--force", "backup") == 0
    definition(home, "")
    assert run("--force", "backup") == 0
    assert not (backup / "old").exists()


def test_commit_failure_rolls_back_data_and_ownership(home):
    backup = setup(home)
    (home / "app").write_text("previous")
    assert run("--force", "backup") == 0
    index = backup / ".mackeep-state/owners.json"
    original = index.read_bytes()
    (home / "app").write_text("replacement")
    replace = os.replace

    def fail_index(source, destination):
        if str(source).endswith("/new") and Path(destination) == index:
            raise OSError("injected commit failure")
        replace(source, destination)

    with patch("mackeep.transaction.os.replace", side_effect=fail_index):
        assert run("--force", "backup") != 0
    assert (backup / "app").read_text() == "previous"
    assert index.read_bytes() == original


def test_shared_nested_file_survives_other_app_exclusion(home):
    backup = setup(home)
    (home / "app").mkdir()
    (home / "app/shared").write_text("shared")
    definition(home, "app/shared", name="other")
    assert run("--force", "backup", "other") == 0
    definition(home, "app", "app/shared")
    assert run("--force", "backup", "audit") == 0
    assert (backup / "app/shared").read_text() == "shared"


def test_migration_does_not_overwrite_destination_created_after_plan(home):
    source = home / "source"
    destination = home / "destination"
    source.write_text("legacy")
    actions = [{"action": "copy", "src": str(source), "dst": str(destination)}]
    destination.write_text("new configuration")
    assert migrate.run(actions) == 0
    assert destination.read_text() == "new configuration"
    assert actions[0]["action"] == "skip"


def test_corrupt_index_refuses_cleanup(home):
    backup = setup(home)
    (home / "app").write_text("previous")
    assert run("--force", "backup") == 0
    index = backup / ".mackeep-state/owners.json"
    index.write_text('{"version":1,"owners":{"audit":["../outside"]}}')
    (home / "app").write_text("replacement")
    assert run("--force", "backup") != 0
    assert (backup / "app").read_text() == "previous"


def test_preflight_checks_all_apps_before_first_write(home):
    backup = setup(home)
    (home / "app").write_text("data")
    definition(home, "../outside", name="bad")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\naudit\nbad\n"))
    assert run("--force", "backup") != 0
    assert not backup.exists()


def test_storage_nested_in_source_is_rejected(home):
    setup(home, "storage")
    marker = home / "storage/marker"
    marker.write_text("source")
    assert run("--force", "backup") != 0
    assert marker.read_text() == "source"


def test_nested_link_restore_preserves_link_without_touching_target(home):
    backup = setup(home)
    (backup / "app").mkdir(parents=True)
    target = home / "target"
    target.write_text("target")
    target.chmod(0o644)
    (backup / "app/link").symlink_to(target)
    assert run("--force", "restore") == 0
    assert (home / "app/link").is_symlink()
    expected_mode = 0o644
    assert target.stat().st_mode & 0o777 == expected_mode


def test_link_install_copy_failure_keeps_both_existing_versions(home):
    backup = setup(home)
    backup.mkdir()
    (home / "app").write_text("local")
    (backup / "app").write_text("previous backup")
    with patch(
        "mackeep.application.utils.copy",
        side_effect=PermissionError("injected"),
    ):
        assert run("--force", "link", "install") != 0
    assert (home / "app").read_text() == "local"
    assert (backup / "app").read_text() == "previous backup"


def test_link_uninstall_copy_failure_keeps_original_link(home):
    backup = setup(home)
    backup.mkdir()
    (backup / "app").write_text("backup")
    (home / "app").symlink_to(backup / "app")
    with patch(
        "mackeep.application.utils.copy",
        side_effect=PermissionError("injected"),
    ):
        assert run("--force", "link", "uninstall", "audit") != 0
    assert (home / "app").is_symlink()
    assert (home / "app").read_text() == "backup"


def test_external_xdg_root_uses_its_exclusion_rules(home, monkeypatch):
    external = home.parent / f"{home.name}-xdg"
    external.mkdir()
    monkeypatch.setenv("XDG_CONFIG_HOME", str(external))
    backup = setup(home, "", "[security]\nallow_external_paths = true\n")
    (home / ".mackeep/audit.cfg").write_text(
        "[application]\nname = Audit\n[xdg_configuration_files]\napp\n"
        "[xdg_exclude]\napp/cache\n",
    )
    (external / "app").mkdir()
    (external / "app/keep").write_text("keep")
    (external / "app/cache").write_text("cache")
    assert run("--force", "backup") == 0
    stored = backup / ".mackeep-external" / str(external / "app").lstrip("/")
    assert (stored / "keep").exists()
    assert not (stored / "cache").exists()


def test_failed_application_does_not_stop_other_applications(home):
    backup = setup(home, "app")
    definition(home, "other", name="second")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\naudit\nsecond\n"))
    (home / "app").write_text("first")
    (home / "other").write_text("second")
    copy = utils.copy

    def fail_first(source, destination, **kwargs):
        if Path(source).name == "app":
            raise PermissionError("injected")
        copy(source, destination, **kwargs)

    with patch("mackeep.application.utils.copy", side_effect=fail_first):
        assert run("--force", "backup") != 0
    assert (backup / "other").read_text() == "second"


def test_declining_replacement_keeps_ownership_and_previous_data(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    index = backup / ".mackeep-state/owners.json"
    old_index = index.read_bytes()
    (home / "app").write_text("new")
    utils.FORCE_YES = False
    assert run("--force-no", "backup") == 0
    assert (backup / "app").read_text() == "old"
    assert index.read_bytes() == old_index


def test_linking_a_missing_local_file_does_not_require_new_source(home):
    backup = setup(home)
    backup.mkdir()
    (backup / "app").write_text("backup")
    assert run("--force", "link", "audit") == 0
    assert (home / "app").is_symlink()


def test_first_index_keeps_shared_files_of_other_listed_apps(home):
    backup = setup(home)
    definition(home, "app/shared", name="other")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text() + "[applications_to_ignore]\nother\n")
    definition(home, "app", "app/shared")
    (home / "app").mkdir()
    (home / "app/keep").write_text("new")
    (backup / "app").mkdir(parents=True)
    (backup / "app/shared").write_text("other application's backup")
    assert run("--force", "backup") == 0
    assert (backup / "app/shared").read_text() == "other application's backup"


def test_declining_cleanup_does_not_remove_old_entries(home):
    backup = setup(home)
    (home / "app").write_text("old")
    assert run("--force", "backup") == 0
    definition(home, "")
    utils.FORCE_YES = False
    assert run("--force-no", "backup") == 0
    assert (backup / "app").read_text() == "old"


def test_missing_source_keeps_backup_when_its_rule_still_exists(home):
    backup = setup(home)
    (home / "app").write_text("saved configuration")
    assert run("--force", "backup") == 0
    (home / "app").unlink()
    assert run("--force", "backup") == 0
    assert (backup / "app").read_text() == "saved configuration"


def test_excluding_entire_legacy_entry_removes_only_its_owned_files(home):
    backup = setup(home)
    definition(home, "app", "app")
    (home / "app").write_text("local")
    backup.mkdir()
    (backup / "app").write_text("old backup")
    assert run("--force", "backup") == 0
    assert not (backup / "app").exists()


@pytest.mark.parametrize("detail", ["entries", "files"])
def test_plan_follows_explicit_top_level_directory_link(home, capsys, detail):
    setup(home)
    target = home / "target"
    target.mkdir()
    (target / "file").write_text("12345")
    (home / "app").symlink_to(target, target_is_directory=True)
    assert run("--json", "--dry-run", "--detail", detail, "backup") == 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["summary"]["total_bytes"] == len("12345")


def test_shared_excluded_file_is_not_planned_for_deletion(home, capsys):
    setup(home)
    (home / "app").mkdir()
    (home / "app/shared").write_text("shared")
    definition(home, "app/shared", name="other")
    assert run("--force", "backup", "other") == 0
    capsys.readouterr()
    definition(home, "app", "app/shared")
    assert run("--json", "--dry-run", "backup", "audit") == 0
    answer = json.loads(capsys.readouterr().out)
    assert not any(action.get("will_remove") for action in answer["actions"])


def test_first_start_does_not_choose_detected_dropbox(home, capsys):
    with patch(
        "mackeep.config.get_dropbox_folder_location",
        return_value=str(home / "storage"),
    ):
        assert run("--json", "config") == 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["storage_configured"] is False
    assert answer["storage"]["engine"] == "unconfigured"
    assert run("--force", "backup") != 0
    assert not (home / "storage/Mackeep").exists()


def test_restore_marks_xdg_credentials_sensitive(home, capsys):
    backup = setup(home, "")
    (home / ".mackeep/audit.cfg").write_text(
        "[application]\nname = Audit\n[xdg_configuration_files]\ngh/hosts.yml\n",
    )
    (backup / ".config/gh").mkdir(parents=True)
    (backup / ".config/gh/hosts.yml").write_text("synthetic credentials")
    assert run("--json", "--dry-run", "restore") == 0
    answer = json.loads(capsys.readouterr().out)
    assert answer["actions"][0]["sensitive"] is True


def test_empty_file_system_path_waits_for_user_configuration(home, capsys):
    setup(home)
    (home / ".mackeep.cfg").write_text(
        "[storage]\nengine = file_system\npath =\n[applications_to_sync]\n",
    )
    assert run("--json", "config") == 0
    assert json.loads(capsys.readouterr().out)["storage_configured"] is False
    assert run("--force", "backup") != 0
    assert not (home / "Mackeep").exists()


def test_failed_rollback_retains_recovery_data_after_close(home, monkeypatch):
    """A second failure must leave both old versions recoverable and named."""

    first, second = home / "first", home / "second"
    first.write_bytes(b"first old")
    second.write_bytes(b"second old")
    transaction = Transaction()
    def stage_first(path: str) -> None:
        Path(path).write_bytes(b"first new")

    def stage_second(path: str) -> None:
        Path(path).write_bytes(b"second new")

    transaction.prepare(str(first), stage_first)
    transaction.prepare(str(second), stage_second)
    replace = os.replace

    def fail_commit_and_rollback(source, destination):
        if Path(source).name == "new" and Path(destination) == second:
            raise OSError("commit failed")
        if Path(source).name == "previous" and Path(destination) == second:
            raise OSError("rollback failed")
        replace(source, destination)

    monkeypatch.setattr("mackeep.transaction.os.replace", fail_commit_and_rollback)
    with pytest.raises(
        OSError, match="Rollback failed; previous data retained",
    ) as error:
        transaction.commit()
    transaction.close()
    workspaces = [Path(item.workspace) for item in transaction.replacements]
    for workspace in workspaces:
        assert str(workspace) in str(error.value)
        assert workspace.is_dir()
    assert (workspaces[0] / "previous").read_bytes() == b"first old"
    assert (workspaces[1] / "previous").read_bytes() == b"second old"
    assert first.read_bytes() == b"first new"
    assert (workspaces[1] / "new").read_bytes() == b"second new"


@pytest.mark.parametrize(
    "payload",
    [
        [],
        {"version": 99, "owners": {}},
        {"version": 1, "owners": []},
        {"version": 1, "owners": {"audit": "app"}},
        *(
            {"version": 1, "owners": {"audit": [path]}}
            for path in (
                None,
                "",
                "/outside",
                ".",
                "app/../outside",
                "app//file",
                ".mackeep-state/owners.json",
            )
        ),
    ],
)
def test_invalid_ownership_index_blocks_writes(home, payload):
    """Reject each malformed record without replacing existing backup data."""
    backup = setup(home)
    (home / "app").write_bytes(b"original")
    assert run("--force", "backup") == 0
    index = backup / ".mackeep-state/owners.json"
    invalid = json.dumps(payload).encode()
    index.write_bytes(invalid)
    (home / "app").write_bytes(b"new local")
    assert run("--force", "backup") != 0
    assert index.read_bytes() == invalid
    assert (backup / "app").read_bytes() == b"original"
    assert (home / "app").read_bytes() == b"new local"


@pytest.mark.parametrize("link_directory", [False, True])
def test_symlinked_ownership_index_blocks_writes(home, link_directory):
    """Neither an index nor its directory may redirect backup state writes."""
    backup = setup(home)
    (home / "app").write_bytes(b"original")
    assert run("--force", "backup") == 0
    state = backup / ".mackeep-state"
    original = (state / "owners.json").read_bytes()
    target = home / "outside-state"
    if link_directory:
        state.rename(target)
        state.symlink_to(target, target_is_directory=True)
    else:
        target.write_bytes(original)
        (state / "owners.json").unlink()
        (state / "owners.json").symlink_to(target)
    (home / "app").write_bytes(b"replacement")
    assert run("--force", "backup") != 0
    assert (state / "owners.json").read_bytes() == original
    assert (backup / "app").read_bytes() == b"original"
    assert (home / "app").read_bytes() == b"replacement"


@pytest.mark.parametrize("entry", [".mackeep-state/file", ".mackeep-external/file"])
def test_reserved_backup_names_are_rejected(home, entry):
    backup = setup(home, entry)
    source = home / entry
    source.parent.mkdir()
    source.write_bytes(b"keep local")
    assert run("--force", "backup") != 0
    assert source.read_bytes() == b"keep local"
    assert not backup.exists()


def test_hardlinked_source_and_destination_are_rejected(home):
    backup = setup(home)
    backup.mkdir()
    source = home / "app"
    source.write_bytes(b"only data")
    (backup / "app").hardlink_to(source)
    assert run("--force", "backup") != 0
    assert source.read_bytes() == b"only data"
    assert (backup / "app").read_bytes() == b"only data"
    assert not (backup / ".mackeep-state").exists()


def test_ownership_relative_rejects_paths_outside_storage(home):

    state = BackupState(str(home / "storage"))
    outside = home / "outside"
    outside.write_bytes(b"keep")
    with pytest.raises(ConfigError, match="leaves storage"):
        state.relative(str(outside))
    assert state.relative(str(home / "storage/app")) == "app"
    assert outside.read_bytes() == b"keep"


def test_signal_cancellation_finishes_current_real_transaction(home):
    """Synchronize inside a real copy, signal the CLI, and check persisted results."""

    backup = setup(home)
    definition(home, "second", name="second")
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text().replace("\naudit\n", "\naudit\nsecond\n"))
    (home / "app").write_bytes(b"complete first application")
    (home / "second").write_bytes(b"must not be copied")
    marker, release = home / "copy-started", home / "copy-release"
    script = """
import sys, time
from pathlib import Path
from mackeep import utils
from mackeep_cli.main import main
original = utils.copy
home = Path.home()
def synchronized_copy(source, destination, **kwargs):
    if Path(source).name == "app":
        (home / "copy-started").touch()
        deadline = time.monotonic() + 10
        while not (home / "copy-release").exists():
            if time.monotonic() >= deadline:
                raise TimeoutError("Test never released copy")
            time.sleep(0.01)
    return original(source, destination, **kwargs)
utils.copy = synchronized_copy
sys.argv = ["mackeep-cli", "--root", "--force", "--json", "backup"]
main()
"""
    environment = {
        **os.environ,
        "PYTHONPATH": str(Path(__file__).resolve().parents[1] / "src"),
    }
    with subprocess.Popen(
        [sys.executable, "-c", script],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ) as process:
        try:
            deadline = time.monotonic() + 10
            while (
                not marker.exists()
                and process.poll() is None
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            assert marker.exists(), "The first application never reached copy"
            process.send_signal(signal.SIGUSR1)
            release.touch()
            stdout, stderr = process.communicate(timeout=10)
            cancelled_status = 130
            assert process.returncode == cancelled_status, (stdout, stderr)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)
    assert (backup / "app").read_bytes() == b"complete first application"
    assert not (backup / "second").exists()
    owners = json.loads((backup / ".mackeep-state/owners.json").read_text())["owners"]
    assert owners == {"audit": ["app"], "second": []}
    events = [json.loads(line) for line in stdout.splitlines()]
    assert [event["app"] for event in events if event.get("event") == "done"] == [
        "audit",
    ]
    assert not any(event.get("app") == "second" for event in events)
    assert not list(backup.glob(".mackeep-*/previous"))


@pytest.mark.parametrize("absolute", [False, True])
def test_path_mapping_refuses_external_entries_without_permission(home, absolute):
    """Exercise the mapping guard independently of database validation."""
    outside = home.parent / f"{home.name}-external"
    outside.write_bytes(b"untouched external data")
    entry = str(outside) if absolute else os.path.relpath(outside, home)
    backup = home / "storage/Mackeep"
    with pytest.raises(ConfigError, match="External paths are disabled"):
        entry_paths(entry, str(backup))
    local, stored = entry_paths(entry, str(backup), allow_external=True)
    assert local == str(outside)
    assert Path(stored).is_relative_to(backup / ".mackeep-external")
    assert outside.read_bytes() == b"untouched external data"
    assert not backup.exists()
