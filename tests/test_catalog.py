"""Validate the actual bundled definitions without reading user configuration."""

import os
from pathlib import Path

import pytest

from mackeep import appsdb, utils
from mackeep.appsdb import ApplicationsDatabase
from mackeep.constants import APPS_DIR
from mackeep.inifile import read

CATALOG = Path(appsdb.__file__).parent / APPS_DIR
DEFINITIONS = sorted(CATALOG.glob("*.cfg"))


@pytest.mark.parametrize("definition", DEFINITIONS, ids=lambda path: path.stem)
def test_bundled_definition_is_valid(definition):
    """A malformed or unsafe shipped definition must fail by application name."""
    document = read(str(definition))
    assert document.read
    assert not document.problems, document.problems
    parser = document.parser
    assert parser.get("application", "name").strip()
    assert set(parser.sections()) <= {
        "application", "configuration_files", "xdg_configuration_files",
        "exclude", "xdg_exclude",
    }
    assert any(
        parser.has_section(section) and parser.options(section)
        for section in ("configuration_files", "xdg_configuration_files")
    ), "A bundled application must define files or folders to back up"
    for section in ("configuration_files", "xdg_configuration_files"):
        if not parser.has_section(section):
            continue
        for entry in parser.options(section):
            assert entry.strip(), (section, entry)
            assert not os.path.isabs(entry), (section, entry)
            assert not {".", ".."} & set(Path(entry).parts), (section, entry)
            assert entry.rstrip("/") != ".", (section, entry)


def test_all_bundled_applications_load_without_errors(home):
    """Exercise runtime validation, including exclusions, for the complete catalog."""
    assert DEFINITIONS, "The bundled catalog must not be empty"
    database = ApplicationsDatabase()
    assert database.get_app_names() == {path.stem for path in DEFINITIONS}
    for name in sorted(database.get_app_names()):
        assert database.get_error(name) is None, (name, database.get_error(name))


@pytest.mark.parametrize(("application", "entry"), [
    ("npm", ".npmrc"),
    ("composer", ".composer/auth.json"),
    ("codex", ".codex/auth.json"),
    ("opencode", ".local/share/opencode/auth.json"),
    ("gmailctl", ".gmailctl/credentials.json"),
    ("context7", ".context7/credentials.json"),
])
def test_catalog_credential_entries_are_marked_sensitive(home, application, entry):
    """Check real catalog entries, without guessing secrets from filename keywords."""
    document = read(str(CATALOG / f"{application}.cfg"))
    assert entry in document.parser.options("configuration_files")
    assert utils.sensitive_path_reason(str(home / entry)) is not None
