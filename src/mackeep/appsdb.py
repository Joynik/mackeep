"""
The applications database.

The Applications Database provides an easy to use interface to load application
data from the Mackeep Database (files).
"""

import configparser
import os

from .constants import (
    APPS_DIR,
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    LEGACY_CUSTOM_APPS_DIR,
    LEGACY_CUSTOM_APPS_DIR_XDG,
)
from .inifile import IniFile
from .inifile import read as read_ini
from .library import directory as library_directory
from .library import hidden_definitions
from .utils import legacy_warning


class ApplicationsDatabase:
    """Database containing all the configured applications."""

    def __init__(self, *, allow_external_paths: bool = False) -> None:
        """Create a ApplicationsDatabase instance."""
        self.allow_external_paths = allow_external_paths

        # Build the dict that will contain the properties of each application
        self.apps: dict[str, dict[str, str | set[str] | list[str]]] = {}

        # The errors of the applications, by application name
        self.errors: dict[str, str] = {}
        self.unsafe_paths: set[str] = set()

        for config_file in ApplicationsDatabase.get_config_files():
            self._load_config_file(config_file)

    def _load_config_file(self, config_file: str) -> None:
        """
        Load an application from its config file.

        A broken file does not stop the other applications from being loaded:
        the problem is reported for the application it belongs to.

        Args:
            config_file (str): The path of the config file.
        """
        try:
            file: IniFile = read_ini(
                config_file,
                allow_no_value=True,
                keep_case=True,
            )
        except configparser.Error as e:
            # The file cannot be parsed at all, the application is listed
            # with its error only.
            self._add_broken_app(
                config_file,
                [f"Invalid application config file {config_file}: {e}"],
            )
            return

        problems: list[str] = list(file.problems)
        if not file.read:
            if problems:
                self._add_broken_app(config_file, problems)
            return

        self._load_app(file.parser, config_file, problems)

    def _add_broken_app(self, config_file: str, problems: list[str]) -> None:
        """
        Add an application whose config file cannot be used.

        The application is listed, so the user can see it and fix it.

        Args:
            config_file (str): The path of the config file.
            problems (list of str): The problems of the file.
        """
        filename: str = os.path.basename(config_file)
        app_name: str = filename[: -len(".cfg")]

        self.apps[app_name] = {
            "name": app_name,
            "config_file": config_file,
            "configuration_files": set(),
            "home_files": set(),
            "xdg_files": set(),
            "exclude": [],
            "xdg_exclude": [],
        }
        if problems:
            self.errors[app_name] = "; ".join(problems)

    def _load_app(
        self,
        config: configparser.ConfigParser,
        config_file: str,
        problems: list[str],
    ) -> None:
        """
        Load an application from its parsed config file.

        Args:
            config (configparser.ConfigParser): The parsed config file.
            config_file (str): The path of the config file.
            problems (list of str): The problems of the file, they are
                                    filled with the ones of the application.
        """
        # Get the filename without the directory name
        filename: str = os.path.basename(config_file)
        # The app name is the cfg filename with the extension
        app_name: str = filename[: -len(".cfg")]

        # Start building a dict for this app
        self.apps[app_name] = {}

        # Add the fancy name for the app, for display purpose
        try:
            app_pretty_name: str = config.get("application", "name")
        except configparser.Error:
            # The name is missing, the identifier of the application is used
            # instead, and the problem is reported.
            app_pretty_name = app_name
            problems.append(
                f"Invalid application config file {config_file}: "
                "the name of the application is missing",
            )
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
                if not self.allow_external_paths and (
                    path.startswith("/") or ".." in path.split("/")
                ):
                    self.unsafe_paths.add(app_name)
                    problems.append(
                        f"Invalid path in {config_file}: "
                        + (
                            f"unsupported absolute path: {path}"
                            if path.startswith("/")
                            else f"parent traversal is disabled: {path}"
                        ),
                    )
                    continue
                config_files.add(path)
                home_files.add(path)

        # Add the XDG configuration files to sync
        home: str = os.path.expanduser("~/")
        failobj: str = f"{home}.config"
        xdg_config_home = os.path.abspath(
            os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", failobj)),
        )
        if not self.allow_external_paths and os.path.commonpath(
            (xdg_config_home, home),
        ) != home.rstrip(os.sep):
            raise ValueError(
                f"$XDG_CONFIG_HOME: {xdg_config_home} must be somewhere "
                f"within your home directory: {home}",
            )

        # The XDG configuration files, as listed in the config file
        xdg_files: set[str] = set()
        self.apps[app_name]["xdg_files"] = xdg_files
        if config.has_section("xdg_configuration_files"):
            for path in config.options("xdg_configuration_files"):
                if not self.allow_external_paths and (
                    path.startswith("/") or ".." in path.split("/")
                ):
                    self.unsafe_paths.add(app_name)
                    problems.append(
                        f"Invalid path in {config_file}: "
                        + (
                            f"unsupported absolute path: {path}"
                            if path.startswith("/")
                            else f"parent traversal is disabled: {path}"
                        ),
                    )
                    continue
                xdg_files.add(path)
                xdg_path = os.path.normpath(os.path.join(xdg_config_home, path))
                if os.path.commonpath((xdg_path, home)) == home.rstrip(os.sep):
                    xdg_path = os.path.relpath(xdg_path, home)
                config_files.add(xdg_path)

        # Add the exclusion rules
        exclude, exclude_problems = self._parse_exclusions(
            config,
            "exclude",
            config_file,
        )
        self.apps[app_name]["exclude"] = exclude
        problems.extend(exclude_problems)

        xdg_exclude, xdg_problems = self._parse_exclusions(
            config,
            "xdg_exclude",
            config_file,
        )
        self.apps[app_name]["xdg_exclude"] = xdg_exclude
        problems.extend(xdg_problems)

        # The problems of the file are reported for the application
        if problems:
            self.errors[app_name] = "; ".join(problems)

    @staticmethod
    def _parse_exclusions(
        config: configparser.ConfigParser,
        section: str,
        config_file: str,
    ) -> tuple[list[str], list[str]]:
        """
        Parse an exclusion section of an application config file.

        The patterns are listed one per line, like the other sections of the
        config files. A pattern may also be given as a value, e.g.
        ``*.log = some log files``.

        The patterns that are not valid are skipped, they do not stop the
        application from being used, and they are reported.

        Args:
            config (configparser.ConfigParser): The parsed config file.
            section (str): The name of the section to read.
            config_file (str): The path of the config file, for error
                               reporting.

        Returns:
            tuple of (the exclusion patterns, the problems of the section)
        """
        patterns: list[str] = []
        problems: list[str] = []
        if not config.has_section(section):
            return patterns, problems

        for option in config.options(section):
            value: str | None = config.get(section, option, raw=True)
            # A pattern listed without a value is the option itself.
            pattern: str = option if value is None else value
            pattern = pattern.strip()
            if not pattern:
                continue
            if pattern.startswith("/"):
                problems.append(
                    f"Invalid exclusion pattern in {config_file}: "
                    f"unsupported absolute path: {pattern}",
                )
                continue
            patterns.append(pattern)

        return patterns, problems

    @staticmethod
    def get_custom_apps_dir() -> str:
        """
        Return the main directory of the custom application configs.

        It is the directory of the user, in the home directory.

        Returns:
            str
        """
        return os.path.join(os.path.expanduser("~"), CUSTOM_APPS_DIR)

    @staticmethod
    def get_custom_apps_dirs() -> list[str]:
        """
        Return the directories where the custom application configs are read.

        Returns:
            list of str
        """
        home: str = os.path.expanduser("~")
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME", os.path.join(home, ".config"),
        )
        return [
            ApplicationsDatabase.get_custom_apps_dir(),
            os.path.join(xdg_config_home, CUSTOM_APPS_DIR_XDG),
        ]

    @staticmethod
    def get_legacy_custom_apps_dirs_pairs() -> list[tuple[str, str]]:
        """
        Return the legacy directories of the custom application configs and
        the ones that replace them.

        Returns:
            list of (str, str): The legacy directory and the new one.
        """
        home: str = os.path.expanduser("~")
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME", os.path.join(home, ".config"),
        )
        return [
            (
                os.path.join(home, LEGACY_CUSTOM_APPS_DIR),
                os.path.join(home, CUSTOM_APPS_DIR),
            ),
            (
                os.path.join(xdg_config_home, LEGACY_CUSTOM_APPS_DIR_XDG),
                os.path.join(xdg_config_home, CUSTOM_APPS_DIR_XDG),
            ),
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
        directory takes priority over the XDG location.

        The legacy Mackup directories are not read any more. The user is
        warned about the configs they hold, so he can migrate them.

        Returns:
            set of strings.
        """
        # Configure the config parser
        apps_dir: str = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), APPS_DIR,
        )

        # The directories of the custom application configs, the Mackeep
        # ones first, then the XDG location.
        custom_dirs: list[str] = ApplicationsDatabase.get_custom_apps_dirs()

        # List of stock application config files
        config_files: set[str] = set()

        # Temp list of user added app config file names
        custom_files: set[str] = set()

        for directory in custom_dirs:
            if not os.path.isdir(directory):
                continue

            for filename in sorted(os.listdir(directory)):
                if not filename.endswith(".cfg"):
                    continue
                if filename in custom_files:
                    # The first directory that holds an application wins.
                    continue
                path: str = os.path.join(directory, filename)
                config_files.add(path)
                custom_files.add(filename)

        # The legacy directories are not read any more, the user is told
        # about the configs they have to migrate.
        for legacy_dir, new_dir in (
            ApplicationsDatabase.get_legacy_custom_apps_dirs_pairs()
        ):
            if not os.path.isdir(legacy_dir):
                continue
            count: int = _count_configs_to_migrate(
                legacy_dir, custom_dirs, apps_dir,
            )
            if count == 0:
                # There is nothing to migrate, every config is either
                # shadowed by a new one or the same as the default one.
                continue
            legacy_warning(
                f"the custom applications in {legacy_dir} are not read any"
                f" more ({count} files), copy them to {new_dir} to use them",
            )

        managed_dir = library_directory()
        removed_files = hidden_definitions()
        if managed_dir.is_dir():
            for managed_path in sorted(managed_dir.glob("*.cfg")):
                if (
                    managed_path.is_file()
                    and managed_path.name not in custom_files | removed_files
                ):
                    config_files.add(str(managed_path))
                    custom_files.add(managed_path.name)

        # Add the default provided app config files, but only if those are not
        # customized, as we don't want to overwrite custom app config.
        for filename in os.listdir(apps_dir):
            if (
                filename.endswith(".cfg")
                and filename not in custom_files | removed_files
            ):
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

    def get_error(self, name: str) -> str | None:
        """
        Return the error of an application, when it has one.

        The broken rules of the config file are skipped, the application is
        still used, and the problem is reported here.

        Args:
            name (str)

        Returns:
            str or None: The reason why the config file is not fully used.
        """
        return self.errors.get(name)

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
        return os.path.dirname(config_file) not in {apps_dir, str(library_directory())}

    def get_app_names(self) -> set[str]:
        """
        Return application names.

        Return the list of application names that are available in the
        database.

        Returns:
            set of str.
        """
        return set(self.apps)

    def get_pretty_app_names(self) -> set[str]:
        """
        Return the list of pretty app names that are available in the
        database.

        Returns:
            set of str.
        """
        return {self.get_name(app_name) for app_name in self.apps}


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


def _count_configs_to_migrate(
    legacy_dir: str, custom_dirs: list[str], apps_dir: str,
) -> int:
    """
    Count the legacy application configs that have to be copied.

    A config file that is shadowed by a new one with the same name is not
    used any more, and a config file that is the same as the default config
    of the application does not have to be copied.

    Args:
        legacy_dir (str): The legacy directory of the config files.
        custom_dirs (list of str): The directories of the new config files.
        apps_dir (str): The directory of the default config files.

    Returns:
        int
    """
    names: set[str] = set()
    for directory in custom_dirs:
        if not os.path.isdir(directory):
            continue
        names.update(
            filename
            for filename in os.listdir(directory)
            if filename.endswith(".cfg")
        )

    count: int = 0
    for filename in sorted(os.listdir(legacy_dir)):
        if not filename.endswith(".cfg"):
            continue
        if filename in names:
            # The file is shadowed by a new one, it is not used.
            continue
        if _is_redundant(
            os.path.join(legacy_dir, filename), filename, apps_dir,
        ):
            # The file is the same as the default one, nothing to copy.
            continue
        count += 1
    return count


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
