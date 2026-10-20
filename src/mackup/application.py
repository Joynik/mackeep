"""
Application Profile.

An Application Profile contains all the information about an application in
Mackup. Name, files, ...
"""

import os
from collections.abc import Callable, Iterator
from typing import Any

from . import utils
from .excludes import Matcher
from .mackup import Mackup

# The type of the callback used to report the operations of an application.
Reporter = Callable[[str, dict[str, Any]], None]


class ApplicationProfile:
    """Instantiate this class with application specific data."""

    def __init__(
        self,
        mackup: Mackup,
        files: set[str],
        dry_run: bool,
        verbose: bool,
    ) -> None:
        """
        Create an ApplicationProfile instance.

        Args:
            mackup (Mackup)
            files (list)
            dry_run (bool)
            verbose (bool)
        """
        assert isinstance(mackup, Mackup)
        assert isinstance(files, set)

        self.mackup: Mackup = mackup
        self.files: list[str] = sorted(files)
        self.dry_run: bool = dry_run
        self.verbose: bool = verbose

        # The exclusion rules, relative to the home directory and to the
        # XDG config home
        self.exclude: Matcher = Matcher()
        self.xdg_exclude: Matcher = Matcher()

        # The reporter of the operations, if any
        self.reporter: Reporter | None = None
        self.app_name: str = ""

        # The XDG config home, relative to the home directory
        self._xdg_home: str | None = self._get_xdg_home()

    def configure(
        self,
        exclude: Matcher | None = None,
        xdg_exclude: Matcher | None = None,
        reporter: Reporter | None = None,
        app_name: str = "",
    ) -> None:
        """
        Set the exclusion rules and the reporter of this profile.

        Args:
            exclude (Matcher): The exclusion rules, relative to the home
                               directory.
            xdg_exclude (Matcher): The exclusion rules, relative to the XDG
                                   config home.
            reporter (Reporter): A callback to report the operations.
            app_name (str): The name of the application.
        """
        if exclude is not None:
            self.exclude = exclude
        if xdg_exclude is not None:
            self.xdg_exclude = xdg_exclude
        self.reporter = reporter
        self.app_name = app_name

    @staticmethod
    def _get_xdg_home() -> str | None:
        """
        Get the XDG config home, relative to the home directory.

        Returns:
            str or None: None when the XDG config home is not in the home
                         directory.
        """
        home: str = os.environ["HOME"]
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME", os.path.join(home, ".config"),
        )
        if not os.path.isabs(xdg_config_home) or not xdg_config_home.startswith(
            home,
        ):
            return None
        return os.path.relpath(xdg_config_home, home)

    def get_filepaths(self, filename: str) -> tuple[str, str]:
        """
        Get home and mackup filepaths for given file

        Args:
            filename (str)

        Returns:
            home_filepath, mackup_filepath (str, str)
        """
        return (
            os.path.join(os.environ["HOME"], filename),
            os.path.join(self.mackup.mackup_folder, filename),
        )

    def _xdg_relative(self, home_relative: str) -> str | None:
        """
        Get a path relative to the XDG config home.

        Args:
            home_relative (str): The path, relative to the home directory.

        Returns:
            str or None: None when the path is not in the XDG config home.
        """
        if self._xdg_home is None:
            return None
        if home_relative == self._xdg_home:
            return ""
        prefix: str = f"{self._xdg_home}/"
        if home_relative.startswith(prefix):
            return home_relative[len(prefix) :]
        return None

    def is_excluded(self, home_relative: str, is_dir: bool = False) -> bool:
        """
        Check if a path is excluded by the exclusion rules.

        Args:
            home_relative (str): The path, relative to the home directory.
            is_dir (bool): Whether the path is a directory.

        Returns:
            bool: True when the path is excluded.
        """
        if self.exclude.is_excluded(home_relative, is_dir):
            return True

        xdg_relative: str | None = self._xdg_relative(home_relative)
        return bool(
            xdg_relative and self.xdg_exclude.is_excluded(xdg_relative, is_dir),
        )

    def _report(self, action: str, **details: Any) -> None:
        """
        Report an operation to the reporter, if any.

        Args:
            action (str): The action, e.g. "copy" or "skip_excluded".
            details: The details of the operation.
        """
        if self.reporter is None:
            return
        payload: dict[str, Any] = {"app": self.app_name, "action": action}
        payload.update(details)
        self.reporter(action, payload)

    def _walk(
        self, src: str, relative: str, filtered: bool = True,
    ) -> Iterator[tuple[str, str, bool]]:
        """
        Walk a directory, relative to the home directory.

        Args:
            src (str): The path of the directory to walk.
            relative (str): The path of the directory, relative to the home
                            directory.
            filtered (bool): Whether the excluded paths are skipped.

        Yields:
            tuple of (str, str, bool): The path, the path relative to the home
            directory and whether the path is a directory.
        """
        try:
            names: list[str] = sorted(os.listdir(src))
        except OSError:
            return

        for name in names:
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            is_dir: bool = os.path.isdir(path)

            if filtered and self.is_excluded(relative_path, is_dir):
                # An excluded directory is not walked.
                continue

            yield path, relative_path, is_dir

            if is_dir:
                yield from self._walk(path, relative_path, filtered)

    def _copy_tree(self, src: str, dst: str, relative: str) -> int:
        """
        Copy a directory, skipping the excluded files.

        Args:
            src (str): The path of the directory to copy.
            dst (str): The path of the destination directory.
            relative (str): The path of the directory, relative to the home
                            directory.

        Returns:
            int: The number of bytes copied.
        """
        os.makedirs(dst, exist_ok=True)
        copied: int = 0

        for path, _relative_path, is_dir in self._walk(src, relative):
            destination: str = os.path.join(dst, os.path.relpath(path, src))
            if is_dir:
                os.makedirs(destination, exist_ok=True)
                continue

            utils.copy(path, destination)
            size: int = os.path.getsize(path)
            copied += size
            self._report("copy", src=path, dst=destination, size_bytes=size)

        # Set the good mode to the file or folder recursively
        utils.chmod(dst)

        return copied

    def _planned_size(self, src: str, relative: str) -> int:
        """
        Compute the size of the files that would be copied.

        Args:
            src (str): The path of the file or directory.
            relative (str): The path, relative to the home directory.

        Returns:
            int: The number of bytes.
        """
        if not os.path.isdir(src):
            return os.path.getsize(src) if os.path.isfile(src) else 0

        size: int = 0
        for path, _relative_path, is_dir in self._walk(src, relative):
            if not is_dir:
                size += os.path.getsize(path)
        return size

    def _contains_excluded(self, src: str, relative: str) -> bool:
        """
        Check if a directory contains excluded files.

        Args:
            src (str): The path of the directory.
            relative (str): The path of the directory, relative to the home
                            directory.

        Returns:
            bool: True when the directory contains an excluded path.
        """
        for _path, relative_path, is_dir in self._walk(src, relative, False):
            if self.is_excluded(relative_path, is_dir):
                return True
        return False

    def _report_stale(
        self, relative: str, home_filepath: str, mackup_filepath: str,
    ) -> None:
        """
        Report the files of the backup that are now excluded.

        Those files are not deleted, they are only reported.

        Args:
            relative (str): The path of the entry, relative to the home
                            directory.
            home_filepath (str): The path of the entry in the home folder.
            mackup_filepath (str): The path of the entry in the Mackup
                                   folder.
        """
        if not os.path.isdir(mackup_filepath):
            return

        for path, relative_path, is_dir in self._walk(
            mackup_filepath, relative, False,
        ):
            if not self.is_excluded(relative_path, is_dir):
                continue
            source: str = os.path.join(
                home_filepath, os.path.relpath(path, mackup_filepath),
            )
            print(
                f"Note: {relative_path} is excluded but still in the backup,"
                " it is not deleted.",
            )
            self._report("stale_in_backup", src=source, dst=path)

    def _link_skip_reason(
        self, relative: str, entry_filepath: str, source_filepath: str,
    ) -> str | None:
        """
        Check if an entry must be skipped in link mode.

        A symlink cannot exclude anything, so an entry that contains excluded
        files cannot be linked.

        Args:
            relative (str): The path of the entry, relative to the home
                            directory.
            entry_filepath (str): The path of the entry in the home folder.
            source_filepath (str): The path of the entry in the folder that
                                   holds the files to link.

        Returns:
            str or None: The reason to skip the entry, if any.
        """
        is_dir: bool = os.path.isdir(entry_filepath)

        if self.is_excluded(relative, is_dir):
            return "it is excluded by the exclusion rules"

        if not is_dir:
            return None

        if not os.path.isdir(source_filepath):
            return None

        if self._contains_excluded(source_filepath, relative):
            return (
                "it contains excluded files and a symlink cannot exclude them"
            )

        return None

    def copy_files_to_mackup_folder(self) -> None:
        """
        Backup the application config files to the Mackup folder.

        Algorithm:
            for config_file
                if config_file is excluded
                    skip it
                if config_file exists and is a real file/folder
                    if home/file is a symlink pointing to mackup/file
                        skip (already backed up via link install)
                    if exists mackup/file
                        are you sure?
                        if sure
                            rm mackup/file
                    cp home/file mackup/file
        """
        for filename in self.files:
            (home_filepath, mackup_filepath) = self.get_filepaths(filename)

            # If config_file exists and is a real file/folder
            if not (os.path.isfile(home_filepath) or os.path.isdir(home_filepath)):
                self._report(
                    "skip_missing", src=home_filepath, dst=mackup_filepath,
                )
                continue

            is_dir: bool = os.path.isdir(home_filepath)

            # Is the file excluded by the exclusion rules?
            if self.is_excluded(filename, is_dir):
                self._report(
                    "skip_excluded", src=home_filepath, dst=mackup_filepath,
                )
                print(f"Skipping {filename} (excluded)")
                continue

            # Check if home file is a symlink pointing to mackup file
            # (already backed up via link install)
            if (
                os.path.islink(home_filepath)
                and os.path.exists(mackup_filepath)
                and os.path.samefile(home_filepath, mackup_filepath)
            ):
                if self.verbose:
                    print(
                        f"Skipping {home_filepath}\n"
                        f"  already linked to\n  {mackup_filepath}",
                    )
                continue

            if self.verbose:
                print(
                    f"Backing up\n  {home_filepath}\n  to\n  {mackup_filepath} ...",
                )
            else:
                print(f"Backing up {filename} ...")

            if self.dry_run:
                size: int = self._planned_size(home_filepath, filename)
                self._report(
                    "copy",
                    src=home_filepath,
                    dst=mackup_filepath,
                    size_bytes=size,
                )
                if os.path.lexists(mackup_filepath):
                    self._report(
                        "conflict",
                        src=home_filepath,
                        dst=mackup_filepath,
                        size_bytes=size,
                    )
                # The files of the backup that are now excluded are not
                # deleted, they are only reported.
                self._report_stale(filename, home_filepath, mackup_filepath)
                continue

            # If exists mackup/file
            if os.path.lexists(mackup_filepath):
                # Name it right
                file_type: str
                if os.path.isfile(mackup_filepath):
                    file_type = "file"
                elif os.path.isdir(mackup_filepath):
                    file_type = "folder"
                elif os.path.islink(mackup_filepath):
                    file_type = "link"
                else:
                    raise ValueError(f"Unsupported file: {mackup_filepath}")
                # Ask the user if he really wants to replace it
                if utils.confirm(
                    f"A {file_type} named {mackup_filepath} already exists in the"
                    " Mackup folder.\nAre you sure that you want to"
                    " replace it? (use --force to skip this prompt)",
                ):
                    # If confirmed, delete the file in Mackup
                    utils.delete(mackup_filepath)
                else:
                    self._report(
                        "conflict",
                        src=home_filepath,
                        dst=mackup_filepath,
                        size_bytes=self._planned_size(home_filepath, filename),
                    )
                    continue

            # Copy the file
            try:
                if is_dir:
                    self._copy_tree(home_filepath, mackup_filepath, filename)
                else:
                    utils.copy(home_filepath, mackup_filepath)
                    self._report(
                        "copy",
                        src=home_filepath,
                        dst=mackup_filepath,
                        size_bytes=os.path.getsize(home_filepath),
                    )
            except PermissionError as e:
                print(
                    f"Error: Unable to copy file from {home_filepath} to "
                    f"{mackup_filepath} due to permission issue: {e}",
                )
                self._report(
                    "error", src=home_filepath, dst=mackup_filepath, message=str(e),
                )

    def copy_files_from_mackup_folder(self) -> None:
        """
        Recover the application config files from the Mackup folder.

        Algorithm:
            for config_file
                if config_file is excluded
                    skip it
                if config_file exists in mackup and is a real file/folder
                    if exists home/file
                        are you sure?
                        if sure
                            rm home/file
                    cp mackup/file home/file
        """
        for filename in self.files:
            (home_filepath, mackup_filepath) = self.get_filepaths(filename)

            # If config_file exists in mackup and is a real file/folder
            if not (os.path.isfile(mackup_filepath) or os.path.isdir(mackup_filepath)):
                self._report(
                    "skip_missing", src=mackup_filepath, dst=home_filepath,
                )
                continue

            is_dir: bool = os.path.isdir(mackup_filepath)

            # Is the file excluded by the exclusion rules?
            if self.is_excluded(filename, is_dir):
                self._report(
                    "skip_excluded", src=mackup_filepath, dst=home_filepath,
                )
                print(f"Skipping {filename} (excluded)")
                continue

            if self.verbose:
                print(
                    f"Recovering\n  {mackup_filepath}\n  to\n  {home_filepath} ...",
                )
            else:
                print(f"Recovering {filename} ...")

            if self.dry_run:
                size: int = self._planned_size(mackup_filepath, filename)
                self._report(
                    "copy",
                    src=mackup_filepath,
                    dst=home_filepath,
                    size_bytes=size,
                )
                if os.path.lexists(home_filepath):
                    self._report(
                        "conflict",
                        src=mackup_filepath,
                        dst=home_filepath,
                        size_bytes=size,
                    )
                continue

            # If exists home/file
            if os.path.lexists(home_filepath):
                # Name it right
                if os.path.isfile(home_filepath):
                    file_type = "file"
                elif os.path.isdir(home_filepath):
                    file_type = "folder"
                elif os.path.islink(home_filepath):
                    file_type = "link"
                else:
                    raise ValueError(f"Unsupported file: {home_filepath}")
                # Ask the user if he really wants to replace it
                if utils.confirm(
                    f"A {file_type} named {home_filepath} already exists in your"
                    " home folder.\nAre you sure that you want to"
                    " replace it?",
                ):
                    # If confirmed, delete the existing home file
                    utils.delete(home_filepath)
                else:
                    self._report(
                        "conflict",
                        src=mackup_filepath,
                        dst=home_filepath,
                        size_bytes=self._planned_size(mackup_filepath, filename),
                    )
                    continue

            # Copy the file
            try:
                if is_dir:
                    self._copy_tree(mackup_filepath, home_filepath, filename)
                else:
                    utils.copy(mackup_filepath, home_filepath)
                    self._report(
                        "copy",
                        src=mackup_filepath,
                        dst=home_filepath,
                        size_bytes=os.path.getsize(mackup_filepath),
                    )
            except PermissionError as e:
                print(
                    f"Error: Unable to copy file from {mackup_filepath} to "
                    f"{home_filepath} due to permission issue: {e}",
                )
                self._report(
                    "error", src=mackup_filepath, dst=home_filepath, message=str(e),
                )

    def link_install(self) -> None:
        """
        Create the application config file links.

        Algorithm:
            if exists home/file
              if home/file is a real file
                if exists mackup/file
                  are you sure?
                  if sure
                    rm mackup/file
                    mv home/file mackup/file
                    link mackup/file home/file
                else
                  mv home/file mackup/file
                  link mackup/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackup_filepath) = self.get_filepaths(filename)

            # A symlink cannot exclude anything, so the entries that are
            # impacted by the exclusion rules are skipped.
            reason: str | None = self._link_skip_reason(
                filename, home_filepath, home_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded", src=home_filepath, dst=mackup_filepath,
                )
                continue

            # If the file exists and is not already a link pointing to Mackup
            if (os.path.isfile(home_filepath) or os.path.isdir(home_filepath)) and not (
                os.path.islink(home_filepath)
                and (os.path.isfile(mackup_filepath) or os.path.isdir(mackup_filepath))
                and os.path.samefile(home_filepath, mackup_filepath)
            ):
                if self.verbose:
                    print(
                        f"Backing up\n  {home_filepath}\n  to\n  {mackup_filepath} ...",
                    )
                else:
                    print(f"Linking {filename} ...")

                if self.dry_run:
                    continue

                # Check if we already have a backup
                if os.path.exists(mackup_filepath):
                    # Name it right
                    if os.path.isfile(mackup_filepath):
                        file_type = "file"
                    elif os.path.isdir(mackup_filepath):
                        file_type = "folder"
                    elif os.path.islink(mackup_filepath):
                        file_type = "link"
                    else:
                        raise ValueError(f"Unsupported file: {mackup_filepath}")

                    # Ask the user if he really wants to replace it
                    if utils.confirm(
                        f"A {file_type} named {mackup_filepath} already exists in the"
                        " backup.\nAre you sure that you want to"
                        " replace it?",
                    ):
                        # Delete the file in Mackup
                        utils.delete(mackup_filepath)
                        # Copy the file
                        utils.copy(home_filepath, mackup_filepath)
                        # Delete the file in the home
                        utils.delete(home_filepath)
                        # Link the backuped file to its original place
                        utils.link(mackup_filepath, home_filepath)
                else:
                    # Copy the file
                    utils.copy(home_filepath, mackup_filepath)
                    # Delete the file in the home
                    utils.delete(home_filepath)
                    # Link the backuped file to its original place
                    utils.link(mackup_filepath, home_filepath)
            elif self.verbose:
                if os.path.exists(home_filepath):
                    print(
                        f"Doing nothing\n  {home_filepath}\n  "
                        f"is already backed up to\n  {mackup_filepath}",
                    )
                elif os.path.islink(home_filepath):
                    print(
                        f"Doing nothing\n  {home_filepath}\n  "
                        "is a broken link, you might want to fix it.",
                    )
                else:
                    print(f"Doing nothing\n  {home_filepath}\n  does not exist")

    def link(self) -> None:
        """
        Link the application config files.

        Algorithm:
            if exists mackup/file
              if exists home/file
                are you sure?
                if sure
                  rm home/file
                  link mackup/file home/file
              else
                link mackup/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackup_filepath) = self.get_filepaths(filename)

            # A symlink cannot exclude anything, so the entries that are
            # impacted by the exclusion rules are skipped.
            reason: str | None = self._link_skip_reason(
                filename, mackup_filepath, mackup_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded", src=mackup_filepath, dst=home_filepath,
                )
                continue

            # If the file exists and is not already pointing to the mackup file
            # and the folder makes sense on the current platform (Don't sync
            # any subfolder of ~/Library on GNU/Linux)
            file_or_dir_exists: bool = os.path.isfile(mackup_filepath) or os.path.isdir(
                mackup_filepath,
            )
            pointing_to_mackup: bool = (
                os.path.islink(home_filepath)
                and os.path.exists(mackup_filepath)
                and os.path.samefile(mackup_filepath, home_filepath)
            )
            supported: bool = utils.can_file_be_synced_on_current_platform(filename)

            if file_or_dir_exists and not pointing_to_mackup and supported:
                if self.verbose:
                    print(
                        f"Restoring\n  linking {home_filepath}\n"
                        f"  to      {mackup_filepath} ...",
                    )
                else:
                    print(f"Restoring {filename} ...")

                if self.dry_run:
                    continue

                # Check if there is already a file in the home folder
                if os.path.exists(home_filepath):
                    # Name it right
                    if os.path.isfile(home_filepath):
                        file_type = "file"
                    elif os.path.isdir(home_filepath):
                        file_type = "folder"
                    elif os.path.islink(home_filepath):
                        file_type = "link"
                    else:
                        raise ValueError(f"Unsupported file: {home_filepath}")

                    if utils.confirm(
                        f"You already have a {file_type} at {home_filepath}.\n"
                        "Do you want to replace it with your backup?",
                    ):
                        utils.delete(home_filepath)
                        utils.link(mackup_filepath, home_filepath)
                else:
                    utils.link(mackup_filepath, home_filepath)
            elif self.verbose:
                if os.path.exists(home_filepath):
                    print(
                        f"Doing nothing\n  {mackup_filepath}\n  "
                        f"  already linked by\n  {home_filepath}",
                    )
                elif os.path.islink(home_filepath):
                    print(
                        f"Doing nothing\n  {home_filepath}\n  "
                        "is a broken link, you might want to fix it.",
                    )
                else:
                    print(
                        f"Doing nothing\n  {mackup_filepath}\n  does not exist",
                    )

    def link_uninstall(self) -> None:
        """
        Removes links and copy config files from the remote folder locally.

        Algorithm:
            for each file in config
                if mackup/file exists
                    if home/file exists
                        delete home/file
                    copy mackup/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackup_filepath) = self.get_filepaths(filename)

            # If the mackup file exists
            if os.path.isfile(mackup_filepath) or os.path.isdir(mackup_filepath):
                # Check if there is a corresponding file in the home folder
                if os.path.exists(home_filepath):
                    # If the home file is not a link or does not point to the
                    # mackup file, display a warning and skip it.
                    if not os.path.islink(home_filepath) or not os.path.samefile(
                        home_filepath, mackup_filepath,
                    ):
                        print(
                            f'Warning: the file in your home "{home_filepath}" '
                            f"does not point to the original file in Mackup "
                            f"{mackup_filepath}, skipping...",
                        )
                        continue
                    if self.verbose:
                        print(
                            f"Reverting {mackup_filepath}\n at {home_filepath} ...",
                        )
                    else:
                        print(f"Reverting {filename} ...")

                    if self.dry_run:
                        continue

                    # If there is, delete it as we are gonna copy the Dropbox
                    # one there
                    utils.delete(home_filepath)

                    # Copy the Dropbox file to the home folder
                    utils.copy(mackup_filepath, home_filepath)
            elif self.verbose:
                print(f"Doing nothing, {mackup_filepath} does not exist")
