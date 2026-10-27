"""Isolated library publishing, downloads and definition precedence."""

# ruff: noqa: SLF001 - exercise the bounded network boundary directly

import hashlib
import json
from io import BytesIO, StringIO
from unittest.mock import patch

import pytest

from mackeep import library
from mackeep.appsdb import ApplicationsDatabase
from mackeep.config import ConfigError
from mackeep.jsonapi import SCHEMA_VERSION
from mackeep_cli.main import main

OLD = b"[application]\nname = Example\n[configuration_files]\n.old\n"
NEW = b"[application]\nname = Example\n[configuration_files]\n.new\n"
REVISION = "a" * 40


@pytest.fixture
def catalog(home, monkeypatch):
    """Keep both bundled and downloaded definitions inside the test HOME."""
    bundled = home / "bundled"
    bundled.mkdir()
    (bundled / "example.cfg").write_bytes(OLD)
    monkeypatch.setattr(library, "bundled_directory", lambda: bundled)
    manifest = {
        "version": 1,
        "schema_version": 4,
        "revision": REVISION,
        "files": {"example.cfg": hashlib.sha256(NEW).hexdigest()},
    }

    def download(url, _limit):
        if url == library.MANIFEST_URL:
            return json.dumps(manifest).encode()
        assert (
            url == f"{library.SOURCE}/{REVISION}/src/mackeep/applications/example.cfg"
        )
        return NEW

    monkeypatch.setattr(library, "_download", download)
    return manifest


def test_check_is_read_only(catalog):
    result = library.check()
    assert result["schema_version"] == SCHEMA_VERSION
    assert result["revision"] == REVISION
    assert result["checked_at"]
    assert result["updates"] == [
        {"name": "example", "sha256": hashlib.sha256(NEW).hexdigest()},
    ]
    assert not library.directory().exists()


def test_update_replaces_only_changes(catalog, monkeypatch):
    result = library.update()
    assert result["updates"] == []
    assert (library.directory() / "example.cfg").read_bytes() == NEW
    assert not list(library.directory().glob(".download-*"))
    calls = []

    def download(url, _limit):
        calls.append(url)
        return json.dumps(catalog).encode()

    monkeypatch.setattr(library, "_download", download)
    library.update()
    assert calls == [library.MANIFEST_URL]


def test_new_definition(catalog):
    (library.bundled_directory() / "example.cfg").unlink()
    assert library.check()["updates"]
    assert library.update()["updates"] == []


def test_checksum_failure_preserves_active_file(catalog):
    library.directory().mkdir(parents=True)
    target = library.directory() / "example.cfg"
    target.write_bytes(OLD)
    catalog["files"]["example.cfg"] = "b" * 64
    with pytest.raises(ConfigError, match="checksum mismatch"):
        library.update()
    assert target.read_bytes() == OLD
    assert not list(library.directory().glob(".download-*"))


def test_download_failure_preserves_active_file(catalog, monkeypatch):
    original = library._download

    def download(url, limit):
        if url != library.MANIFEST_URL:
            raise OSError("offline")
        return original(url, limit)

    monkeypatch.setattr(library, "_download", download)
    with pytest.raises(OSError, match="offline"):
        library.update()
    assert not (library.directory() / "example.cfg").exists()


@pytest.mark.parametrize(
    "data",
    [b"not ini", b"\xff", b"[application]\n", b"[application]\nname=\n"],
)
def test_reject_invalid_definition(data):
    with pytest.raises(ConfigError):
        library.validate_definition(data)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("version", 99),
        ("schema_version", 99),
        ("revision", "../master"),
        ("revision", None),
        ("files", []),
        ("files", {}),
        ("files", {"../bad.cfg": "a" * 64}),
        ("files", {"good.cfg": "not a checksum"}),
    ],
)
def test_reject_invalid_manifest(catalog, field, value):
    catalog[field] = value
    with pytest.raises(ConfigError):
        library.check()
    assert not library.directory().exists()


@pytest.mark.parametrize("data", [b"[]", b"invalid", b"\xff"])
def test_reject_invalid_json(home, monkeypatch, data):
    monkeypatch.setattr(library, "_download", lambda *_args: data)
    with pytest.raises(ConfigError):
        library.check()


def test_download_size_and_timeout(monkeypatch):
    calls = []

    def open_url(url, timeout):
        calls.append((url, timeout))
        return BytesIO(b"1234")

    monkeypatch.setattr(library, "urlopen", open_url)
    assert library._download(library.MANIFEST_URL, 4) == b"1234"
    with pytest.raises(ConfigError, match="size limit"):
        library._download(library.MANIFEST_URL, 3)
    assert calls == [(library.MANIFEST_URL, 20)] * 2


def test_custom_overrides_managed_library(home, catalog):
    library.update()
    db = ApplicationsDatabase()
    assert db.get_files("example") == {".new"}
    assert not db.is_custom("example")
    custom = home / ".mackeep"
    custom.mkdir()
    (custom / "example.cfg").write_bytes(OLD)
    db = ApplicationsDatabase()
    assert db.get_files("example") == {".old"}
    assert db.is_custom("example")
    assert (custom / "example.cfg").read_bytes() == OLD


def test_xdg_custom_overrides_managed(home, catalog):
    library.update()
    custom = home / ".config/mackeep/applications"
    custom.mkdir(parents=True)
    (custom / "example.cfg").write_bytes(OLD)
    db = ApplicationsDatabase()
    assert db.get_files("example") == {".old"}
    assert db.is_custom("example")


@pytest.mark.parametrize("action", ["check", "update"])
def test_cli_library_json_without_storage(catalog, monkeypatch, capsys, action):
    monkeypatch.setattr("sys.argv", ["mackeep", "--json", "library", action])
    main()
    result = json.loads(capsys.readouterr().out)
    assert result["schema_version"] == SCHEMA_VERSION
    assert bool(result["updates"]) == (action == "check")


def test_cli_library_dry_run_does_not_write(catalog, monkeypatch, capsys):
    monkeypatch.setattr(
        "sys.argv",
        ["mackeep", "--json", "--dry-run", "library", "update"],
    )
    with pytest.raises(SystemExit) as error:
        main()
    assert error.value.code == 1
    assert "error" in json.loads(capsys.readouterr().out)
    assert not library.directory().exists()


def test_cli_network_failure_is_error(catalog, monkeypatch):
    monkeypatch.setattr(
        library,
        "_download",
        lambda *_args: (_ for _ in ()).throw(OSError("offline")),
    )
    monkeypatch.setattr("sys.argv", ["mackeep", "--json", "library", "check"])
    stdout = StringIO()
    with patch("sys.stdout", stdout), pytest.raises(SystemExit) as error:
        main()
    assert error.value.code == 1
    assert "offline" in json.loads(stdout.getvalue())["error"]["message"]


def test_new_definition_has_display_name_before_download(catalog):
    catalog["names"] = {"example.cfg": "Example App"}
    (library.bundled_directory() / "example.cfg").unlink()
    assert library.check()["new"] == [
        {"name": "example", "display_name": "Example App"},
    ]
    assert library.update()["new"] == []


def test_retired_definition_is_kept_until_manual_removal(home, catalog):
    library.update()
    settings = home / ".new"
    settings.write_text("personal settings")
    backup = home / "storage/example"
    backup.write_text("existing backup")
    catalog["files"] = {"other.cfg": "b" * 64}
    status = library.check()
    assert status["removed"] == ["example"]
    assert (library.directory() / "example.cfg").read_bytes() == NEW
    status = library.remove("example")
    assert status["removed"] == []
    assert not (library.directory() / "example.cfg").exists()
    assert "example.cfg" in library.hidden_definitions()
    assert settings.read_text() == "personal settings"
    assert backup.read_text() == "existing backup"
    assert "example" not in ApplicationsDatabase().get_app_names()


def test_remove_bundled_definition_hides_without_writing_bundle(home, catalog):
    catalog["files"] = {"other.cfg": "b" * 64}
    # Use an actual bundled name to test the database's fallback suppression.
    (library.bundled_directory() / "vim.cfg").write_bytes(OLD)
    assert "vim" in ApplicationsDatabase().get_app_names()
    library.remove("vim")
    assert "vim" not in ApplicationsDatabase().get_app_names()
    assert (library.bundled_directory() / "vim.cfg").read_bytes() == OLD
    custom = home / ".mackeep"
    custom.mkdir()
    (custom / "vim.cfg").write_bytes(NEW)
    assert ApplicationsDatabase().is_custom("vim")


def test_active_or_unknown_definitions_cannot_be_removed(catalog):
    with pytest.raises(ConfigError, match="still available"):
        library.remove("example")
    with pytest.raises(ConfigError, match="Unknown"):
        library.remove("missing")
    with pytest.raises(ConfigError, match="Invalid"):
        library.remove("../escape")


def test_selected_retired_definition_cannot_be_removed(home, catalog):
    (home / ".mackeep.cfg").write_text("[applications_to_sync]\nexample\n")
    catalog["files"] = {"other.cfg": "b" * 64}
    with pytest.raises(ConfigError, match="backup selection"):
        library.remove("example")
    assert not library.directory().exists()


def test_reintroduced_definition_can_be_downloaded_again(catalog):
    catalog["files"] = {"other.cfg": "b" * 64}
    library.remove("example")
    catalog["files"] = {"example.cfg": hashlib.sha256(OLD).hexdigest()}
    assert library.check()["new"] == [{"name": "example", "display_name": "example"}]
    # OLD equals bundled content, but explicit download must undo the removal.
    with patch.object(
        library,
        "_download",
        side_effect=[json.dumps(catalog).encode(), OLD],
    ):
        assert library.update("example")["updates"] == []
    assert not library.hidden_definitions()
    assert "example" in ApplicationsDatabase().get_app_names()


def test_single_update_keeps_other_pending_updates(catalog):
    catalog["files"]["other.cfg"] = "b" * 64
    status = library.update("example")
    assert [item["name"] for item in status["updates"]] == ["other"]
    with pytest.raises(ConfigError, match="Unknown"):
        library.update("missing")


def test_invalid_download_does_not_replace_definition(catalog):
    invalid = b"[application]\n"
    catalog["files"]["example.cfg"] = hashlib.sha256(invalid).hexdigest()
    with (
        patch.object(
            library,
            "_download",
            side_effect=[json.dumps(catalog).encode(), invalid],
        ),
        pytest.raises(ConfigError, match="Invalid library definition"),
    ):
        library.update()
    assert not (library.directory() / "example.cfg").exists()


def test_stages_all_downloads_before_replacing_any(catalog):
    catalog["files"]["second.cfg"] = "b" * 64
    with (
        patch.object(
            library,
            "_download",
            side_effect=[json.dumps(catalog).encode(), NEW, OSError("offline")],
        ),
        pytest.raises(OSError, match="offline"),
    ):
        library.update()
    assert not (library.directory() / "example.cfg").exists()


@pytest.mark.parametrize("component", [".local", ".local/share/mackeep/library"])
def test_linked_library_paths_cannot_be_written(home, catalog, component):
    outside = home / "outside"
    outside.mkdir()
    linked = home / component
    linked.parent.mkdir(parents=True, exist_ok=True)
    linked.symlink_to(outside, target_is_directory=True)
    with pytest.raises(ConfigError, match="symbolic links"):
        library.update()
    catalog["files"] = {"other.cfg": "b" * 64}
    with pytest.raises(ConfigError, match="symbolic links"):
        library.remove("example")
    assert not list(outside.iterdir())


@pytest.mark.parametrize(
    "rule",
    [
        "[configuration_files]\n../secret\n",
        "[xdg_configuration_files]\n/secret\n",
        "[exclude]\n/secret\n",
        "[xdg_exclude]\npattern = /secret\n",
    ],
)
def test_reject_unsafe_library_rules(rule):
    with pytest.raises(ConfigError):
        library.validate_definition(("[application]\nname = Example\n" + rule).encode())


@pytest.mark.parametrize(
    "data", [b"[application]\nname\n", b"[application]\nname=%(missing)s\n"],
)
def test_reject_unusable_names(data):
    with pytest.raises(ConfigError):
        library.validate_definition(data)


@pytest.mark.parametrize("value", ["not json", "{}", '["../escape.cfg"]'])
def test_invalid_removal_index_is_visible_error(home, value):
    library.directory().mkdir(parents=True)
    (library.directory() / "removed.json").write_text(value)
    with pytest.raises(ConfigError, match="removed library"):
        library.hidden_definitions()


def test_cli_downloads_one_new_definition(catalog, monkeypatch, capsys):
    catalog["files"]["other.cfg"] = "b" * 64
    monkeypatch.setattr(
        "sys.argv", ["mackeep", "--json", "library", "update", "example"],
    )
    main()
    result = json.loads(capsys.readouterr().out)
    assert [item["name"] for item in result["updates"]] == ["other"]
    assert (library.directory() / "example.cfg").read_bytes() == NEW


def test_cli_removes_retired_definition(catalog, monkeypatch, capsys):
    catalog["files"] = {"other.cfg": "b" * 64}
    monkeypatch.setattr(
        "sys.argv", ["mackeep", "--json", "library", "remove", "example"],
    )
    main()
    result = json.loads(capsys.readouterr().out)
    assert result["removed"] == []
    assert "example.cfg" in library.hidden_definitions()
