"""The fixtures shared by the tests."""

import os
import shutil
from pathlib import Path
from unittest.mock import patch

import pytest

from mackeep import utils


@pytest.fixture(autouse=True)
def clear_warnings():
    """The legacy warnings are kept in a module level list."""
    utils.LEGACY_WARNINGS.clear()
    utils.SENSITIVE_WARNINGS.clear()
    yield
    utils.LEGACY_WARNINGS.clear()
    utils.SENSITIVE_WARNINGS.clear()


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Set up a temporary home directory."""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".config"))
    monkeypatch.delenv("MACKEEP_CONFIG", raising=False)

    utils.FORCE_YES = True
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = True

    storage = tmp_path / "storage"
    storage.mkdir(exist_ok=True)

    yield tmp_path

    utils.FORCE_YES = False
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = False


@pytest.fixture
def fixture_home(home):
    """Copy read-only input fixtures into an isolated, writable HOME."""
    fixtures = Path(__file__).parent / "fixtures"
    original = {
        p.relative_to(fixtures): p.read_bytes()
        for p in fixtures.rglob("*")
        if p.is_file()
    }
    shutil.copytree(fixtures, home, dirs_exist_ok=True)
    with patch.dict(os.environ):
        os.environ.pop("XDG_CONFIG_HOME", None)
        os.environ.pop("MACKEEP_CONFIG", None)
        yield home
    assert {
        p.relative_to(fixtures): p.read_bytes()
        for p in fixtures.rglob("*")
        if p.is_file()
    } == original
