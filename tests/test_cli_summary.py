"""Compact backup output preserves copy behavior and error visibility."""

import json
from unittest.mock import patch

import pytest

from mackeep import utils
from tests.test_audit_regressions import run, setup


@pytest.mark.parametrize("flags", [(), ("--force",), ("--verbose",)])
def test_summary_counts_committed_files_without_progress(home, capsys, flags):
    backup = setup(home, "app\nmissing")
    backup.mkdir()
    (home / "app").mkdir()
    (home / "app/one").write_text("one")
    (home / "app/two").write_text("two")
    utils.FORCE_YES = False
    assert run("backup", "--summary", *flags) == 0
    captured = capsys.readouterr()
    assert "Backing up" not in captured.out + captured.err
    assert "| Files copied           |        2 |" in captured.out
    assert "| Applications succeeded |        1 |" in captured.out
    assert "| Paths skipped          |        1 |" in captured.out
    assert (backup / "app/two").read_text() == "two"


def test_summary_reports_failed_transaction_without_counting_staged_files(home, capsys):
    backup = setup(home)
    (home / "app").mkdir()
    (home / "app/one").write_text("first")
    (home / "app/two").write_text("second")
    copy = utils.copy

    def fail_second(source, destination, **kwargs):
        if source.endswith("/two"):
            raise PermissionError("blocked")
        return copy(source, destination, **kwargs)

    with patch("mackeep.application.utils.copy", side_effect=fail_second):
        assert run("backup", "--summary") == 1
    captured = capsys.readouterr()
    assert "| Applications failed    |        1 |" in captured.out
    assert "| Files copied           |        0 |" in captured.out
    assert "blocked" in captured.err
    assert not (backup / "app").exists()


def test_summary_force_no_keeps_old_snapshot(home, capsys):
    backup = setup(home)
    backup.mkdir()
    (backup / "app").write_text("old")
    (home / "app").write_text("new")
    assert run("backup", "--force-no", "--summary") == 1
    captured = capsys.readouterr()
    assert "replacement declined" in captured.err
    assert "| Applications failed    |        1 |" in captured.out
    assert (backup / "app").read_text() == "old"


def test_summary_does_not_change_json_contract(home, capsys):
    setup(home)
    (home / "app").write_text("data")
    assert run("backup", "--json", "--summary") == 0
    captured = capsys.readouterr()
    events = [json.loads(line) for line in captured.out.splitlines()]
    assert events[-1]["event"] == "done"
    assert "Backup summary" not in captured.out + captured.err


@pytest.mark.parametrize("arguments", [("restore",), ("backup", "--dry-run")])
def test_summary_rejects_unsupported_modes(home, capsys, arguments):
    setup(home)
    assert run(*arguments, "--summary") == 1
    assert not capsys.readouterr().out
