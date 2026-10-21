"""
The Mackeep Class.

The Mackeep class is keeping all the state that Mackeep needs to keep during its
runtime. It also provides easy to use interface that is used by the Mackeep UI.
The only UI for now is the command line.
"""

import os
import os.path

from . import appsdb, utils
from .config import Config


class Mackeep:
    """Main Mackeep class."""

    def __init__(self, config_file: str | None = None) -> None:
        """Mackeep Constructor."""
        self._config: Config = Config(config_file)

        self.mackeep_folder: str = self._config.fullpath

    @property
    def config(self) -> Config:
        """
        The configuration of Mackeep.

        Returns:
            config.Config
        """
        return self._config

    def check_for_usable_environment(self) -> None:
        """Check if the current env is usable and has everything's required."""

        # Allow only explicit superuser usage
        if os.geteuid() == 0 and not utils.CAN_RUN_AS_ROOT:
            utils.error(
                "Running Mackeep as superuser can be dangerous."
                " Don't do it unless you know what you're doing!"
                " Run mackeep --help for guidance.",
            )

        # Do we have a folder set to save Mackeep content into?
        if not os.path.isdir(self._config.path):
            utils.error(
                f"Unable to find the storage folder: {self._config.path}",
            )

        # Is Sublime Text running?
        # if is_process_running('Sublime Text'):
        #    error("Sublime Text is running. It is known to cause problems"
        #          " when Sublime Text is running while I backup or restore"
        #          " its configuration files. Please close Sublime Text and"
        #          " run me again.")

    def check_for_usable_backup_env(self) -> None:
        """Check if the current env can be used to back up files."""
        self.check_for_usable_environment()
        self.create_mackeep_home()

    def check_for_usable_restore_env(self) -> None:
        """Check if the current env can be used to restore files."""
        self.check_for_usable_environment()

        if not os.path.isdir(self.mackeep_folder):
            utils.error(
                f"Unable to find the Mackeep folder: {self.mackeep_folder}\n"
                "You might want to back up some files or get your"
                " storage directory synced first.",
            )

    def create_mackeep_home(self) -> None:
        """If the Mackeep home folder does not exist, create it."""
        if not os.path.isdir(self.mackeep_folder):
            if utils.confirm(
                "Mackeep needs a directory to store your"
                " configuration files\n"
                f"Do you want to create it now? <{self.mackeep_folder}>",
            ):
                os.makedirs(self.mackeep_folder)
            else:
                utils.error("Mackeep can't do anything without a home =(")

    def get_apps_to_backup(self) -> set[str]:
        """
        Get the list of applications that should be backed up by Mackeep.

        It's the list of allowed apps minus the list of ignored apps.

        When the config file holds the list of the applications to sync, only
        the applications of it are backed up, even when the list is empty.
        Otherwise every application of the database is backed up.

        Returns:
            (set) List of application names to back up
        """
        # Instantiate the app db
        app_db: appsdb.ApplicationsDatabase = appsdb.ApplicationsDatabase()

        # If a list of apps to sync is specify, we only allow those
        # Or we allow every supported app by default
        if self._config.apps_to_sync_is_explicit:
            apps_to_backup: set[str] = set(self._config.apps_to_sync)
        else:
            apps_to_backup = app_db.get_app_names()

        # Remove the specified apps to ignore
        for app_name in self._config.apps_to_ignore:
            apps_to_backup.discard(app_name)

        return apps_to_backup
