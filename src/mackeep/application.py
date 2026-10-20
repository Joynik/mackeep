"""
Application Profile.

An Application Profile contains all the information about an application in
Mackeep. Name, files, ...
"""

import os
from collections.abc import Callable, Iterator
from typing import Any

from . import utils
from .excludes import Matcher
from .mackeep import Mackeep

# The type of the callback used to report the operations of an application.
Reporter = Callable[[str, dict[str, Any]], None]


class ApplicationProfile:
    """Instantiate this class with application specific data."""

    def __init__(
        self,
        mackeep: Mackeep,
        files: set[str],
        dry_run: bool,
        verbose: bool,
    ) -> None:
        """
        Create an ApplicationProfile instance.

        Args:
            mackeep (Mackeep)
            files (list)
            dry_run (bool)
            verbose (bool)
        """
        assert isinstance(mackeep, Mackeep)
        assert isinstance(files, set)

        self.mackeep: Mackeep = mackeep
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
        Get home and mackeep filepaths for given file

        Args:
            filename (str)

        Returns:
            home_filepath, mackeep_filepath (str, str)
        """
        return (
            os.path.join(os.environ["HOME"], filename),
            os.path.join(self.mackeep.mackeep_folder, filename),
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

    def _walk(self, src: str, relative: str) -> Iterator[tuple[str, str, bool]]:
        """
        Walk a directory, relative to the home directory.

        The excluded paths are not filtered out, the caller decides what to
        do with them.

        Args:
            src (str): The path of the directory to walk.
            relative (str): The path of the directory, relative to the home
                            directory.

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

            yield path, relative_path, is_dir

            if is_dir:
                yield from self._walk(path, relative_path)

    def _report_excluded(self, path: str, relative_path: str, dst: str) -> None:
        """
        Report an excluded path.

        Args:
            path (str): The path of the excluded file or folder.
            relative_path (str): The path, relative to the home directory.
            dst (str): The path the file would have been copied to.
        """
        self._report("skip_excluded", src=path, dst=dst)
        if self.verbose or self.dry_run:
            print(f"Skipping {relative_path} (excluded)")

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

        for name in sorted(os.listdir(src)):
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            is_dir: bool = os.path.isdir(path)
            destination: str = os.path.join(dst, name)

            if self.is_excluded(relative_path, is_dir):
                # An excluded directory is not walked.
                self._report_excluded(path, relative_path, destination)
                continue

            if is_dir:
                copied += self._copy_tree(path, destination, relative_path)
                continue

            utils.copy(path, destination)
            size: int = os.path.getsize(path)
            copied += size
            self._report("copy", src=path, dst=destination, size_bytes=size)

        # Set the good mode to the file or folder recursively
        utils.chmod(dst)

        return copied

    def _plan_tree(
        self, src: str, relative: str,
    ) -> tuple[int, list[tuple[str, str]]]:
        """
        Compute what would be copied, without copying anything.

        Args:
            src (str): The path of the file or directory.
            relative (str): The path, relative to the home directory.

        Returns:
            tuple: The number of bytes that would be copied and the list of
            the excluded paths, as (path, relative path) tuples.
        """
        if not os.path.isdir(src):
            return (os.path.getsize(src) if os.path.isfile(src) else 0), []

        size: int = 0
        excluded: list[tuple[str, str]] = []

        for name in sorted(os.listdir(src)):
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            is_dir: bool = os.path.isdir(path)

            if self.is_excluded(relative_path, is_dir):
                excluded.append((path, relative_path))
                continue

            if is_dir:
                sub_size, sub_excluded = self._plan_tree(path, relative_path)
                size += sub_size
                excluded.extend(sub_excluded)
            else:
                size += os.path.getsize(path)

        return size, excluded

    def _plan(self, src: str, dst: str, relative: str) -> int:
        """
        Report what would be copied, without copying anything.

        Args:
            src (str): The path of the file or directory.
            dst (str): The path of the destination.
            relative (str): The path, relative to the home directory.

        Returns:
            int: The number of bytes that would be copied.
        """
        size, excluded = self._plan_tree(src, relative)
        for path, relative_path in excluded:
            destination: str = os.path.join(dst, os.path.relpath(path, src))
            self._report_excluded(path, relative_path, destination)
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
        for _path, relative_path, is_dir in self._walk(src, relative):
            if self.is_excluded(relative_path, is_dir):
                return True
        return False

    def _report_stale(
        self, relative: str, home_filepath: str, mackeep_filepath: str,
    ) -> None:
        """
        Report the files of the backup that are now excluded.

        Those files are not deleted, they are only reported.

        Args:
            relative (str): The path of the entry, relative to the home
                            directory.
            home_filepath (str): The path of the entry in the home folder.
            mackeep_filepath (str): The path of the entry in the Mackeep
                                   folder.
        """
        if not os.path.isdir(mackeep_filepath):
            return

        for path, relative_path, is_dir in self._walk(mackeep_filepath, relative):
            if not self.is_excluded(relative_path, is_dir):
                continue
            source: str = os.path.join(
                home_filepath, os.path.relpath(path, mackeep_filepath),
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

    def copy_files_to_mackeep_folder(self) -> None:
        """
        Backup the application config files to the Mackeep folder.

        Algorithm:
            for config_file
                if config_file is excluded
                    skip it
                if config_file exists and is a real file/folder
                    if home/file is a symlink pointing to mackeep/file
                        skip (already backed up via link install)
                    if exists mackeep/file
                        are you sure?
                        if sure
                            rm mackeep/file
                    cp home/file mackeep/file
        """
        for filename in self.files:
            (home_filepath, mackeep_filepath) = self.get_filepaths(filename)

            # If config_file exists and is a real file/folder
            if not (os.path.isfile(home_filepath) or os.path.isdir(home_filepath)):
                self._report(
                    "skip_missing", src=home_filepath, dst=mackeep_filepath,
                )
                continue

            is_dir: bool = os.path.isdir(home_filepath)

            # Is the file excluded by the exclusion rules?
            if self.is_excluded(filename, is_dir):
                self._report(
                    "skip_excluded", src=home_filepath, dst=mackeep_filepath,
                )
                print(f"Skipping {filename} (excluded)")
                continue

            # Check if home file is a symlink pointing to mackeep file
            # (already backed up via link install)
            if (
                os.path.islink(home_filepath)
                and os.path.exists(mackeep_filepath)
                and os.path.samefile(home_filepath, mackeep_filepath)
            ):
                if self.verbose:
                    print(
                        f"Skipping {home_filepath}\n"
                        f"  already linked to\n  {mackeep_filepath}",
                    )
                continue

            if self.verbose:
                print(
                    f"Backing up\n  {home_filepath}\n  to\n  {mackeep_filepath} ...",
                )
            else:
                print(f"Backing up {filename} ...")

            if self.dry_run:
                size: int = self._plan(home_filepath, mackeep_filepath, filename)
                self._report(
                    "copy",
                    src=home_filepath,
                    dst=mackeep_filepath,
                    size_bytes=size,
                )
                if os.path.lexists(mackeep_filepath):
                    self._report(
                        "conflict",
                        src=home_filepath,
                        dst=mackeep_filepath,
                        size_bytes=size,
                    )
                # The files of the backup that are now excluded are not
                # deleted, they are only reported.
                self._report_stale(filename, home_filepath, mackeep_filepath)
                continue

            # If exists mackeep/file
            if os.path.lexists(mackeep_filepath):
                # Name it right
                file_type: str
                if os.path.isfile(mackeep_filepath):
                    file_type = "file"
                elif os.path.isdir(mackeep_filepath):
                    file_type = "folder"
                elif os.path.islink(mackeep_filepath):
                    file_type = "link"
                else:
                    raise ValueError(f"Unsupported file: {mackeep_filepath}")
                # Ask the user if he really wants to replace it
                if utils.confirm(
                    f"A {file_type} named {mackeep_filepath} already exists in the"
                    " Mackeep folder.\nAre you sure that you want to"
                    " replace it? (use --force to skip this prompt)",
                ):
                    # If confirmed, delete the file in Mackeep
                    utils.delete(mackeep_filepath)
                else:
                    self._report(
                        "conflict",
                        src=home_filepath,
                        dst=mackeep_filepath,
                        size_bytes=self._plan_tree(home_filepath, filename)[0],
                    )
                    continue

            # Copy the file
            try:
                if is_dir:
                    self._copy_tree(home_filepath, mackeep_filepath, filename)
                else:
                    utils.copy(home_filepath, mackeep_filepath)
                    self._report(
                        "copy",
                        src=home_filepath,
                        dst=mackeep_filepath,
                        size_bytes=os.path.getsize(home_filepath),
                    )
            except PermissionError as e:
                print(
                    f"Error: Unable to copy file from {home_filepath} to "
                    f"{mackeep_filepath} due to permission issue: {e}",
                )
                self._report(
                    "error", src=home_filepath, dst=mackeep_filepath, message=str(e),
                )

    def copy_files_from_mackeep_folder(self) -> None:
        """
        Recover the application config files from the Mackeep folder.

        Algorithm:
            for config_file
                if config_file is excluded
                    skip it
                if config_file exists in mackeep and is a real file/folder
                    if exists home/file
                        are you sure?
                        if sure
                            rm home/file
                    cp mackeep/file home/file
        """
        for filename in self.files:
            (home_filepath, mackeep_filepath) = self.get_filepaths(filename)

            # If config_file exists in mackeep and is a real file/folder
            if not (
                os.path.isfile(mackeep_filepath)
                or os.path.isdir(mackeep_filepath)
            ):
                self._report(
                    "skip_missing", src=mackeep_filepath, dst=home_filepath,
                )
                continue

            is_dir: bool = os.path.isdir(mackeep_filepath)

            # Is the file excluded by the exclusion rules?
            if self.is_excluded(filename, is_dir):
                self._report(
                    "skip_excluded", src=mackeep_filepath, dst=home_filepath,
                )
                print(f"Skipping {filename} (excluded)")
                continue

            if self.verbose:
                print(
                    f"Recovering\n  {mackeep_filepath}\n  to\n  {home_filepath} ...",
                )
            else:
                print(f"Recovering {filename} ...")

            if self.dry_run:
                size: int = self._plan(mackeep_filepath, home_filepath, filename)
                self._report(
                    "copy",
                    src=mackeep_filepath,
                    dst=home_filepath,
                    size_bytes=size,
                )
                if os.path.lexists(home_filepath):
                    self._report(
                        "conflict",
                        src=mackeep_filepath,
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
                        src=mackeep_filepath,
                        dst=home_filepath,
                        size_bytes=self._plan_tree(mackeep_filepath, filename)[0],
                    )
                    continue

            # Copy the file
            try:
                if is_dir:
                    self._copy_tree(mackeep_filepath, home_filepath, filename)
                else:
                    utils.copy(mackeep_filepath, home_filepath)
                    self._report(
                        "copy",
                        src=mackeep_filepath,
                        dst=home_filepath,
                        size_bytes=os.path.getsize(mackeep_filepath),
                    )
            except PermissionError as e:
                print(
                    f"Error: Unable to copy file from {mackeep_filepath} to "
                    f"{home_filepath} due to permission issue: {e}",
                )
                self._report(
                    "error", src=mackeep_filepath, dst=home_filepath, message=str(e),
                )

    def link_install(self) -> None:
        """
        Create the application config file links.

        Algorithm:
            if exists home/file
              if home/file is a real file
                if exists mackeep/file
                  are you sure?
                  if sure
                    rm mackeep/file
                    mv home/file mackeep/file
                    link mackeep/file home/file
                else
                  mv home/file mackeep/file
                  link mackeep/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackeep_filepath) = self.get_filepaths(filename)

            # A symlink cannot exclude anything, so the entries that are
            # impacted by the exclusion rules are skipped.
            reason: str | None = self._link_skip_reason(
                filename, home_filepath, home_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded", src=home_filepath, dst=mackeep_filepath,
                )
                continue

            # If the file exists and is not already a link pointing to Mackeep
            if (os.path.isfile(home_filepath) or os.path.isdir(home_filepath)) and not (
                os.path.islink(home_filepath)
                and (
                    os.path.isfile(mackeep_filepath)
                    or os.path.isdir(mackeep_filepath)
                )
                and os.path.samefile(home_filepath, mackeep_filepath)
            ):
                if self.verbose:
                    print(
                        f"Backing up\n  {home_filepath}\n  to\n"
                        f"  {mackeep_filepath} ...",
                    )
                else:
                    print(f"Linking {filename} ...")

                if self.dry_run:
                    continue

                # Check if we already have a backup
                if os.path.exists(mackeep_filepath):
                    # Name it right
                    if os.path.isfile(mackeep_filepath):
                        file_type = "file"
                    elif os.path.isdir(mackeep_filepath):
                        file_type = "folder"
                    elif os.path.islink(mackeep_filepath):
                        file_type = "link"
                    else:
                        raise ValueError(f"Unsupported file: {mackeep_filepath}")

                    # Ask the user if he really wants to replace it
                    if utils.confirm(
                        f"A {file_type} named {mackeep_filepath} already exists in the"
                        " backup.\nAre you sure that you want to"
                        " replace it?",
                    ):
                        # Delete the file in Mackeep
                        utils.delete(mackeep_filepath)
                        # Copy the file
                        utils.copy(home_filepath, mackeep_filepath)
                        # Delete the file in the home
                        utils.delete(home_filepath)
                        # Link the backuped file to its original place
                        utils.link(mackeep_filepath, home_filepath)
                else:
                    # Copy the file
                    utils.copy(home_filepath, mackeep_filepath)
                    # Delete the file in the home
                    utils.delete(home_filepath)
                    # Link the backuped file to its original place
                    utils.link(mackeep_filepath, home_filepath)
            elif self.verbose:
                if os.path.exists(home_filepath):
                    print(
                        f"Doing nothing\n  {home_filepath}\n  "
                        f"is already backed up to\n  {mackeep_filepath}",
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
            if exists mackeep/file
              if exists home/file
                are you sure?
                if sure
                  rm home/file
                  link mackeep/file home/file
              else
                link mackeep/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackeep_filepath) = self.get_filepaths(filename)

            # A symlink cannot exclude anything, so the entries that are
            # impacted by the exclusion rules are skipped.
            reason: str | None = self._link_skip_reason(
                filename, mackeep_filepath, mackeep_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded", src=mackeep_filepath, dst=home_filepath,
                )
                continue

            # If the file exists and is not already pointing to the mackeep file
            # and the folder makes sense on the current platform (Don't sync
            # any subfolder of ~/Library on GNU/Linux)
            file_or_dir_exists: bool = (
                os.path.isfile(mackeep_filepath)
                or os.path.isdir(mackeep_filepath)
            )
            pointing_to_mackeep: bool = (
                os.path.islink(home_filepath)
                and os.path.exists(mackeep_filepath)
                and os.path.samefile(mackeep_filepath, home_filepath)
            )
            supported: bool = utils.can_file_be_synced_on_current_platform(filename)

            if file_or_dir_exists and not pointing_to_mackeep and supported:
                if self.verbose:
                    print(
                        f"Restoring\n  linking {home_filepath}\n"
                        f"  to      {mackeep_filepath} ...",
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
                        utils.link(mackeep_filepath, home_filepath)
                else:
                    utils.link(mackeep_filepath, home_filepath)
            elif self.verbose:
                if os.path.exists(home_filepath):
                    print(
                        f"Doing nothing\n  {mackeep_filepath}\n  "
                        f"  already linked by\n  {home_filepath}",
                    )
                elif os.path.islink(home_filepath):
                    print(
                        f"Doing nothing\n  {home_filepath}\n  "
                        "is a broken link, you might want to fix it.",
                    )
                else:
                    print(
                        f"Doing nothing\n  {mackeep_filepath}\n  does not exist",
                    )

    def link_uninstall(self) -> None:
        """
        Removes links and copy config files from the remote folder locally.

        Algorithm:
            for each file in config
                if mackeep/file exists
                    if home/file exists
                        delete home/file
                    copy mackeep/file home/file
        """
        # For each file used by the application
        for filename in self.files:
            (home_filepath, mackeep_filepath) = self.get_filepaths(filename)

            # If the mackeep file exists
            if os.path.isfile(mackeep_filepath) or os.path.isdir(mackeep_filepath):
                # Check if there is a corresponding file in the home folder
                if os.path.exists(home_filepath):
                    # If the home file is not a link or does not point to the
                    # mackeep file, display a warning and skip it.
                    if not os.path.islink(home_filepath) or not os.path.samefile(
                        home_filepath, mackeep_filepath,
                    ):
                        print(
                            f'Warning: the file in your home "{home_filepath}" '
                            f"does not point to the original file in Mackeep "
                            f"{mackeep_filepath}, skipping...",
                        )
                        continue
                    if self.verbose:
                        print(
                            f"Reverting {mackeep_filepath}\n at {home_filepath} ...",
                        )
                    else:
                        print(f"Reverting {filename} ...")

                    if self.dry_run:
                        continue

                    # If there is, delete it as we are gonna copy the Dropbox
                    # one there
                    utils.delete(home_filepath)

                    # Copy the Dropbox file to the home folder
                    utils.copy(mackeep_filepath, home_filepath)
            elif self.verbose:
                print(f"Doing nothing, {mackeep_filepath} does not exist")
