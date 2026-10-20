"""Package used to manage the .mackeep.cfg config file."""

import configparser
import os
import os.path
from pathlib import Path

from .constants import (
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    ENGINE_DROPBOX,
    ENGINE_FS,
    ENGINE_GDRIVE,
    ENGINE_ICLOUD,
    LEGACY_BACKUP_PATH,
    LEGACY_CONFIG_FILE,
    MACKEEP_BACKUP_PATH,
    MACKEEP_CONFIG_FILE,
)
from .utils import (
    error,
    get_dropbox_folder_location,
    get_google_drive_folder_location,
    get_icloud_folder_location,
    legacy_warning,
)


class Config:
    """The Mackeep Config class."""

    def __init__(self, filename: str | None = None) -> None:
        """
        Create a Config instance.

        Args:
            filename (str): Optional filename of the config file. If empty,
                            defaults to MACKEEP_CONFIG_FILE
        """
        assert isinstance(filename, str) or filename is None

        # Is the config file a legacy Mackup one?
        self._is_legacy: bool = False

        # Is the storage folder a legacy Mackup one?
        self._using_legacy_directory: bool = False

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
        return str(os.path.join(self.path, self.directory))

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
    def is_legacy(self) -> bool:
        """
        Whether the config file is a legacy Mackup one.

        Returns:
            bool
        """
        return self._is_legacy

    @property
    def using_legacy_directory(self) -> bool:
        """
        Whether the storage folder is the legacy Mackup one.

        Returns:
            bool
        """
        return self._using_legacy_directory

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

    def _setup_parser(
        self, filename: str | None = None,
    ) -> configparser.ConfigParser:
        """
        Configure the ConfigParser instance the way we want it.

        Args:
            filename (str) or None

        Returns:
            ConfigParser
        """
        assert isinstance(filename, str) or filename is None

        parser = configparser.ConfigParser(
            allow_no_value=True, inline_comment_prefixes=(";", "#"),
        )
        # Keep track of the config file that is used
        self._config_path: str = self._best_config_path(filename)
        parser.read(self._config_path)

        return parser

    def _setup_exclusion_parser(self) -> configparser.ConfigParser:
        """
        Configure a ConfigParser instance to read the exclusion rules.

        The exclusion patterns are case sensitive, so the case of the
        patterns must be preserved.

        Returns:
            ConfigParser
        """
        parser = configparser.ConfigParser(
            allow_no_value=True, inline_comment_prefixes=(";", "#"),
        )
        parser.optionxform = str  # type: ignore
        try:
            parser.read(self._config_path)
        except configparser.Error as e:
            raise ConfigError(
                f"Invalid config file {self._config_path}: {e}",
            ) from e

        return parser

    def _best_config_path(self, filename: str | None = None) -> str:
        """
        If no filename is provided, we try to find one in according to the following
        order, note that we will always check the original default of `~/.mackeep.cfg`
        first before checking the other options:

        - ~/.mackeep.cfg
        - $MACKEEP_CONFIG
        - $XDG_CONFIG_HOME/mackeep/mackeep.cfg
        - ~/.mackup.cfg (legacy)
        - $XDG_CONFIG_HOME/mackup/mackup.cfg (legacy)

        The first one that exists wins. If none of these files exist, we
        create ~/.mackeep.cfg.

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
            legacy_paths = [
                # 4. the legacy config file of Mackup
                Path.home() / LEGACY_CONFIG_FILE,
                # 5. the legacy config file in the XDG_CONFIG_HOME directory
                xdg_config_home / "mackup" / LEGACY_CONFIG_FILE.lstrip("."),
            ]
            search_paths = [
                # 1. the default config file is ~/.mackeep.cfg
                default,
                # 2. check for the MACKEEP_CONFIG envvar
                Path(os.environ.get("MACKEEP_CONFIG", "")).expanduser(),
                # 3. check for a config file in the XDG_CONFIG_HOME directory
                xdg_config_home / "mackeep" / MACKEEP_CONFIG_FILE.lstrip("."),
                *legacy_paths,
            ]
            config_path = next((p for p in search_paths if p.is_file()), default)
            self._is_legacy = config_path in legacy_paths
            if self._is_legacy:
                legacy_warning(
                    f"the config file {config_path} is used, copy it to "
                    f"{default} to use the new name",
                )
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
        if self.engine == ENGINE_DROPBOX:
            path = get_dropbox_folder_location()
        elif self.engine == ENGINE_GDRIVE:
            path = get_google_drive_folder_location()
        elif self.engine == ENGINE_ICLOUD:
            path = get_icloud_folder_location()
        elif self.engine == ENGINE_FS:
            if self._parser.has_option("storage", "path"):
                cfg_path = self._parser.get("storage", "path")
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

            # The legacy folder of Mackup is used when it exists and the
            # new one does not. An explicit directory is never replaced.
            legacy_directory: str = os.path.join(self.path, LEGACY_BACKUP_PATH)
            if not os.path.isdir(os.path.join(self.path, directory)) and os.path.isdir(
                legacy_directory,
            ):
                directory = LEGACY_BACKUP_PATH
                self._using_legacy_directory = True
                legacy_warning(
                    f"the storage folder {legacy_directory} is used, set the"
                    " 'directory' option in the config file to use another one",
                )

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

    def _parse_exclusions(self, section_title: str) -> list[str]:
        """
        Parse a global exclusion section in the config.

        The patterns are listed one per line, like the other sections of the
        config file. A pattern may also be given as a value, e.g.
        ``*.log = some log files``.

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
                raise ConfigError(
                    f"Invalid exclusion pattern in {self._config_path}: "
                    f"unsupported absolute path: {pattern}",
                )
            patterns.append(pattern)

        return patterns


class ConfigError(Exception):
    """Exception used for handle errors in the configuration."""
