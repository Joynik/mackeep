"""Package used to manage the .mackeep.cfg config file."""

import os
import os.path
from pathlib import Path
from typing import TYPE_CHECKING

from .constants import (
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    DOCUMENTATION_URL,
    ENGINE_DROPBOX,
    ENGINE_FS,
    ENGINE_GDRIVE,
    ENGINE_ICLOUD,
    ENGINE_UNCONFIGURED,
    MACKEEP_BACKUP_PATH,
    MACKEEP_CONFIG_FILE,
)
from .inifile import IniFile
from .inifile import read as read_ini
from .utils import (
    error,
    get_dropbox_folder_location,
    get_google_drive_folder_location,
    get_icloud_folder_location,
)

if TYPE_CHECKING:
    import configparser


class Config:
    """The Mackeep Config class."""

    def __init__(self, filename: str | None = None, *, read_only: bool = False) -> None:
        """
        Create a Config instance.

        Args:
            filename (str): Optional filename of the config file. If empty,
                            defaults to MACKEEP_CONFIG_FILE
        """
        assert isinstance(filename, str) or filename is None

        self.read_only = read_only

        # The problems of the config file, they do not stop Mackeep
        self._errors: list[str] = []

        # Initialize the parser
        self._parser = self._setup_parser(filename)

        # Initialize the parser of the exclusion rules. The patterns are
        # case sensitive, so their case must be preserved.
        self._exclusion_parser = self._setup_exclusion_parser()

        # Do we have an old config file?
        self._warn_on_old_config()

        # Get the storage engine
        self._engine = self._parse_engine()

        # Get the path where the Mackeep folder is
        self._path = self._parse_path()

        # Get the directory replacing 'Mackeep', if any
        self._directory = self._parse_directory()

        # Get the list of apps to ignore
        self._apps_to_ignore = self._parse_apps_to_ignore()

        # Get the list of apps to allow
        self._apps_to_sync = self._parse_apps_to_sync()

        # Get the global exclusion rules, applied to every application
        self._global_exclude = self._parse_exclusions("exclude")
        self._global_xdg_exclude = self._parse_exclusions("xdg_exclude")

    @property
    def allow_external_paths(self) -> bool:
        """Whether application entries may leave their HOME/XDG root."""
        try:
            return self._parser.getboolean(
                "security", "allow_external_paths", fallback=False,
            )
        except ValueError as exc:
            raise ConfigError("allow_external_paths must be true or false") from exc

    @property
    def engine(self) -> str:
        """
        The engine used by the storage.

        ENGINE_DROPBOX, ENGINE_GDRIVE, ENGINE_ICLOUD or ENGINE_FS.

        Returns:
            str
        """
        return str(self._engine)

    @property
    def path(self) -> str:
        """
        Path to the Mackeep configuration files.

        The path to the directory where Mackeep is gonna create and store his
        directory.

        Returns:
            str
        """
        return str(self._path)

    @property
    def directory(self) -> str:
        """
        The name of the Mackeep directory, named Mackeep by default.

        Returns:
            str
        """
        return str(self._directory)

    @property
    def fullpath(self) -> str:
        """
        Full path to the Mackeep configuration files.

        The full path to the directory when Mackeep is storing the configuration
        files.

        Returns:
            str
        """
        return os.path.join(self.path, self.directory) if self.path else ""

    @property
    def apps_to_ignore(self) -> set[str]:
        """
        Get the list of applications ignored in the config file.

        Returns:
            set. Set of application names to ignore, lowercase
        """
        return set(self._apps_to_ignore)

    @property
    def apps_to_sync(self) -> set[str]:
        """
        Get the list of applications allowed in the config file.

        Returns:
            set. Set of application names to allow, lowercase
        """
        return set(self._apps_to_sync)

    @property
    def config_path(self) -> str:
        """
        The path of the config file that is used.

        Returns:
            str
        """
        return str(self._config_path)

    @property
    def global_exclude(self) -> list[str]:
        """
        Get the global exclusion patterns, applied to every application.

        The patterns are relative to the home directory.

        Returns:
            list of str
        """
        return list(self._global_exclude)

    @property
    def global_xdg_exclude(self) -> list[str]:
        """
        Get the global XDG exclusion patterns, applied to every application.

        The patterns are relative to the XDG config home.

        Returns:
            list of str
        """
        return list(self._global_xdg_exclude)

    @property
    def errors(self) -> list[str]:
        """
        Get the problems of the config file.

        The broken rules are skipped, they do not stop Mackeep from working.

        Returns:
            list of str
        """
        return list(self._errors)

    def _setup_parser(
        self,
        filename: str | None = None,
    ) -> configparser.ConfigParser:
        """
        Configure the ConfigParser instance the way we want it.

        Args:
            filename (str) or None

        Returns:
            ConfigParser
        """
        assert isinstance(filename, str) or filename is None

        # Keep track of the config file that is used
        self._config_path: str = self._best_config_path(filename)
        if (
            not self.read_only
            and not filename
            and not Path(self._config_path).is_file()
        ):
            # The config file is created when it does not exist
            self._create_config_file()

        file: IniFile = read_ini(
            self._config_path,
            allow_no_value=True,
            inline_comment_prefixes=(";", "#"),
            keep_case=False,
        )

        if self.read_only and not file.read:
            file.parser.add_section("storage")
            file.parser.set("storage", "engine", ENGINE_UNCONFIGURED)
        if not self.read_only:
            (Path.home() / CUSTOM_APPS_DIR).mkdir(mode=0o700, exist_ok=True)
        return file.parser

    def _create_config_file(self) -> None:
        """Create the config file with the default content."""
        try:
            Path(self._config_path).write_text(
                "# The configuration of Mackeep.\n"
                f"# See {DOCUMENTATION_URL} for the options.\n"
                "\n"
                "[storage]\n"
                f"engine = {ENGINE_UNCONFIGURED}\n"
                f"directory = {MACKEEP_BACKUP_PATH}\n",
                encoding="utf-8",
            )
        except OSError as e:
            error(f"Unable to create the config file {self._config_path}: {e}")

    def _setup_exclusion_parser(self) -> configparser.ConfigParser:
        """
        Configure a ConfigParser instance to read the exclusion rules.

        The exclusion patterns are case sensitive, so the case of the
        patterns must be preserved.

        Returns:
            ConfigParser
        """
        file: IniFile = read_ini(
            self._config_path,
            allow_no_value=True,
            inline_comment_prefixes=(";", "#"),
            keep_case=True,
        )
        # The problems of the file are reported once, the file is read by
        # both parsers.
        self._add_problems(file.problems)

        return file.parser

    def _best_config_path(self, filename: str | None = None) -> str:
        """
        If no filename is provided, we try to find one in according to the following
        order, note that we will always check the original default of `~/.mackeep.cfg`
        first before checking the other options:

        - ~/.mackeep.cfg
        - $MACKEEP_CONFIG
        - $XDG_CONFIG_HOME/mackeep/mackeep.cfg

        The first one that exists wins. If none of these files exist, we
        create ~/.mackeep.cfg. The config file of the previous version is not
        used, it can be migrated with `mackeep migrate`.

        Args:
            filename (str or None, optional): Optional override for the config
                file path. Can be absolute or relative to home directory.
                Defaults to None.

        Returns:
            str: the absolute path to the config file
        """
        assert isinstance(filename, str) or filename is None

        # If we are not overriding the config filename
        config_path: Path
        if not filename:
            default = Path.home() / MACKEEP_CONFIG_FILE
            xdg_config_home = Path(
                os.environ.get("XDG_CONFIG_HOME", "~/.config"),
            ).expanduser()
            search_paths = [
                # 1. the default config file is ~/.mackeep.cfg
                default,
                # 2. check for the MACKEEP_CONFIG envvar
                Path(os.environ.get("MACKEEP_CONFIG", "")).expanduser(),
                # 3. check for a config file in the XDG_CONFIG_HOME directory
                xdg_config_home / "mackeep" / MACKEEP_CONFIG_FILE.lstrip("."),
            ]
            config_path = next((p for p in search_paths if p.is_file()), default)
        else:
            # Support both absolute and relative paths
            config_path = Path(filename).expanduser()
            if not config_path.is_absolute():
                config_path = Path.home() / filename

            # When explicitly specified, check that the file exists
            if not config_path.is_file():
                error(
                    f"The config file '{config_path}' does not exist. Aborting.",
                )

        try:
            # Make sure the config file is in the home directory
            config_path.relative_to(Path.home())
        except ValueError:
            error(
                f"The config file '{config_path}' is not in your home "
                "directory. Aborting.",
            )

        # return the absolute path to the config file
        return str(config_path.absolute())

    def _warn_on_old_config(self) -> None:
        """Warn the user if an old config format is detected."""
        # Is an old section in the config file?
        old_sections = ["Allowed Applications", "Ignored Applications"]
        for old_section in old_sections:
            if self._parser.has_section(old_section):
                error(
                    "Old config file detected. Aborting.\n"
                    "\n"
                    "An old section (e.g. [Allowed Applications]"
                    " or [Ignored Applications] has been detected"
                    f" in your {MACKEEP_CONFIG_FILE} file.\n"
                    "I'd rather do nothing than do something you"
                    " do not want me to do.\n"
                    "\n"
                    "Please read the up to date documentation on"
                    " <https://github.com/Joynik/mackeep> and migrate"
                    " your configuration file.",
                )

    def _parse_engine(self) -> str:
        """
        Parse the storage engine in the config.

        Returns:
            str
        """
        if self._parser.has_option("storage", "engine"):
            engine = str(self._parser.get("storage", "engine"))
        else:
            engine = ENGINE_DROPBOX

        assert isinstance(engine, str)

        if engine not in [
            ENGINE_UNCONFIGURED,
            ENGINE_DROPBOX,
            ENGINE_GDRIVE,
            ENGINE_ICLOUD,
            ENGINE_FS,
        ]:
            raise ConfigError(f"Unknown storage engine: {engine}")

        return str(engine)

    def _parse_path(self) -> str:
        """
        Parse the storage path in the config.

        Returns:
            str
        """
        if self.engine == ENGINE_UNCONFIGURED:
            return ""
        if self.engine == ENGINE_DROPBOX:
            try:
                path = get_dropbox_folder_location()
            except SystemExit:
                if self._parser.has_option("storage", "engine"):
                    raise
                return ""
        elif self.engine == ENGINE_GDRIVE:
            path = get_google_drive_folder_location()
        elif self.engine == ENGINE_ICLOUD:
            path = get_icloud_folder_location()
        elif self.engine == ENGINE_FS:
            if self._parser.has_option("storage", "path"):
                cfg_path = self._parser.get("storage", "path")
                if not cfg_path:
                    return ""
                path = os.path.join(os.environ["HOME"], cfg_path)
            else:
                raise ConfigError(
                    "The required 'path' can't be found while"
                    " the 'file_system' engine is used.",
                )

        return str(path)

    def _parse_directory(self) -> str:
        """
        Parse the storage directory in the config.

        Returns:
            str
        """
        if self._parser.has_option("storage", "directory"):
            directory = self._parser.get("storage", "directory")
            # Don't allow CUSTOM_APPS_DIR or XDG custom apps dir as a storage directory
            if directory == CUSTOM_APPS_DIR:
                raise ConfigError(
                    f"{CUSTOM_APPS_DIR} cannot be used as a storage directory.",
                )
            xdg_custom_apps_dir = os.path.join(".config", CUSTOM_APPS_DIR_XDG)
            in_xdg_dir = directory in (CUSTOM_APPS_DIR_XDG, xdg_custom_apps_dir)
            if in_xdg_dir or directory.endswith("/" + xdg_custom_apps_dir):
                raise ConfigError(
                    f"{CUSTOM_APPS_DIR_XDG} cannot be used as a storage directory.",
                )
        else:
            directory = MACKEEP_BACKUP_PATH

        return str(directory)

    def _parse_apps_to_ignore(self) -> set[str]:
        """
        Parse the applications to ignore in the config.

        Returns:
            set
        """
        # We ignore nothing by default
        apps_to_ignore = set()

        # Is the "[applications_to_ignore]" in the cfg file?
        section_title = "applications_to_ignore"
        if self._parser.has_section(section_title):
            apps_to_ignore = set(self._parser.options(section_title))

        return apps_to_ignore

    def _parse_apps_to_sync(self) -> set[str]:
        """
        Parse the applications to backup in the config.

        Returns:
            set
        """
        # We allow nothing by default
        apps_to_sync = set()

        # Is the "[applications_to_sync]" section in the cfg file?
        section_title = "applications_to_sync"
        if self._parser.has_section(section_title):
            apps_to_sync = set(self._parser.options(section_title))

        return apps_to_sync

    @property
    def apps_to_sync_is_explicit(self) -> bool:
        """
        Whether the config file holds the list of the applications to backup.

        When the list is there, only the applications of it are backed up,
        even when it is empty. When it is not there, every application of
        the database is backed up.

        Returns:
            bool
        """
        return self._parser.has_section("applications_to_sync")

    def _parse_exclusions(self, section_title: str) -> list[str]:
        """
        Parse a global exclusion section in the config.

        The patterns are listed one per line, like the other sections of the
        config file. A pattern may also be given as a value, e.g.
        ``*.log = some log files``.

        The patterns that are not valid are skipped, they do not stop Mackeep
        from working, and they are reported.

        Args:
            section_title (str): The name of the section to read.

        Returns:
            list of str
        """
        patterns: list[str] = []
        if not self._exclusion_parser.has_section(section_title):
            return patterns

        for option in self._exclusion_parser.options(section_title):
            value: str | None = self._exclusion_parser.get(
                section_title, option, raw=True,
            )
            # A pattern listed without a value is the option itself.
            pattern: str = option if value is None else value
            pattern = pattern.strip()
            if not pattern:
                continue
            if pattern.startswith("/"):
                self._add_problems(
                    [
                        f"Invalid exclusion pattern in {self._config_path}: "
                        f"unsupported absolute path: {pattern}",
                    ],
                )
                continue
            patterns.append(pattern)

        return patterns

    def _add_problems(self, problems: list[str]) -> None:
        """
        Report the problems of the config file.

        The same problem is only reported once, the file is read twice.

        Args:
            problems (list of str): The problems of the file.
        """
        for problem in problems:
            if problem not in self._errors:
                self._errors.append(problem)


class ConfigError(Exception):
    """Exception used for handle errors in the configuration."""
