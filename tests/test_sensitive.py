"""Tests for the paths that hold secrets."""

import json
from unittest.mock import patch

from mackeep import utils
from mackeep.jsonapi import SCHEMA_VERSION
from mackeep_cli.main import main

# The content of the config file of the test application
APP_CONFIG = (
    "[application]\n"
    "name = Test App\n"
    "\n"
    "[configuration_files]\n"
    ".ssh/id_rsa\n"
    ".ssh/id_rsa.pub\n"
    ".ssh/config\n"
    ".gnupg\n"
    ".aws/credentials\n"
    "Library/Keychains\n"
    ".configrc\n"
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

    for name in (".ssh/id_rsa", ".ssh/id_rsa.pub", ".ssh/config", ".configrc"):
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("secret\n")

    for name in (".aws/credentials", ".gnupg/secring.gpg", "Library/Keychains/db"):
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("secret\n")

    (home / "storage" / "Mackeep").mkdir(parents=True, exist_ok=True)

    return home


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


def test_the_sensitive_paths_are_found():
    """The paths that hold secrets are found."""
    assert utils.sensitive_reason(".ssh/id_rsa") == "A private key of SSH"
    assert utils.sensitive_reason(".gnupg") == "The keys of GnuPG"
    assert utils.sensitive_reason(".gnupg/secring.gpg") == "The keys of GnuPG"
    assert utils.sensitive_reason(".aws/credentials") == "The credentials of AWS"
    assert utils.sensitive_reason("Library/Keychains") == "The keychain of macOS"
    assert (
        utils.sensitive_reason("Library/Keychains/login.keychain-db")
        == "The keychain of macOS"
    )
    assert utils.sensitive_reason(".configrc") is None


def test_the_public_keys_are_not_sensitive():
    """The public keys are not secrets."""
    assert utils.sensitive_reason(".ssh/id_rsa.pub") is None


def test_the_json_list_marks_the_sensitive_files(home, capsys):
    """The JSON list tells which files hold secrets."""
    setup(home)

    data, code = run_json(capsys, "list")

    assert code == 0

    app = next(app for app in data if app["name"] == "test-app")
    assert app["schema_version"] == SCHEMA_VERSION
    files = {file["path"]: file for file in app["files"]}

    assert files[".ssh/id_rsa"]["sensitive"] is True
    assert files[".ssh/id_rsa"]["sensitive_reason"] == "A private key of SSH"
    assert files[".ssh/id_rsa.pub"]["sensitive"] is False
    assert files[".ssh/id_rsa.pub"]["sensitive_reason"] is None
    assert files[".ssh/config"]["sensitive"] is False
    assert files[".aws/credentials"]["sensitive"] is True
    assert files[".configrc"]["sensitive"] is False


def test_the_json_show_marks_the_sensitive_files(home, capsys):
    """The JSON show tells which files hold secrets."""
    setup(home)

    data, code = run_json(capsys, "show", "test-app")

    assert code == 0
    assert data["schema_version"] == SCHEMA_VERSION

    files = {file["path"]: file for file in data["files"]}
    assert files[".ssh/id_rsa"]["sensitive"] is True
    assert files[".ssh/config"]["sensitive"] is False


def test_the_json_dry_run_marks_the_sensitive_files(home, capsys):
    """The JSON dry-run tells which files hold secrets."""
    setup(home)

    data, code = run_json(capsys, "backup", "--dry-run", "test-app")

    assert code == 0
    assert data["schema_version"] == SCHEMA_VERSION

    actions = {action["src"]: action for action in data["actions"]}
    copied = next(
        action
        for action in actions.values()
        if action["action"] == "copy" and action["src"].endswith("id_rsa")
    )
    assert copied["sensitive"] is True
    assert copied["sensitive_reason"] == "A private key of SSH"

    other = next(
        action
        for action in actions.values()
        if action["action"] == "copy" and action["src"].endswith("configrc")
    )
    assert other["sensitive"] is False
    assert other["sensitive_reason"] is None


def test_the_backup_warns_once_about_the_sensitive_files(home, capsys):
    """The backup warns about the sensitive files once."""
    setup(home)

    run("backup", "test-app")
    captured = capsys.readouterr()

    assert captured.err.count("Warning:") == 1
    assert "holds secrets" in captured.err


def test_the_backup_does_not_warn_without_the_sensitive_files(home, capsys):
    """The backup does not warn when there is no sensitive file."""
    setup(home)
    (home / ".ssh" / "id_rsa").unlink()
    (home / ".aws" / "credentials").unlink()
    (home / ".gnupg" / "secring.gpg").unlink()
    (home / "Library" / "Keychains" / "db").unlink()

    run("backup", "test-app")
    captured = capsys.readouterr()

    assert "Warning:" not in captured.err


def test_the_schema_version_is_the_current_one(home, capsys):
    """The version of the schema is the current one."""
    setup(home)

    data, code = run_json(capsys, "show", "test-app")

    assert code == 0
    assert data["schema_version"] == SCHEMA_VERSION
