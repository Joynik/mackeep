"""CLI history records committed results without polluting command output."""

import json
from unittest.mock import patch

import pytest

from mackeep_cli.history import OperationHistory, history_directory
from tests.test_audit_regressions import run, setup


def records():
    """Read only this test's isolated CLI journal."""
    return [json.loads(path.read_text()) for path in history_directory().glob("*.json")]


@pytest.mark.parametrize("flags", [(), ("--summary",), ("--force",)])
def test_cli_backup_records_committed_counts(home, flags):
    setup(home)
    (home / "app").write_text("data")
    assert run("backup", *flags) == 0
    (record,) = records()
    assert record["command"] == "backup"
    assert record["application"] == "audit"
    assert record["succeeded"] is True
    assert record["files"] == 1
    assert record["bytes"] == len("data")
    assert record["message"] is None
    (file,) = history_directory().glob("*.json")
    private_mode = 0o600
    assert file.stat().st_mode & 0o777 == private_mode


def test_failed_cli_backup_records_failure_without_staged_files(home):
    setup(home)
    (home / "app").write_text("data")
    with patch(
        "mackeep.application.utils.copy", side_effect=PermissionError("blocked"),
    ):
        assert run("backup", "--summary") == 1
    (record,) = records()
    assert record["succeeded"] is False
    assert record["files"] == 0
    assert "blocked" in record["message"]


@pytest.mark.parametrize("flags", [("--dry-run",), ("--json",)])
def test_preview_and_frontend_do_not_duplicate_history(home, flags):
    setup(home)
    (home / "app").write_text("data")
    assert run("backup", *flags) == 0
    assert not history_directory().exists()


def test_restore_records_history_and_reports_overwrites(home, capsys):
    backup = setup(home, "app\nnew")
    backup.mkdir()
    (backup / "app").write_text("saved")
    (backup / "new").write_text("new")
    (home / "app").write_text("local")
    assert run("restore", "--force", "--json") == 0
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    copies = {event["dst"]: event for event in events if event.get("action") == "copy"}
    assert copies[str(home / "app")]["would_overwrite"] is True
    assert copies[str(home / "new")]["would_overwrite"] is False
    assert run("restore", "--force") == 0
    (record,) = records()
    assert record["command"] == "restore"
    assert record["files"] == len(copies)


def test_history_failure_does_not_change_backup_result(home, capsys):
    backup = setup(home)
    (home / "app").write_text("data")
    with patch(
        "mackeep_cli.history.OperationHistory.save", side_effect=OSError("blocked"),
    ):
        assert run("backup") == 0
    assert (backup / "app").read_text() == "data"
    assert "could not save run history" in capsys.readouterr().err


def test_cli_journal_rejects_symlink_and_limits_records(home):
    target = home / "protected"
    target.mkdir()
    directory = history_directory()
    directory.parent.mkdir(parents=True)
    directory.symlink_to(target, target_is_directory=True)
    with pytest.raises(OSError, match="symbolic link"):
        OperationHistory("backup", None).save()
    assert not list(target.iterdir())
    directory.unlink()
    for _ in range(52):
        OperationHistory("backup", None).save()
    maximum_runs = 50
    assert len(records()) == maximum_runs


def test_plain_cli_history_preserves_secret_warnings(home, capsys):
    setup(home, ".ssh/id_ed25519")
    (home / ".ssh").mkdir()
    (home / ".ssh/id_ed25519").write_text("test private key")
    assert run("backup") == 0
    assert "holds secrets in 1 paths" in capsys.readouterr().err
    assert records()[0]["succeeded"] is True
