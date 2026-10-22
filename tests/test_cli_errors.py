"""Tests for the error paths of the command line of Mackeep."""

import json
import runpy
from types import SimpleNamespace
from typing import cast
from unittest.mock import patch

import pytest

from mackeep import utils
from mackeep.jsonapi import SCHEMA_VERSION
from mackeep_cli import main as main_module
from mackeep_cli.main import _Context, main

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


def setup(home):
    """Set up a home directory with a config file and a test application."""
    write_config(home, home / ".mackeep.cfg")
    write_config(home, home / ".mackeep" / "test-app.cfg", APP_CONFIG)
    (home / ".testrc").write_text("test_config=value\n")
    (home / "storage" / "Mackeep").mkdir(parents=True, exist_ok=True)


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


def test_the_list_command_lists_the_applications(home, capsys):
    """The list command displays the supported applications."""
    setup(home)

    run("list")
    captured = capsys.readouterr()

    assert "test-app" in captured.out
    assert "applications supported in Mackeep" in captured.out


def test_the_show_command_displays_the_application(home, capsys):
    """The show command displays the files of an application."""
    setup(home)

    run("show", "test-app")
    captured = capsys.readouterr()

    assert "Name: Test App" in captured.out
    assert ".testrc" in captured.out


def test_the_show_command_displays_the_exclusions(home, capsys):
    """The show command displays the excluded paths of an application."""
    setup(home)
    write_config(
        home,
        home / ".mackeep" / "test-app.cfg",
        APP_CONFIG + "\n[exclude]\n.cache/*\n\n[xdg_exclude]\nconfig/*\n",
    )

    run("show", "test-app")
    captured = capsys.readouterr()

    assert "Excluded paths:" in captured.out
    assert ".cache/*" in captured.out
    assert "Excluded XDG paths:" in captured.out
    assert "config/*" in captured.out


def test_the_show_command_fails_on_an_unknown_application(home):
    """The show command fails when the application is not supported."""
    setup(home)

    with pytest.raises(SystemExit):
        run("show", "unknown-app")


def test_the_verbose_output_has_the_header_of_the_application(home, capsys):
    """The verbose output displays the name of the application."""
    setup(home)

    run("--verbose", "backup")
    captured = capsys.readouterr()

    assert "test-app" in captured.out


def test_the_migrate_command_copies_the_legacy_files(home, capsys):
    """The migrate command displays the files it copies."""
    write_config(home, home / ".mackup.cfg", MAIN_CONFIG)

    run("migrate")
    captured = capsys.readouterr()

    assert "Copy" in captured.out
    assert "file(s) copied" in captured.out
    assert (home / ".mackeep.cfg").exists()


def test_the_dry_run_of_the_migrate_command_copies_nothing(home, capsys):
    """The dry-run of the migrate command copies nothing."""
    write_config(home, home / ".mackup.cfg", MAIN_CONFIG)

    run("--dry-run", "migrate")
    captured = capsys.readouterr()

    assert "Nothing was copied, this was a dry-run." in captured.out
    assert not (home / ".mackeep.cfg").exists()


def test_the_json_migrate_command_writes_the_plan(home, capsys):
    """The JSON mode of the migrate command writes the plan."""
    write_config(home, home / ".mackup.cfg", MAIN_CONFIG)

    data, code = run_json(capsys, "migrate")

    assert code == 0
    assert data["summary"]["copied"] == 1
    assert data["actions"][0]["action"] == "copy"


def test_the_json_restore_command_writes_the_events(home, capsys):
    """The JSON mode of the restore command writes the events."""
    setup(home)

    code: int = 0
    try:
        run("--json", "restore", "test-app")
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else 1
    captured = capsys.readouterr()

    events: list[dict] = [
        json.loads(line) for line in captured.out.splitlines() if line
    ]

    assert code == 0
    assert events[0]["event"] == "start"
    assert events[-1]["event"] == "done"
    assert events[0]["schema_version"] == SCHEMA_VERSION


def test_the_json_mode_does_not_support_the_link_commands(home, capsys):
    """The JSON mode does not support the link commands."""
    setup(home)

    data, code = run_json(capsys, "link", "install")

    assert code == 1
    assert data["error"]["code"] == "error"
    assert "not supported" in data["error"]["message"]


def test_the_json_mode_writes_the_error_of_an_unknown_application(home, capsys):
    """The JSON mode writes the error of an unknown application."""
    setup(home)

    data, code = run_json(capsys, "show", "unknown-app")

    assert code == 1
    assert data["error"]["code"] == "unsupported_application"
    assert "Unsupported application" in data["error"]["message"]


def test_the_force_and_the_force_no_options_are_exclusive(home):
    """The force and the force-no options cannot be used together."""
    setup(home)

    with pytest.raises(SystemExit):
        run("--force", "--force-no", "backup")


def test_the_root_option_allows_to_run_as_root(home):
    """The root option allows Mackeep to run as root."""
    setup(home)

    run("--root", "backup")

    assert utils.CAN_RUN_AS_ROOT is True


def test_an_unknown_detail_level_fails(home):
    """An unknown detail level is an error."""
    setup(home)

    with pytest.raises(SystemExit):
        run("--detail", "unknown", "backup")


def test_an_invalid_number_of_actions_fails(home):
    """An invalid number of actions is an error."""
    setup(home)

    with pytest.raises(SystemExit):
        run("--max-actions", "many", "backup")


def test_a_number_of_actions_below_one_fails(home):
    """A number of actions below one is an error."""
    setup(home)

    with pytest.raises(SystemExit):
        run("--max-actions", "0", "backup")


def test_the_command_fails_without_the_usage_information(home):
    """The command fails when the usage information is not available."""
    setup(home)

    with patch.object(main_module, "__doc__", None), pytest.raises(SystemExit):
        run("backup")


def test_the_config_error_is_written_as_json(home, capsys):
    """A config error is written as JSON in the JSON mode."""
    setup(home)
    (home / ".mackeep.cfg").write_text("[storage]\nengine = unknown\n")

    data, code = run_json(capsys, "config")

    assert code == 1
    assert data["error"]["code"] == "config_error"


def test_the_config_error_is_raised_in_the_text_mode(home):
    """A config error stops the command in the text mode."""
    setup(home)
    (home / ".mackeep.cfg").write_text("[storage]\nengine = unknown\n")

    with pytest.raises(SystemExit, match="Unknown storage engine"):
        run("config")


def test_the_exit_code_is_written_in_the_json(home, capsys):
    """An exit code that is not a message is written in the JSON."""
    setup(home)

    with patch("mackeep_cli.main._run", side_effect=SystemExit(3)):
        data, code = run_json(capsys, "backup")

    assert code == 1
    assert data["error"]["code"] == "error"
    assert "exit code 3" in data["error"]["message"]


def test_the_entry_point_of_the_module_runs_the_command(home, capsys):
    """The module of the package runs the command."""
    setup(home)

    # The module runs the command when it is run as a program.
    with patch("sys.argv", ["mackeep-cli", "list"]):
        runpy.run_module("mackeep_cli", run_name="__main__")

    captured = capsys.readouterr()
    assert "applications supported in Mackeep" in captured.out


def test_the_version_is_shown_with_the_short_options(home, capsys):
    """The version is shown with -v, -V and --version."""
    setup(home)

    for option in ("-v", "-V", "--version"):
        with pytest.raises(SystemExit) as exit_info:
            run(option)
        captured = capsys.readouterr()

        assert exit_info.value.code == 0, option
        assert captured.out.startswith("Mackeep "), option
        assert captured.err == "", option


def test_the_verbose_option_has_no_short_option(home, capsys):
    """The verbose option is only the long one, -v shows the version."""
    setup(home)

    run("--verbose", "list")
    captured = capsys.readouterr()

    assert "applications supported in Mackeep" in captured.out


def test_cancellation_stops_between_complete_applications(monkeypatch):
    """A stop request finishes the current app and never starts the next."""
    copied = []
    events = []

    def copy_first():
        copied.append("first")
        main_module._request_cancel(0, None)  # noqa: SLF001 - exercise signal boundary

    profiles = [
        ("first", SimpleNamespace(copy=copy_first, failed=False)),
        ("second", SimpleNamespace(copy=lambda: copied.append("second"), failed=False)),
    ]
    monkeypatch.setattr(main_module, "_cancel_requested", False)
    monkeypatch.setattr(main_module, "_preflight", lambda *_: profiles)
    ctx = cast(
        "_Context",
        SimpleNamespace(verbose=False, reporter=lambda event, _: events.append(event)),
    )
    with pytest.raises(SystemExit) as error:
        main_module._run_action(ctx, {"first", "second"}, "copy")  # noqa: SLF001
    cancelled = 130
    assert error.value.code == cancelled
    assert copied == ["first"]
    assert events == ["start", "done"]
