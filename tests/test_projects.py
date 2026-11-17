"""Project persistence and independent root-relative backup behavior."""

import uuid
from pathlib import Path

import pytest

from mackeep.config import ConfigError
from mackeep.mackeep import Mackeep
from mackeep.projects import ProjectProfile, ProjectStore, validate


@pytest.fixture
def project(home, tmp_path_factory):
    """Create a project outside HOME and an isolated storage configuration."""
    root = tmp_path_factory.mktemp("project")
    (home / ".mackeep.cfg").write_text(
        f"[storage]\nengine = file_system\npath = {home / 'storage'}\ndirectory = Mackeep\n",
    )
    return validate(
        {"id": str(uuid.uuid4()), "name": "Example", "root": str(root), "files": ["src"]}
    )


def test_project_backup_restore_preserves_exclusions(home, project):
    """Restore outside HOME and retain excluded local files."""
    root = Path(project["root"])
    (root / "src").mkdir()
    (root / "src/code").write_text("original")
    (root / "src/cache").write_text("secret")
    project["exclude"] = ["cache"]
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    backup = home / "storage/Mackeep/Project" / project["id"] / "src"
    assert (backup / "code").read_text() == "original"
    assert not (backup / "cache").exists()
    (root / "src/code").write_text("changed")
    profile.copy_files_from_mackeep_folder()
    assert (root / "src/code").read_text() == "original"
    assert (root / "src/cache").read_text() == "secret"


def test_store_rename_and_delete_retain_identity(home, project):
    """Definitions remain independent from application definitions."""
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.update(project)
    project["name"] = "Renamed"
    store.update(project)
    assert store.load() == [project]
    duplicate = {**project, "id": str(uuid.uuid4())}
    with pytest.raises(ConfigError, match="unique"):
        store.update(duplicate)
    assert store.load() == [project]
    store.update(None, project["id"])
    assert store.load() == []


@pytest.mark.parametrize("entry", ["../outside", "/absolute", "src/../../outside"])
def test_reject_escaping_entries(project, entry):
    """Relative paths cannot escape the selected project root."""
    with pytest.raises(ConfigError, match="relative"):
        validate({**project, "files": [entry]})


def test_dry_run_creates_nothing(home, project):
    """Planning must not initialize storage or project state."""
    root = Path(project["root"])
    (root / "src").write_text("data")
    profile = ProjectProfile(Mackeep(read_only=True), project, True, False)
    profile.copy_files_to_mackeep_folder()
    assert not (home / "storage/Mackeep").exists()


def cli(monkeypatch, capsys, *arguments):
    """Run real CLI parsing and decode every JSON document or event."""
    import json

    from mackeep_cli.main import main

    monkeypatch.setattr("sys.argv", ["mackeep-cli", "--json", *arguments])
    code = 0
    try:
        main()
    except SystemExit as exc:
        code = exc.code
    captured = capsys.readouterr()
    return code, [json.loads(line) for line in captured.out.splitlines()]


def test_cli_crud_and_global_toggle(home, project, monkeypatch, capsys):
    """Global backups include enabled projects without exposing them as applications."""
    import json

    config = home / ".mackeep.cfg"
    config.write_text(
        config.read_text() + "\n[applications_to_sync]\n\n[projects]\nenabled = true\n"
    )
    (home / "storage/Mackeep").mkdir()
    root = Path(project["root"])
    (root / "src").write_text("original")
    code, _ = cli(monkeypatch, capsys, "projects", "save", "--project-data=" + json.dumps(project))
    assert code == 0
    code, listed = cli(monkeypatch, capsys, "projects", "list")
    assert code == 0
    assert listed == [[project]]
    code, events = cli(monkeypatch, capsys, "backup")
    assert code == 0
    assert events[-1]["event"] == "done"
    backup = home / "storage/Mackeep/Project" / project["id"] / "src"
    assert backup.read_text() == "original"
    config.write_text(config.read_text().replace("enabled = true", "enabled = false"))
    (root / "src").write_text("new")
    code, _ = cli(monkeypatch, capsys, "backup")
    assert code == 0
    assert backup.read_text() == "original"
    assert ProjectStore(str(config)).load() == [project]
    code, _ = cli(monkeypatch, capsys, "projects", "backup")
    assert code != 0
    config.write_text(config.read_text().replace("enabled = false", "enabled = true"))
    code, _ = cli(monkeypatch, capsys, "--force", "projects", "restore", project["id"])
    assert code == 0
    assert (root / "src").read_text() == "original"
    code, _ = cli(monkeypatch, capsys, "projects", "delete", project["id"])
    assert code == 0
    assert backup.read_text() == "original"


def test_project_symlink_escape_rejected(home, project):
    """A selected path cannot follow a directory link outside the project."""
    root = Path(project["root"])
    (root / "src").symlink_to(home, target_is_directory=True)
    profile = ProjectProfile(Mackeep(), project, False, False)
    with pytest.raises(ConfigError, match="escapes"):
        profile.copy_files_to_mackeep_folder()
    assert not (home / "storage/Mackeep").exists()


def test_project_failure_retains_previous_snapshot(home, project, monkeypatch):
    """A failed copy preserves both the old snapshot and the local source."""
    from mackeep import utils

    root = Path(project["root"])
    (root / "src").write_text("original")
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    (root / "src").write_text("new")

    def fail(*_args, **_kwargs):
        raise OSError("injected failure")

    monkeypatch.setattr(utils, "copy", fail)
    profile.copy_files_to_mackeep_folder()
    assert profile.failed
    backup = home / "storage/Mackeep/Project" / project["id"] / "src"
    assert backup.read_text() == "original"
    assert (root / "src").read_text() == "new"


def test_full_project_restore_keeps_local_excluded_directory(project):
    """The dot entry selects the whole project without losing excluded data."""
    root = Path(project["root"])
    (root / "code").write_text("original")
    (root / ".cache").mkdir()
    (root / ".cache/local").write_text("keep")
    project.update(files=["."], exclude=[".cache/"])
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    (root / "code").write_text("changed")
    profile.copy_files_from_mackeep_folder()
    assert (root / "code").read_text() == "original"
    assert (root / ".cache/local").read_text() == "keep"


def test_removed_project_entry_cleans_only_owned_backup(home, project):
    """Project cleanup cannot delete another project's snapshot."""
    root = Path(project["root"])
    (root / "src").write_text("data")
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    other = {**project, "id": str(uuid.uuid4()), "name": "Other"}
    ProjectProfile(Mackeep(), other, False, False).copy_files_to_mackeep_folder()
    project["files"] = []
    ProjectProfile(Mackeep(), project, False, False).copy_files_to_mackeep_folder()
    base = home / "storage/Mackeep/Project"
    assert not (base / project["id"] / "src").exists()
    assert (base / other["id"] / "src").read_text() == "data"


def test_nested_symlink_is_copied_without_traversal(home, project):
    """Nested directory symlinks remain links instead of copying external files."""
    root = Path(project["root"])
    (root / "src").mkdir()
    (root / "src/link").symlink_to(home, target_is_directory=True)
    ProjectProfile(Mackeep(), project, False, False).copy_files_to_mackeep_folder()
    link = home / "storage/Mackeep/Project" / project["id"] / "src/link"
    assert link.is_symlink()
    assert link.readlink() == home


def test_project_restore_to_missing_source_root(project):
    """Restoring can recreate the configured root after it has been removed."""
    import shutil

    root = Path(project["root"])
    (root / "src").write_text("original")
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    shutil.rmtree(root)
    profile.copy_files_from_mackeep_folder()
    assert (root / "src").read_text() == "original"


def test_application_external_path_policy_is_unchanged(project):
    """Project roots outside HOME do not enable external application paths."""
    from mackeep.application import ApplicationProfile

    config = Mackeep()
    assert not config.config.allow_external_paths
    profile = ApplicationProfile(config, {project["root"] + "/src"}, False, False)
    with pytest.raises(ConfigError, match="External paths are disabled"):
        profile.preflight("copy_files_to_mackeep_folder")


def test_project_commit_failure_rolls_back(home, project, monkeypatch):
    """Failure during commit restores all earlier project replacements."""
    import os

    root = Path(project["root"])
    (root / "src").write_text("old")
    profile = ProjectProfile(Mackeep(), project, False, False)
    profile.copy_files_to_mackeep_folder()
    (root / "src").write_text("new")
    replace = os.replace

    def fail_state(source, destination):
        if str(destination).endswith("owners.json") and str(source).endswith("/new"):
            raise OSError("injected state commit failure")
        return replace(source, destination)

    monkeypatch.setattr(os, "replace", fail_state)
    profile.copy_files_to_mackeep_folder()
    assert profile.failed
    assert (home / "storage/Mackeep/Project" / project["id"] / "src").read_text() == "old"


def test_corrupt_store_does_not_overwrite_definitions(home, project):
    """Malformed persistent definitions fail visibly instead of silently resetting."""
    store = ProjectStore(str(home / ".mackeep.cfg"))
    store.path.write_text('[{"name": "missing id"}]')
    with pytest.raises(ConfigError, match="persistent identifiers"):
        store.update(project)
    assert store.path.read_text() == '[{"name": "missing id"}]'


def test_legacy_link_selection_never_includes_projects(home, project):
    """The new feature cannot route project data through legacy link operations."""
    from mackeep.appsdb import ApplicationsDatabase
    from mackeep_cli.main import _Context, _resolve_apps

    config = home / ".mackeep.cfg"
    config.write_text(
        config.read_text() + "\n[applications_to_sync]\n\n[projects]\nenabled = true\n"
    )
    ProjectStore(str(config)).update(project)
    context = _Context(str(config), Mackeep(), ApplicationsDatabase(), False, False)
    assert _resolve_apps(None, context) == set()
    assert _resolve_apps(None, context, include_projects=True) == {"project:" + project["id"]}


def test_application_cannot_overwrite_project_namespace(home, project, monkeypatch, capsys):
    """Protect retained project snapshots even when the feature is disabled."""
    config = home / ".mackeep.cfg"
    config.write_text(config.read_text() + "\n[applications_to_sync]\ncollision\n")
    custom = home / ".mackeep"
    custom.mkdir()
    (custom / "collision.cfg").write_text(
        "[application]\nname = Collision\n[configuration_files]\nProject\n"
    )
    (home / "Project").mkdir()
    (home / "Project/file").write_text("application")
    ProjectStore(str(config)).update(project)
    (home / "storage/Mackeep").mkdir()
    code, _ = cli(monkeypatch, capsys, "backup")
    assert code != 0
    assert not (home / "storage/Mackeep/Project").exists()


def test_unchecked_project_is_excluded_from_global_backup(home, project, monkeypatch, capsys):
    """Per-project selection is independent from the application selection."""
    config = home / ".mackeep.cfg"
    config.write_text(
        config.read_text() + "\n[applications_to_sync]\n\n[projects]\nenabled = true\n"
    )
    (home / "storage/Mackeep").mkdir()
    (Path(project["root"]) / "src").write_text("data")
    project["enabled"] = False
    ProjectStore(str(config)).update(project)
    code, _ = cli(monkeypatch, capsys, "backup")
    assert code == 0
    assert not (home / "storage/Mackeep/Project").exists()
    code, _ = cli(monkeypatch, capsys, "projects", "backup", project["id"])
    assert code == 0
    assert (home / "storage/Mackeep/Project" / project["id"] / "src").read_text() == "data"


def test_project_namespace_symlink_cannot_redirect_backup(home, project):
    """A storage symlink cannot redirect a project into another snapshot."""
    root = Path(project["root"])
    (root / "src").write_text("source")
    base = home / "storage/Mackeep/Project"
    base.mkdir(parents=True)
    other = base / "other"
    other.mkdir()
    (other / "src").write_text("keep")
    (base / project["id"]).symlink_to(other, target_is_directory=True)
    with pytest.raises(ConfigError, match="symbolic link"):
        ProjectProfile(Mackeep(), project, False, False).copy_files_to_mackeep_folder()
    assert (other / "src").read_text() == "keep"
