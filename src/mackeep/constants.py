"""Constants used in Mackeep."""

from importlib.metadata import PackageNotFoundError, version

# Support platforms
PLATFORM_DARWIN: str = "Darwin"
PLATFORM_LINUX: str = "Linux"

# Directory containing the application configs
APPS_DIR: str = "applications"

# Mackeep application name
MACKEEP_APP_NAME: str = "mackeep"

# The name of the distribution of the terminal version
DISTRIBUTION_NAME: str = "mackeep-cli"

# Default Mackeep backup path where it stores its files in Dropbox
MACKEEP_BACKUP_PATH: str = "Mackeep"

# Mackeep config file
MACKEEP_CONFIG_FILE: str = ".mackeep.cfg"

# The legacy Mackup names, read for backward compatibility
LEGACY_BACKUP_PATH: str = "Mackup"
LEGACY_CONFIG_FILE: str = ".mackup.cfg"
LEGACY_CUSTOM_APPS_DIR: str = ".mackup"
LEGACY_CUSTOM_APPS_DIR_XDG: str = "mackup/applications"


def get_version() -> str:
    """Return package version, or a safe fallback when metadata is unavailable."""
    try:
        return version(DISTRIBUTION_NAME)
    except PackageNotFoundError:
        return "unknown"


# Current version
VERSION: str = get_version()

# Directory that can contains user defined app configs
CUSTOM_APPS_DIR: str = ".mackeep"

# XDG-compliant directory for user defined app configs (relative to XDG_CONFIG_HOME)
CUSTOM_APPS_DIR_XDG: str = "mackeep/applications"

# Supported engines
ENGINE_DROPBOX: str = "dropbox"
ENGINE_FS: str = "file_system"
ENGINE_GDRIVE: str = "google_drive"
ENGINE_ICLOUD: str = "icloud"

DOCUMENTATION_URL: str = "https://github.com/Joynik/mackeep/blob/master/doc/README.md"

# Error message displayed when mackeep can't find the storage specified
# in the config (or the default one).
ERROR_UNABLE_TO_FIND_STORAGE: str = (
    "Unable to find your {provider} =(\n"
    f"If this is the first time you use {MACKEEP_APP_NAME}, you may want "
    "to use another provider.\n"
    "Take a look at the documentation [1] to know more about "
    "how to configure mackeep.\n\n"
    f"[1]: {DOCUMENTATION_URL}"
)
