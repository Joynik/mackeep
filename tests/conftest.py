"""The fixtures shared by the tests."""

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
