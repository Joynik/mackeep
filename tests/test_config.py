import contextlib
import os
import os.path
import unittest
from pathlib import Path

import pytest

from mackeep.config import Config, ConfigError
from mackeep.constants import (
    ENGINE_DROPBOX,
    ENGINE_FS,
    ENGINE_GDRIVE,
    ENGINE_ICLOUD,
    ENGINE_UNCONFIGURED,
    MACKEEP_CONFIG_FILE,
)


def assert_correct_config_read(expected_directory):
    assert expected_directory == Config().directory


@pytest.mark.usefixtures("fixture_home")
class TestConfig(unittest.TestCase):
    def test_config_envvar(self):
        os.environ["MACKEEP_CONFIG"] = "~/mackeep-envarcheck.cfg"
        assert_correct_config_read("test_config_envvar")

    def test_config_xdg(self):
        os.environ["XDG_CONFIG_HOME"] = "~/xdg-config-home/"
        assert_correct_config_read("test_config_xdg")

    def test_config_find_correct_default(self):
        config_path = Path.home() / MACKEEP_CONFIG_FILE

        try:
            # create a default config file, this must be cleaned up after the test
            config_path.write_text("[storage]\ndirectory = test_config_default")

            # nothing else set, should find the default file
            assert_correct_config_read("test_config_default")

            # set MACKEEP_CONFIG, but should still find the default file
            os.environ["MACKEEP_CONFIG"] = "~/mackeep-envarcheck.cfg"
            assert_correct_config_read("test_config_default")

            # set XDG_CONFIG_HOME, but should still find the default file
            os.environ["XDG_CONFIG_HOME"] = "~/xdg-config-home/"
            assert_correct_config_read("test_config_default")
        except Exception:
            raise
        finally:
            config_path.unlink(missing_ok=True)

        assert config_path.exists() is False

    def test_config_finds_correct_envvar(self):
        # set XDG_CONFIG_HOME, should find the XDG config file
        os.environ["XDG_CONFIG_HOME"] = "~/xdg-config-home/"
        assert_correct_config_read("test_config_xdg")

        # set MACKEEP_CONFIG, should find the MACKEEP_CONFIG file
        os.environ["MACKEEP_CONFIG"] = "~/mackeep-envarcheck.cfg"
        assert_correct_config_read("test_config_envvar")

    def test_config_file_is_created(self):
        """The config file is created when it does not exist."""
        config_path = Path.home() / MACKEEP_CONFIG_FILE
        config_path.unlink(missing_ok=True)

        # The storage of the machine is not used, the config can be read
        # without it
        with contextlib.suppress(SystemExit):
            Config()

        assert config_path.is_file()
        assert "directory = Mackeep" in config_path.read_text()

    def test_config_no_config(self):
        cfg = Config()

        # Should should do the same as the default, empty configuration
        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_UNCONFIGURED

        assert isinstance(cfg.path, str)
        print(cfg.path)
        assert cfg.path == ""

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == ""

        assert cfg.apps_to_ignore == set()
        assert cfg.apps_to_sync == set()

    def test_config_empty(self):
        cfg = Config("mackeep-empty.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_DROPBOX

        assert isinstance(cfg.path, str)
        assert cfg.path == "/home/some_user/Dropbox"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/home/some_user/Dropbox/Mackeep"

        assert cfg.apps_to_ignore == set()
        assert cfg.apps_to_sync == set()

    def test_config_engine_dropbox(self):
        cfg = Config("mackeep-engine-dropbox.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_DROPBOX

        assert isinstance(cfg.path, str)
        assert cfg.path == "/home/some_user/Dropbox"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "some_weirld_name"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/home/some_user/Dropbox/some_weirld_name"

        assert cfg.apps_to_ignore == set()
        assert cfg.apps_to_sync == set()

    def test_config_engine_filesystem_absolute(self):
        cfg = Config("mackeep-engine-file_system-absolute.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_FS

        assert isinstance(cfg.path, str)
        assert cfg.path == "/some/absolute/folder"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "custom_folder"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/some/absolute/folder/custom_folder"

        assert cfg.apps_to_ignore == {"subversion", "sequel-pro"}
        assert cfg.apps_to_sync == set()

    def test_config_engine_filesystem(self):
        cfg = Config("mackeep-engine-file_system.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_FS

        assert isinstance(cfg.path, str)
        assert cfg.path.endswith(
            os.path.join(os.environ["HOME"], "some/relative/folder"),
        )

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == os.path.join(
            os.environ["HOME"],
            "some/relative/folder",
            "Mackeep",
        )

        assert cfg.apps_to_ignore == set()
        assert cfg.apps_to_sync == {"sabnzbd", "sublime-text-3", "x11"}

    def test_config_engine_google_drive(self):
        cfg = Config("mackeep-engine-google_drive.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_GDRIVE

        assert isinstance(cfg.path, str)
        assert cfg.path == "/Users/whatever/Google Drive"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath.endswith("/Google Drive/Mackeep")

        assert cfg.apps_to_ignore == {"subversion", "sequel-pro", "sabnzbd"}
        assert cfg.apps_to_sync == {"sublime-text-3", "x11", "sabnzbd"}

    def test_config_engine_icloud(self):
        cfg = Config("mackeep-engine-icloud.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_ICLOUD

        assert isinstance(cfg.path, str)
        assert cfg.path == os.path.expanduser(
            "~/Library/Mobile Documents/com~apple~CloudDocs/",
        )

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath.endswith("/com~apple~CloudDocs/Mackeep")

        assert cfg.apps_to_ignore == {"subversion", "sequel-pro", "sabnzbd"}
        assert cfg.apps_to_sync == {"sublime-text-3", "x11", "sabnzbd"}

    def test_config_engine_filesystem_no_path(self):
        with pytest.raises(ConfigError):
            Config("mackeep-engine-file_system-no_path.cfg")

    def test_config_engine_unknown(self):
        with pytest.raises(ConfigError):
            Config("mackeep-engine-unknown.cfg")

    def test_config_apps_to_ignore(self):
        cfg = Config("mackeep-apps_to_ignore.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_DROPBOX

        assert isinstance(cfg.path, str)
        assert cfg.path == "/home/some_user/Dropbox"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/home/some_user/Dropbox/Mackeep"

        assert cfg.apps_to_ignore == {"subversion", "sequel-pro", "sabnzbd"}
        assert cfg.apps_to_sync == set()

    def test_config_apps_to_sync(self):
        cfg = Config("mackeep-apps_to_sync.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_DROPBOX

        assert isinstance(cfg.path, str)
        assert cfg.path == "/home/some_user/Dropbox"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/home/some_user/Dropbox/Mackeep"

        assert cfg.apps_to_ignore == set()
        assert cfg.apps_to_sync == {"sabnzbd", "sublime-text-3", "x11"}

    def test_config_apps_to_ignore_and_sync(self):
        cfg = Config("mackeep-apps_to_ignore_and_sync.cfg")

        assert isinstance(cfg.engine, str)
        assert cfg.engine == ENGINE_DROPBOX

        assert isinstance(cfg.path, str)
        assert cfg.path == "/home/some_user/Dropbox"

        assert isinstance(cfg.directory, str)
        assert cfg.directory == "Mackeep"

        assert isinstance(cfg.fullpath, str)
        assert cfg.fullpath == "/home/some_user/Dropbox/Mackeep"

        assert cfg.apps_to_ignore == {"subversion", "sequel-pro", "sabnzbd"}
        assert cfg.apps_to_sync == {"sabnzbd", "sublime-text-3", "x11", "vim"}

    def test_config_old_config(self):
        with pytest.raises(SystemExit):
            Config("mackeep-old-config.cfg")
