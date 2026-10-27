"""The publisher indexes actual contents and rejects invalid source files."""

import hashlib

import pytest

from mackeep.config import ConfigError
from mackeep.jsonapi import SCHEMA_VERSION
from tools.generate_library_manifest import generate

REVISION = "a" * 40


def test_manifest_pins_source_and_includes_names(tmp_path):
    definitions = tmp_path / "src/mackeep/applications"
    definitions.mkdir(parents=True)
    data = b"[application]\nname = New App\n[configuration_files]\n.file\n"
    (definitions / "new-app.cfg").write_bytes(data)
    result = generate(tmp_path, REVISION)
    assert result == {
        "version": 1,
        "schema_version": SCHEMA_VERSION,
        "revision": REVISION,
        "files": {"new-app.cfg": hashlib.sha256(data).hexdigest()},
        "names": {"new-app.cfg": "New App"},
    }
    assert result == generate(tmp_path, REVISION)


def test_manifest_requires_source_and_commit(tmp_path):
    with pytest.raises(ValueError, match="Git revision"):
        generate(tmp_path, "master")
    with pytest.raises(ValueError, match="No library definitions"):
        generate(tmp_path, REVISION)


@pytest.mark.parametrize("filename", ["invalid name.cfg", "Example.cfg"])
def test_manifest_rejects_unsafe_filename(tmp_path, filename):
    definitions = tmp_path / "src/mackeep/applications"
    definitions.mkdir(parents=True)
    (definitions / filename).write_text("[application]\nname = Example\n")
    with pytest.raises(ValueError, match="filename"):
        generate(tmp_path, REVISION)


def test_manifest_rejects_invalid_definition(tmp_path):
    definitions = tmp_path / "src/mackeep/applications"
    definitions.mkdir(parents=True)
    (definitions / "bad.cfg").write_text("[configuration_files]\n.file\n")
    with pytest.raises(ConfigError, match="Invalid library definition"):
        generate(tmp_path, REVISION)


def test_manifest_rejects_missing_final_newline(tmp_path):
    definitions = tmp_path / "src/mackeep/applications"
    definitions.mkdir(parents=True)
    (definitions / "bad.cfg").write_text("[application]\nname = Example")
    with pytest.raises(ValueError, match="final newline"):
        generate(tmp_path, REVISION)
