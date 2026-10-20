"""
The applications database.

The Applications Database provides an easy to use interface to load application
data from the Mackeep Database (files).
"""

import configparser
import os

from .config import ConfigError
from .constants import (
    APPS_DIR,
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    LEGACY_CUSTOM_APPS_DIR,
    LEGACY_CUSTOM_APPS_DIR_XDG,
)
from .utils import legacy_warning


class ApplicationsDatabase:
    """Database containing all the configured applications."""

    def __init__(self) -> None:
        """Create a ApplicationsDatabase instance."""
        # Build the dict that will contain the properties of each application
        self.apps: dict[str, dict[str, str | set[str] | list[str]]] = {}

        for config_file in ApplicationsDatabase.get_config_files():
            config: configparser.ConfigParser = configparser.ConfigParser(
                allow_no_value=True,
            )

            # Needed to not lowercase the configuration_files in the ini files
            config.optionxform = str  # type: ignore

            try:
                read: bool = bool(config.read(config_file))
            except configparser.Error as e:
                raise ConfigError(
                    f"Invalid application config file {config_file}: {e}",
                ) from e

            if read:
                try:
                    self._load_app(config, config_file)
                except configparser.Error as e:
                    raise ConfigError(
                        f"Invalid application config file {config_file}: {e}",
                    ) from e

    def _load_app(
        self, config: configparser.ConfigParser, config_file: str,
    ) -> None:
        """
        Load an application from its parsed config file.

        Args:
            config (configparser.ConfigParser): The parsed config file.
            config_file (str): The path of the config file.
        """
        # Get the filename without the directory name
        filename: str = os.path.basename(config_file)
        # The app name is the cfg filename with the extension
        app_name: str = filename[: -len(".cfg")]

        # Start building a dict for this app
        self.apps[app_name] = {}

        # Add the fancy name for the app, for display purpose
        app_pretty_name: str = config.get("application", "name")
        self.apps[app_name]["name"] = app_pretty_name

        # Keep track of the config file, to know where the app comes
        # from and to be able to report errors
        self.apps[app_name]["config_file"] = config_file

        # Add the configuration files to sync
        config_files: set[str] = set()
        self.apps[app_name]["configuration_files"] = config_files

        # Add the configuration files to sync, as listed in the
        # config file (without the XDG ones)
        home_files: set[str] = set()
        self.apps[app_name]["home_files"] = home_files
        if config.has_section("configuration_files"):
            for path in config.options("configuration_files"):
                if path.startswith("/"):
                    raise ValueError(
                        f"Unsupported absolute path: {path}",
                    )
                config_files.add(path)
                home_files.add(path)

        # Add the XDG configuration files to sync
        home: str = os.path.expanduser("~/")
        failobj: str = f"{home}.config"
        xdg_config_home: str = os.environ.get("XDG_CONFIG_HOME", failobj)
        if not xdg_config_home.startswith(home):
            raise ValueError(
                f"$XDG_CONFIG_HOME: {xdg_config_home} must be somewhere "
                f"within your home directory: {home}",
            )

        # The XDG configuration files, as listed in the config file
        xdg_files: set[str] = set()
        self.apps[app_name]["xdg_files"] = xdg_files
        if config.has_section("xdg_configuration_files"):
            for path in config.options("xdg_configuration_files"):
                if path.startswith("/"):
                    raise ValueError(
                        f"Unsupported absolute path: {path}",
                    )
                xdg_files.add(path)
                xdg_path = os.path.join(xdg_config_home, path)
                xdg_path = xdg_path.replace(home, "")
                config_files.add(xdg_path)

        # Add the exclusion rules
        self.apps[app_name]["exclude"] = self._parse_exclusions(
            config, "exclude", config_file,
        )
        self.apps[app_name]["xdg_exclude"] = self._parse_exclusions(
            config, "xdg_exclude", config_file,
        )

    @staticmethod
    def _parse_exclusions(
        config: configparser.ConfigParser,
        section: str,
        config_file: str,
    ) -> list[str]:
        """
        Parse an exclusion section of an application config file.

        The patterns are listed one per line, like the other sections of the
        config files. A pattern may also be given as a value, e.g.
        ``*.log = some log files``.

        Args:
            config (configparser.ConfigParser): The parsed config file.
            section (str): The name of the section to read.
            config_file (str): The path of the config file, for error
                               reporting.

        Returns:
            list of str: The exclusion patterns.
        """
        patterns: list[str] = []
        if not config.has_section(section):
            return patterns

        for option in config.options(section):
            value: str | None = config.get(section, option, raw=True)
            # A pattern listed without a value is the option itself.
            pattern: str = option if value is None else value
            pattern = pattern.strip()
            if not pattern:
                continue
            if pattern.startswith("/"):
                raise ConfigError(
                    f"Invalid exclusion pattern in {config_file}: "
                    f"unsupported absolute path: {pattern}",
                )
            patterns.append(pattern)

        return patterns

    @staticmethod
    def get_custom_apps_dirs() -> list[str]:
        """
        Return the directories where the custom application configs are read.

        Returns:
            list of str
        """
        home: str = os.environ["HOME"]
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME", os.path.join(home, ".config"),
        )
        return [
            os.path.join(home, CUSTOM_APPS_DIR),
            os.path.join(xdg_config_home, CUSTOM_APPS_DIR_XDG),
        ]

    @staticmethod
    def get_legacy_custom_apps_dirs() -> list[str]:
        """
        Return the legacy directories where the custom application configs
        are read, for backward compatibility.

        Returns:
            list of str
        """
        home: str = os.environ["HOME"]
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME", os.path.join(home, ".config"),
        )
        return [
            os.path.join(home, LEGACY_CUSTOM_APPS_DIR),
            os.path.join(xdg_config_home, LEGACY_CUSTOM_APPS_DIR_XDG),
        ]

    @staticmethod
    def get_config_files() -> set[str]:
        """
        Return the application configuration files.

        Return a list of configuration files describing the apps supported by
        Mackeep. The files returned are absolute full path to those files.
        e.g. /usr/lib/mackeep/applications/bash.cfg

        Only one config file per application should be returned, custom config
        having a priority over stock config. The Mackeep custom apps
        directories take priority over the XDG location and over the legacy
        Mackup ones.

        Returns:
            set of strings.
        """
        # Configure the config parser
        apps_dir: str = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), APPS_DIR,
        )

        # The directories of the custom application configs, the Mackeep
        # ones first, then the legacy Mackup ones.
        custom_dirs: list[str] = ApplicationsDatabase.get_custom_apps_dirs()
        legacy_dirs: list[str] = ApplicationsDatabase.get_legacy_custom_apps_dirs()

        # List of stock application config files
        config_files: set[str] = set()

        # Temp list of user added app config file names
        custom_files: set[str] = set()

        for directory in [*custom_dirs, *legacy_dirs]:
            if not os.path.isdir(directory):
                continue

            legacy: bool = directory in legacy_dirs
            for filename in sorted(os.listdir(directory)):
                if not filename.endswith(".cfg"):
                    continue
                if filename in custom_files:
                    # The first directory that holds an application wins.
                    continue
                path: str = os.path.join(directory, filename)
                config_files.add(path)
                custom_files.add(filename)

                if legacy and not _is_redundant(path, filename, apps_dir):
                    # The file is used, the user has to copy it. A file that
                    # is shadowed by a new one is not used at all, and a file
                    # that is the same as the one that replaces it does not
                    # have to be copied.
                    legacy_warning(
                        f"the application config {path} is used, copy it to"
                        " the new directory to use the new name",
                    )

        # Add the default provided app config files, but only if those are not
        # customized, as we don't want to overwrite custom app config.
        for filename in os.listdir(apps_dir):
            if filename.endswith(".cfg") and filename not in custom_files:
                config_files.add(os.path.join(apps_dir, filename))

        return config_files

    def get_name(self, name: str) -> str:
        """
        Return the fancy name of an application.

        Args:
            name (str)

        Returns:
            str
        """
        value = self.apps[name]["name"]
        assert isinstance(value, str)
        return value

    def get_files(self, name: str) -> set[str]:
        """
        Return the list of config files of an application.

        The XDG configuration files are included, as paths relative to the
        home directory.

        Args:
            name (str)

        Returns:
            set of str.
        """
        value = self.apps[name]["configuration_files"]
        assert isinstance(value, set)
        return value

    def get_home_files(self, name: str) -> set[str]:
        """
        Return the list of config files of an application, as listed in the
        [configuration_files] section of its config file.

        Args:
            name (str)

        Returns:
            set of str.
        """
        value = self.apps[name]["home_files"]
        assert isinstance(value, set)
        return value

    def get_xdg_files(self, name: str) -> set[str]:
        """
        Return the list of XDG config files of an application, as listed in
        the [xdg_configuration_files] section of its config file.

        The paths are relative to the XDG config home.

        Args:
            name (str)

        Returns:
            set of str.
        """
        value = self.apps[name]["xdg_files"]
        assert isinstance(value, set)
        return value

    def get_exclude(self, name: str) -> list[str]:
        """
        Return the exclusion patterns of an application.

        The patterns are relative to the home directory.

        Args:
            name (str)

        Returns:
            list of str.
        """
        value = self.apps[name]["exclude"]
        assert isinstance(value, list)
        return value

    def get_xdg_exclude(self, name: str) -> list[str]:
        """
        Return the XDG exclusion patterns of an application.

        The patterns are relative to the XDG config home.

        Args:
            name (str)

        Returns:
            list of str.
        """
        value = self.apps[name]["xdg_exclude"]
        assert isinstance(value, list)
        return value

    def get_config_file(self, name: str) -> str:
        """
        Return the path of the config file of an application.

        Args:
            name (str)

        Returns:
            str
        """
        value = self.apps[name]["config_file"]
        assert isinstance(value, str)
        return value

    def is_custom(self, name: str) -> bool:
        """
        Check if an application comes from a user defined config file.

        Args:
            name (str)

        Returns:
            bool
        """
        config_file: str = self.get_config_file(name)
        apps_dir: str = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), APPS_DIR,
        )
        return os.path.dirname(config_file) != apps_dir

    def get_app_names(self) -> set[str]:
        """
        Return application names.

        Return the list of application names that are available in the
        database.

        Returns:
            set of str.
        """
        app_names: set[str] = set()
        for name in self.apps:
            app_names.add(name)

        return app_names

    def get_pretty_app_names(self) -> set[str]:
        """
        Return the list of pretty app names that are available in the
        database.

        Returns:
            set of str.
        """
        pretty_app_names: set[str] = set()
        for app_name in self.get_app_names():
            pretty_app_names.add(self.get_name(app_name))

        return pretty_app_names


def _is_same_file(path: str, other: str) -> bool:
    """
    Whether two files have the same content.

    Args:
        path (str): The path of the first file.
        other (str): The path of the second file.

    Returns:
        bool
    """
    try:
        with open(path, "rb") as first, open(other, "rb") as second:
            return first.read() == second.read()
    except OSError:
        return False


def _is_redundant(path: str, filename: str, apps_dir: str) -> bool:
    """
    Whether a custom application config is the same as the one that replaces it.

    A config file that is the same as the default config of the application
    does not have to be copied to the new directory.

    Args:
        path (str): The path of the custom config file.
        filename (str): The name of the config file.
        apps_dir (str): The directory of the default config files.

    Returns:
        bool
    """
    default: str = os.path.join(apps_dir, filename)
    return os.path.isfile(default) and _is_same_file(path, default)
