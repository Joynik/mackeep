"""Tests for ApplicationsDatabase XDG support."""

import os
import unittest
from pathlib import Path

import pytest

from mackeep.appsdb import ApplicationsDatabase


class TestApplicationsDatabaseXDG(unittest.TestCase):
    """Test XDG Base Directory support for custom applications."""

    @pytest.fixture(autouse=True)
    def isolated_home(self, fixture_home):
        """Keep each database test independent of shared fixtures and environment."""
        self.fixtures_path = str(fixture_home)

    def test_legacy_custom_apps_dir(self):
        """Test that legacy ~/.mackeep/ directory is found."""
        # Don't set XDG_CONFIG_HOME, only legacy should be found
        config_files = ApplicationsDatabase.get_config_files()
        filenames = {os.path.basename(f) for f in config_files}

        assert "legacy-test-app.cfg" in filenames

    def test_xdg_custom_apps_dir(self):
        """Test that XDG custom apps directory is found."""
        xdg_config = os.path.join(self.fixtures_path, "xdg-config-home")
        os.environ["XDG_CONFIG_HOME"] = xdg_config

        config_files = ApplicationsDatabase.get_config_files()
        filenames = {os.path.basename(f) for f in config_files}

        assert "xdg-test-app.cfg" in filenames

    def test_legacy_takes_priority_over_xdg(self):
        """Test that legacy directory takes priority when same app exists."""
        xdg_config = os.path.join(self.fixtures_path, "xdg-config-home")
        os.environ["XDG_CONFIG_HOME"] = xdg_config

        config_files = ApplicationsDatabase.get_config_files()

        # Find the priority-test-app.cfg file
        priority_files = [f for f in config_files if "priority-test-app.cfg" in f]

        # Should only have one file (legacy should win)
        assert len(priority_files) == 1

        # Should be from legacy directory
        assert ".mackeep" in priority_files[0]
        assert "xdg-config-home" not in priority_files[0]

    def test_both_directories_merged(self):
        """Test that apps from both directories are available."""
        xdg_config = os.path.join(self.fixtures_path, "xdg-config-home")
        os.environ["XDG_CONFIG_HOME"] = xdg_config

        config_files = ApplicationsDatabase.get_config_files()
        filenames = {os.path.basename(f) for f in config_files}

        # Both unique apps should be present
        assert "legacy-test-app.cfg" in filenames
        assert "xdg-test-app.cfg" in filenames

    def test_xdg_default_fallback(self):
        """Test that XDG falls back to ~/.config when XDG_CONFIG_HOME is not set."""
        # Unset XDG_CONFIG_HOME - should fall back to ~/.config
        os.environ.pop("XDG_CONFIG_HOME", None)

        folder = Path(self.fixtures_path) / ".config/mackeep/applications"
        folder.mkdir(parents=True, exist_ok=True)
        definition = "[application]\nname = Default XDG\n[configuration_files]\n.demo\n"
        expected = folder / "default-xdg.cfg"
        expected.write_text(definition)
        unrelated = Path(self.fixtures_path) / "unrelated.cfg"
        unrelated.write_text(definition)
        files = ApplicationsDatabase.get_config_files()
        assert str(expected) in files
        assert str(unrelated) not in files
        database = ApplicationsDatabase()
        assert database.get_name("default-xdg") == "Default XDG"

    def test_applications_database_loads_xdg_apps(self):
        """Test that ApplicationsDatabase correctly loads apps from XDG."""
        xdg_config = os.path.join(self.fixtures_path, "xdg-config-home")
        os.environ["XDG_CONFIG_HOME"] = xdg_config

        db = ApplicationsDatabase()

        # XDG app should be loaded
        assert "xdg-test-app" in db.get_app_names()
        assert db.get_name("xdg-test-app") == "XDG Test App"

    def test_applications_database_priority_loads_legacy(self):
        """Test ApplicationsDatabase loads legacy version when app exists."""
        xdg_config = os.path.join(self.fixtures_path, "xdg-config-home")
        os.environ["XDG_CONFIG_HOME"] = xdg_config

        db = ApplicationsDatabase()

        # Priority app should load the legacy version
        assert "priority-test-app" in db.get_app_names()
        assert db.get_name("priority-test-app") == "Priority Test App Legacy"


if __name__ == "__main__":
    unittest.main()
