"""Exercise the filesystem failures and real CLI flows found in review."""

import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.backupstate import BackupState
from mackeep.config import Config, ConfigError
from mackeep.excludes import Matcher, Rule
from mackeep.locking import storage_lock
from mackeep.transaction import Transaction
from tests.test_audit_regressions import run, setup


def test_repeated_json_backup_replaces_snapshot(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (home / "app").write_bytes(b"first")
    utils.FORCE_YES = False
    assert run("--json", "backup") == 0
    (home / "app").write_bytes(b"second")
    assert run("--json", "backup") == 0
    assert (backup / "app").read_bytes() == b"second"
    capsys.readouterr()


def test_json_declined_restore_is_not_success(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (backup / "app").write_text("backup")
    (home / "app").write_text("local")
    utils.FORCE_YES = False
    assert run("--json", "restore") == 1
    assert (home / "app").read_text() == "local"
    capsys.readouterr()


@pytest.mark.parametrize("directory", ["", ".", "..", "../outside", "/tmp/outside"])
def test_invalid_storage_directory_is_rejected(home, directory):
    setup(home)
    config = home / ".mackeep.cfg"
    config.write_text(
        config.read_text().replace("[storage]", f"[storage]\ndirectory = {directory}"),
    )
    with pytest.raises(ConfigError):
        Config()


def test_storage_directory_cannot_follow_link_outside(home):
    setup(home)
    (home / "outside").mkdir()
    (home / "storage/Mackeep").symlink_to(home / "outside", target_is_directory=True)
    with pytest.raises(ConfigError):
        _ = Config().fullpath


def test_storage_path_expands_home(home):
    (home / ".mackeep.cfg").write_text(
        "[storage]\nengine = file_system\npath = ~/storage\n",
    )
    assert Config().path == str(home / "storage")


def test_invalid_index_has_configuration_error(home):
    root = home / "storage"
    (root / ".mackeep-state").mkdir()
    (root / ".mackeep-state/owners.json").write_text("{broken")
    with pytest.raises(ConfigError, match="ownership"):
        BackupState(str(root))


def test_cleanup_continues_after_one_workspace_fails(home, capsys):
    transaction = Transaction()
    for name in ("one", "two"):
        transaction.prepare(str(home / name), lambda path: open(path, "w").close())
    transaction.commit()
    remove = shutil.rmtree
    first = transaction.replacements[0].workspace

    def fail_first(path, *, onexc):
        if path == first:
            raise PermissionError("blocked")
        remove(path, onexc=onexc)

    with patch("mackeep.transaction.shutil.rmtree", side_effect=fail_first):
        transaction.close()
    assert not os.path.exists(transaction.replacements[1].workspace)
    assert os.path.exists(first)
    assert "Warning" in capsys.readouterr().err


def test_restore_preserves_original_modes_and_private_storage(home):
    backup = setup(home)
    source = home / "app"
    source.mkdir()
    (source / "script").write_bytes(b"#!/bin/sh\nexit 0\n")
    source.chmod(0o750)
    (source / "script").chmod(0o754)
    assert run("--force", "backup") == 0
    private_mode = 0o700
    assert stat.S_IMODE((backup / "app/script").stat().st_mode) == private_mode
    source.chmod(0o700)
    (source / "script").chmod(0o600)
    assert run("--force", "restore") == 0
    directory_mode, script_mode = 0o750, 0o754
    assert stat.S_IMODE(source.stat().st_mode) == directory_mode
    assert stat.S_IMODE((source / "script").stat().st_mode) == script_mode
    assert (
        json.loads((backup / ".mackeep-state/owners.json").read_text())["version"] == 1
    )


def test_confirm_eof_declines():
    with (
        patch.object(utils, "FORCE_YES", False),
        patch.object(utils, "FORCE_NO", False),
        patch(
            "builtins.input",
            side_effect=EOFError,
        ),
    ):
        assert utils.confirm("Replace?") is False


def test_storage_lock_blocks_another_process_and_releases(home):
    """A separate CLI process cannot write until the owning process releases."""
    root = setup(home)
    source = (
        "import sys; from mackeep.locking import storage_lock; "
        "\nwith storage_lock(sys.argv[1]): print('acquired')"
    )
    environment = dict(os.environ, PYTHONPATH=str(Path.cwd() / "src"))
    with storage_lock(str(root)):
        blocked = subprocess.run(
            [sys.executable, "-c", source, str(root)],
            env=environment, capture_output=True, text=True, check=False,
        )
    assert blocked.returncode != 0
    assert "Another Mackeep operation" in blocked.stderr
    acquired = subprocess.run(
        [sys.executable, "-c", source, str(root)],
        env=environment, capture_output=True, text=True, check=True,
    )
    assert acquired.stdout.strip() == "acquired"


def test_dry_run_creates_no_local_lock(home, capsys):
    setup(home)
    (home / "app").write_text("content")
    assert run("--json", "--dry-run", "backup") == 0
    assert not (home / ".local/state/mackeep").exists()
    capsys.readouterr()


def test_unavailable_cloud_does_not_block_diagnostics(home, capsys):
    (home / ".mackeep.cfg").write_text("[storage]\nengine = dropbox\n")
    assert run("--json", "config") == 0
    result = json.loads(capsys.readouterr().out)
    assert result["storage"]["resolved_backup_dir"] == ""
    assert result["errors"]
    assert run("list") == 0
    capsys.readouterr()


def test_cleanup_removes_read_only_previous_tree(home):
    destination = home / "app"
    destination.mkdir()
    (destination / "nested").mkdir()
    (destination / "nested/old").write_bytes(b"previous")
    (destination / "nested").chmod(0o500)
    transaction = Transaction()
    transaction.prepare(str(destination), lambda path: Path(path).mkdir())
    transaction.commit()
    transaction.close()
    assert destination.is_dir()
    assert not list(home.glob(".mackeep-*"))


def test_copy_tree_does_not_spawn_permission_processes(home):
    backup = setup(home)
    (home / "app/nested").mkdir(parents=True)
    count = 100
    for index in range(count):
        (home / f"app/nested/{index}").write_bytes(b"data")
    with patch(
        "mackeep.utils.subprocess.Popen",
        side_effect=AssertionError("Unexpected process"),
    ):
        assert run("--force", "backup") == 0
    files = list((backup / "app/nested").iterdir())
    assert len(files) == count
    assert all(path.read_bytes() == b"data" for path in files)


@pytest.mark.parametrize("path", [
    ".npmrc", ".npmrcs/work", ".codex/auth.json", ".composer/auth.json",
    ".gem/credentials", ".gmailctl/credentials.json", ".context7/credentials.json",
    ".factory/auth.json", ".local/share/opencode/auth.json", ".keybase/config.json",
])
def test_additional_secret_paths_are_detected(path):
    assert utils.sensitive_reason(path) is not None


def test_literal_brackets_remain_literal():
    matcher = Matcher([Rule("app/file[12].txt", "exclude", "test.cfg")])
    assert matcher.match("app/file[12].txt", False) is not None
    assert matcher.match("app/file1.txt", False) is None


def test_read_only_root_permissions_survive_repeated_restore(home):
    setup(home)
    source = home / "app"
    source.mkdir()
    (source / "config").write_bytes(b"saved")
    read_only_mode = 0o550
    source.chmod(read_only_mode)
    assert run("--force", "backup") == 0
    for _ in range(2):
        assert run("--force", "restore") == 0
        assert stat.S_IMODE(source.stat().st_mode) == read_only_mode
        assert (source / "config").read_bytes() == b"saved"


def test_force_does_not_leak_into_the_next_invocation(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (backup / "app").write_bytes(b"backup")
    (home / "app").write_bytes(b"local")
    utils.FORCE_YES = False
    assert run("--json", "--force", "restore") == 0
    (home / "app").write_bytes(b"new local")
    assert run("--json", "restore") == 1
    assert (home / "app").read_bytes() == b"new local"
    capsys.readouterr()


@pytest.mark.parametrize(
    "modes", [{"../outside": 0o777}, {"app": 0o4777}, {".": 0o700}],
)
def test_invalid_saved_permissions_refuse_restore(home, modes):
    root = setup(home)
    (root / ".mackeep-state").mkdir(parents=True)
    (root / ".mackeep-state/owners.json").write_text(
        json.dumps({"version": 1, "owners": {}, "modes": modes}),
    )
    with pytest.raises(ConfigError, match="permissions"):
        BackupState(str(root))


def test_old_index_without_modes_still_restores(home):
    root = setup(home)
    (root / ".mackeep-state").mkdir(parents=True)
    (root / ".mackeep-state/owners.json").write_text(
        json.dumps({"version": 1, "owners": {"audit": ["app"]}}),
    )
    (root / "app").write_bytes(b"legacy backup")
    assert run("--force", "restore") == 0
    assert (home / "app").read_bytes() == b"legacy backup"


def test_failed_commit_restores_read_only_destination(home, monkeypatch):
    destination = home / "app"
    destination.mkdir()
    (destination / "old").write_bytes(b"retained")
    read_only = 0o550
    destination.chmod(read_only)
    transaction = Transaction()
    transaction.prepare(str(destination), lambda path: Path(path).mkdir())
    original_replace = os.replace

    def fail_install(source, target):
        if source == transaction.replacements[0].staged:
            raise OSError("failed install")
        original_replace(source, target)

    monkeypatch.setattr("mackeep.transaction.os.replace", fail_install)
    with pytest.raises(OSError, match="failed install"):
        transaction.commit()
    transaction.close()
    assert stat.S_IMODE(destination.stat().st_mode) == read_only
    assert (destination / "old").read_bytes() == b"retained"


def test_copy_error_still_finishes_the_application_event(home, capsys):
    root = setup(home)
    root.mkdir()
    (home / "app").write_bytes(b"data")
    with patch("mackeep.application.utils.copy", side_effect=ValueError("unsupported")):
        assert run("--json", "backup") == 1
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert [event["event"] for event in events[:3]] == ["start", "error", "done"]
    assert not (root / "app").exists()


def test_copy_immutable_file_keeps_source_flags_and_clears_only_backup(home):
    if sys.platform != "darwin":
        pytest.skip("Requires macOS file flags")
    root = setup(home)
    source = home / "app"
    source.write_bytes(b"protected configuration")
    os.chflags(source, stat.UF_IMMUTABLE)
    try:
        assert run("--force", "backup") == 0
        assert source.stat().st_flags & stat.UF_IMMUTABLE
        assert not (root / "app").stat().st_flags & stat.UF_IMMUTABLE
        assert (root / "app").read_bytes() == b"protected configuration"
    finally:
        os.chflags(source, 0)
