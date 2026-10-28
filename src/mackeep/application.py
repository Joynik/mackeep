"""
Application Profile.

An Application Profile contains all the information about an application in
Mackeep. Name, files, ...
"""

import os
import shutil
import sys
from collections.abc import Callable, Iterator
from functools import partial
from typing import Any

from . import utils
from .backupstate import BackupState
from .config import ConfigError
from .excludes import Matcher, Pattern
from .mackeep import Mackeep
from .paths import entry_paths, inside, validate_pair
from .transaction import Transaction

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
        if not isinstance(mackeep, Mackeep) or not isinstance(files, set):
            raise TypeError("Expected a Mackeep instance and a set of file paths")

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
        self.observer: Reporter | None = None
        self.app_name: str = ""

        # The detail level of the dry-run: "entries" or "files"
        self.detail: str = "entries"
        self.failed = False
        self.replace_backup = True
        self._sensitive_paths: set[str] = set()
        self._pending_events: list[tuple[str, dict[str, Any]]] | None = None
        self._staged_paths: dict[str, str] = {}
        self._restoring = False
        self._active_source = ""
        self.ownership_baseline: dict[str, list[str]] = {}

        # The XDG config home, relative to the home directory
        self._xdg_home: str | None = self._get_xdg_home()

    def configure(
        self,
        exclude: Matcher | None = None,
        xdg_exclude: Matcher | None = None,
        reporter: Reporter | None = None,
        app_name: str = "",
        detail: str = "",
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
            detail (str): The detail level of the dry-run, "entries" or
                          "files".
        """
        if exclude is not None:
            self.exclude = exclude
        if xdg_exclude is not None:
            self.xdg_exclude = xdg_exclude
        self.reporter = reporter
        self.app_name = app_name
        if detail:
            self.detail = detail

    @staticmethod
    def _get_xdg_home() -> str | None:
        """
        Get the XDG config home, relative to the home directory.

        Returns:
            str or None: None when the XDG config home is not in the home
                         directory.
        """
        home: str = os.path.expanduser("~")
        xdg_config_home: str = os.environ.get(
            "XDG_CONFIG_HOME",
            os.path.join(home, ".config"),
        )
        if not os.path.isabs(xdg_config_home) or not inside(xdg_config_home, home):
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
        return entry_paths(
            filename,
            self.mackeep.mackeep_folder,
            allow_external=self.mackeep.config.allow_external_paths is True,
        )

    def preflight(self, action: str) -> None:
        """Check every entry before any application changes its data."""
        for filename in self.files:
            local, backup = self.get_filepaths(filename)
            # Already installed legacy links are expected, not a replacement.
            if (
                os.path.islink(local)
                and os.path.exists(backup)
                and os.path.exists(local)
                and os.path.samefile(local, backup)
            ):
                continue
            if self.mackeep.config.allow_external_paths is not True and not inside(
                os.path.realpath(local),
                os.path.realpath(os.path.expanduser("~")),
            ):
                raise ConfigError(f"External paths are disabled: {local}")
            validate_pair(local, self.mackeep.mackeep_folder)
            if action in {"copy_files_to_mackeep_folder", "link_install"}:
                validate_pair(local, backup)
            else:
                validate_pair(backup, local)
            root = self.mackeep.mackeep_folder
            if not inside(
                os.path.realpath(os.path.dirname(backup)),
                os.path.realpath(root),
            ):
                raise ValueError(f"Backup destination parent escapes storage: {backup}")

    def _xdg_relative(self, home_relative: str) -> str | None:
        """
        Get a path relative to the XDG config home.

        Args:
            home_relative (str): The path, relative to the home directory.

        Returns:
            str or None: None when the path is not in the XDG config home.
        """
        if self._xdg_home is None:
            if self.mackeep.config.allow_external_paths is not True:
                return None
            root = os.path.abspath(
                os.path.expanduser(
                    os.environ.get(
                        "XDG_CONFIG_HOME",
                        os.path.join(os.path.expanduser("~"), ".config"),
                    ),
                ),
            )
            path = os.path.abspath(os.path.join(os.path.expanduser("~"), home_relative))
            return os.path.relpath(path, root) if inside(path, root) else None
        path = os.path.relpath(
            os.path.abspath(os.path.join(os.path.expanduser("~"), home_relative)),
            os.path.expanduser("~"),
        )
        if path == self._xdg_home:
            return ""
        prefix: str = f"{self._xdg_home}/"
        if path.startswith(prefix):
            return path[len(prefix) :]
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

        if not self.xdg_exclude:
            return False
        xdg_relative: str | None = self._xdg_relative(home_relative)
        return bool(
            xdg_relative and self.xdg_exclude.is_excluded(xdg_relative, is_dir),
        )

    def exclusion_reason(
        self,
        home_relative: str,
        is_dir: bool = False,
    ) -> dict[str, str] | None:
        """
        Get the reason why a path is excluded.

        Args:
            home_relative (str): The path, relative to the home directory.
            is_dir (bool): Whether the path is a directory.

        Returns:
            dict or None: The pattern that excluded the path, the section
            and the config file it comes from. None when the path is not
            excluded.
        """
        pattern: Pattern | None = self.exclude.match(home_relative, is_dir)
        if pattern is not None and not pattern.negated:
            return self._reason(pattern)

        if not self.xdg_exclude:
            return None
        xdg_relative: str | None = self._xdg_relative(home_relative)
        if xdg_relative:
            pattern = self.xdg_exclude.match(xdg_relative, is_dir)
            if pattern is not None and not pattern.negated:
                return self._reason(pattern)

        return None

    @staticmethod
    def _reason(pattern: Pattern) -> dict[str, str]:
        """
        Build the reason of an exclusion.

        Args:
            pattern (Pattern): The pattern that excluded the path.

        Returns:
            dict
        """
        return {
            "pattern": pattern.raw,
            "section": pattern.section,
            "file": pattern.file,
        }

    def _report(self, action: str, **details: Any) -> None:
        """
        Report an operation to the reporter, if any.

        The paths that hold secrets are marked, so the front-ends can warn
        about them. The human-readable output warns about them once.

        Args:
            action (str): The action, e.g. "copy" or "skip_excluded".
            details: The details of the operation.
        """
        for staged, destination in self._staged_paths.items():
            path = str(details.get("dst", ""))
            if inside(path, staged):
                details["dst"] = (
                    os.path.join(destination, os.path.relpath(path, staged))
                    if path != staged
                    else destination
                )
                break
        if self._pending_events is not None:
            if self._restoring and action == "copy":
                details["would_overwrite"] = os.path.lexists(
                    str(details.get("dst", "")),
                )
            self._pending_events.append((action, details))
            return
        local = str(details.get("dst" if self._restoring else "src", ""))
        relative: str = self._home_relative(local)
        reason = utils.sensitive_path_reason(local)
        details["sensitive"] = reason is not None
        details["sensitive_reason"] = reason

        if self.observer is not None:
            self.observer(action, {"app": self.app_name, "action": action, **details})
        if self.reporter is None:
            if action == "copy" and reason is not None:
                self._sensitive_paths.add(relative)
            return
        payload: dict[str, Any] = {"app": self.app_name, "action": action}
        payload.update(details)
        self.reporter(action, payload)

    @staticmethod
    def _home_relative(path: str) -> str:
        """
        Get the path relative to the home directory, when it is inside it.

        Args:
            path (str): The path of a file.

        Returns:
            str: The path relative to the home directory, an empty string
            when the path is outside of it.
        """
        if not path:
            return ""

        home: str = os.path.expanduser("~")
        try:
            relative: str = os.path.relpath(path, home)
        except ValueError:
            return ""

        if relative.startswith(".."):
            return ""

        return relative

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
        for name in sorted(os.listdir(src)):
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            is_dir: bool = os.path.isdir(path)

            yield path, relative_path, is_dir

            if is_dir and not os.path.islink(path):
                yield from self._walk(path, relative_path)

    def _report_excluded(
        self,
        path: str,
        relative_path: str,
        dst: str,
        reason: dict[str, str],
    ) -> None:
        """
        Report an excluded path.

        Args:
            path (str): The path of the excluded file or folder.
            relative_path (str): The path, relative to the home directory.
            dst (str): The path the file would have been copied to.
            reason (dict): The pattern that excluded the path.
        """
        self._report("skip_excluded", src=path, dst=dst, reason=reason)
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

            reason: dict[str, str] | None = self.exclusion_reason(
                relative_path,
                is_dir,
            )
            if reason is not None:
                # An excluded directory is not walked.
                self._report_excluded(path, relative_path, destination, reason)
                continue

            if is_dir and not os.path.islink(path):
                copied += self._copy_tree(path, destination, relative_path)
                continue

            utils.copy(path, destination, preserve_link=True)
            size: int = self._file_size(path)
            copied += size
            self._report("copy", src=path, dst=destination, size_bytes=size)

        # Set the good mode to the file or folder recursively
        shutil.copystat(src, dst)
        utils.set_mode(dst, 0o700)

        return copied

    def _plan_tree(
        self,
        src: str,
        relative: str,
    ) -> tuple[int, list[tuple[str, str, dict[str, str]]]]:
        """
        Compute what would be copied, without copying anything.

        Args:
            src (str): The path of the file or directory.
            relative (str): The path, relative to the home directory.

        Returns:
            tuple: The number of bytes that would be copied and the list of
            the excluded paths, as (path, relative path, reason) tuples.
        """
        if not os.path.isdir(src):
            return os.path.getsize(src), []

        size: int = 0
        excluded: list[tuple[str, str, dict[str, str]]] = []

        for name in sorted(os.listdir(src)):
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            is_dir: bool = os.path.isdir(path)

            reason: dict[str, str] | None = self.exclusion_reason(
                relative_path,
                is_dir,
            )
            if reason is not None:
                excluded.append((path, relative_path, reason))
                continue

            if is_dir and not os.path.islink(path):
                sub_size, sub_excluded = self._plan_tree(path, relative_path)
                size += sub_size
                excluded.extend(sub_excluded)
            else:
                size += self._file_size(path)

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
        for path, relative_path, reason in excluded:
            destination: str = os.path.join(dst, os.path.relpath(path, src))
            self._report_excluded(path, relative_path, destination, reason)
        return size

    def _plan_files(self, src: str, dst: str, relative: str) -> None:
        """
        Report what would be copied, one entry per file.

        The excluded directories are not walked, they are reported as a
        single entry.

        Args:
            src (str): The path of the file or directory.
            dst (str): The path of the destination.
            relative (str): The path, relative to the home directory.
        """
        if not os.path.isdir(src):
            self._report_file(src, dst, follow_link=True)
            return

        for name in sorted(os.listdir(src)):
            path: str = os.path.join(src, name)
            relative_path: str = f"{relative}/{name}" if relative else name
            destination: str = os.path.join(dst, name)
            is_dir: bool = os.path.isdir(path)

            reason: dict[str, str] | None = self.exclusion_reason(
                relative_path,
                is_dir,
            )
            if reason is not None:
                # An excluded directory is not walked.
                self._report_excluded(path, relative_path, destination, reason)
                continue

            if is_dir and not os.path.islink(path):
                self._plan_files(path, destination, relative_path)
                continue

            self._report_file(path, destination)

    def _report_file(self, src: str, dst: str, *, follow_link: bool = False) -> None:
        """
        Report a file that would be copied.

        A file that already exists in the destination is reported as a
        conflict, and not as a copy.

        Args:
            src (str): The path of the file.
            dst (str): The path of the destination.
        """
        size = os.path.getsize(src) if follow_link else self._file_size(src)
        if os.path.lexists(dst):
            self._report(
                "conflict",
                src=src,
                dst=dst,
                size_bytes=size,
                would_overwrite=True,
            )
            return
        self._report("copy", src=src, dst=dst, size_bytes=size)

    def _plan_copy(self, src: str, dst: str, relative: str) -> None:
        """
        Report what would be copied, without copying anything.

        Args:
            src (str): The path of the file or directory.
            dst (str): The path of the destination.
            relative (str): The path, relative to the home directory.
        """
        if self.detail == "files":
            self._plan_files(src, dst, relative)
            return

        size: int = self._plan(src, dst, relative)
        self._report("copy", src=src, dst=dst, size_bytes=size)
        if os.path.lexists(dst):
            self._report("conflict", src=src, dst=dst, size_bytes=size)

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
        if not self.exclude and not self.xdg_exclude:
            return False
        for _path, relative_path, is_dir in self._walk(src, relative):
            if self.is_excluded(relative_path, is_dir):
                return True
        return False

    def _report_stale(
        self,
        relative: str,
        home_filepath: str,
        mackeep_filepath: str,
        protected: set[str] | None = None,
    ) -> None:
        """
        Report the files of the backup that are now excluded.

        The plan reports removal after successful replacement.

        Args:
            relative (str): The path of the entry, relative to the home
                            directory.
            home_filepath (str): The path of the entry in the home folder.
            mackeep_filepath (str): The path of the entry in the Mackeep
                                   folder.
        """
        if not os.path.isdir(mackeep_filepath):
            return

        for name in sorted(os.listdir(mackeep_filepath)):
            path = os.path.join(mackeep_filepath, name)
            source = os.path.join(home_filepath, name)
            relative_path = f"{relative}/{name}"
            is_dir = os.path.isdir(path)
            if protected and path in protected:
                continue
            if (
                protected
                and is_dir
                and not os.path.islink(path)
                and any(inside(other, path) for other in protected)
            ):
                self._report_stale(relative_path, source, path, protected)
            elif self.is_excluded(relative_path, is_dir):
                print(f"Note: {relative_path} will be removed from the backup.")
                self._report("stale_in_backup", src=source, dst=path, will_remove=True)
            elif is_dir and not os.path.islink(path):
                self._report_stale(relative_path, source, path, protected)

    def _link_skip_reason(
        self,
        relative: str,
        entry_filepath: str,
        source_filepath: str,
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
            return "it contains excluded files and a symlink cannot exclude them"

        return None

    @staticmethod
    def _file_size(path: str) -> int:
        """Measure a link itself rather than following a possibly broken target."""
        return os.lstat(path).st_size

    @staticmethod
    def _inventory(root: str) -> set[str]:
        """List leaf entries, including symbolic links and empty directories."""
        if os.path.islink(root) or not os.path.isdir(root):
            return {""}
        entries: set[str] = set()
        for name in os.listdir(root):
            path = os.path.join(root, name)
            entries.update(
                os.path.join(name, child) if child else name
                for child in ApplicationProfile._inventory(path)
            )
        return entries or {""}

    def _preserve_local_exclusions(
        self,
        existing: str,
        staged: str,
        relative: str,
    ) -> None:
        """Keep excluded local entries when replacing a restored directory."""
        if (
            not (self.exclude or self.xdg_exclude)
            or os.path.islink(existing)
            or not os.path.isdir(existing)
        ):
            return
        for name in os.listdir(existing):
            old = os.path.join(existing, name)
            new = os.path.join(staged, name)
            entry = f"{relative}/{name}"
            if self.is_excluded(entry, os.path.isdir(old)):
                if not os.path.lexists(new):
                    utils.copy(old, new, preserve_link=True, private=False)
            elif os.path.isdir(old) and not os.path.islink(old):
                self._preserve_local_exclusions(old, new, entry)

    def _stage_copy(
        self,
        source: str,
        destination: str,
        relative: str,
        staged: str,
    ) -> None:
        """Build a fresh replacement without borrowing the old backup contents."""
        self._active_source = source
        self._staged_paths[staged] = destination
        if os.path.isdir(source):
            self._copy_tree(source, staged, relative)
            if self._restoring:
                self._preserve_local_exclusions(destination, staged, relative)
        else:
            utils.copy(source, staged)
            self._report(
                "copy",
                src=source,
                dst=destination,
                size_bytes=os.path.getsize(source),
            )

        if self._restoring:
            paths = [staged]
            if os.path.isdir(staged):
                for parent, directories, files in os.walk(staged):
                    paths.extend(
                        os.path.join(parent, name) for name in directories + files
                    )
            for path in reversed(paths):
                suffix = os.path.relpath(path, staged)
                entry = relative if suffix == "." else f"{relative}/{suffix}"
                if os.path.islink(path) or self.is_excluded(entry, os.path.isdir(path)):
                    continue
                backup = source if suffix == "." else os.path.join(source, suffix)
                key = os.path.relpath(backup, self.mackeep.mackeep_folder)
                mode = self._restore_modes.get(key)
                if mode is not None:
                    utils.set_mode(path, mode)

    def _prepare_entry(
        self,
        filename: str,
        transaction: Transaction,
        state: BackupState | None,
        owned: set[str],
        changed_roots: list[str],
    ) -> None:
        """Plan or stage one entry, retaining ownership of declined replacements."""
        local, backup = self.get_filepaths(filename)
        if any(inside(backup, root) for root in changed_roots):
            return
        source, destination = (backup, local) if self._restoring else (local, backup)
        if not os.path.exists(source):
            self._report("skip_missing", src=source, dst=destination)
            if state:
                state.keep_previous(self.app_name, backup, owned)
            return
        if self.is_excluded(filename, os.path.isdir(source)):
            self._report("skip_excluded", src=source, dst=destination)
            return
        linked = (
            os.path.islink(local)
            and os.path.exists(local)
            and os.path.exists(backup)
            and os.path.samefile(local, backup)
        )
        if linked and not self._restoring:
            if self.verbose:
                print(f"Skipping {local}, already linked to {backup}")
            if state:
                state.keep_previous(self.app_name, backup, owned)
            return
        print(f"{'Recovering' if self._restoring else 'Backing up'} {filename} ...")
        if self.dry_run:
            self._plan_copy(source, destination, filename)
            if state:
                self._report_stale(
                    filename,
                    local,
                    backup,
                    {
                        os.path.join(state.root, path)
                        for path in state.others(self.app_name)
                    },
                )
                owned.update(
                    state.relative(os.path.join(destination, leaf))
                    for leaf in self._inventory_filtered(
                        os.path.realpath(source),
                        filename,
                    )
                )
            changed_roots.append(backup)
            return
        if (
            os.path.lexists(destination)
            and (self._restoring or not self.replace_backup)
            and not utils.confirm(
                f"A file or folder named {destination} already exists. Replace it?",
            )
        ):
            self.failed = True
            self._report(
                "conflict",
                src=source,
                dst=destination,
                size_bytes=self._plan_tree(source, filename)[0],
            )
            if state:
                state.keep_previous(self.app_name, backup, owned)
            return

        def build(staged: str) -> None:
            self._stage_copy(source, destination, filename, staged)
            if state:
                owned.update(
                    state.relative(os.path.join(destination, leaf))
                    for leaf in self._inventory(staged)
                )
                state.record_modes(source, staged, destination)
                state.preserve_shared(self.app_name, destination, staged)

        transaction.prepare(destination, build)
        changed_roots.append(backup)

    def _prepare_cleanup(
        self,
        state: BackupState,
        transaction: Transaction,
        owned: set[str],
        changed_roots: list[str],
    ) -> None:
        """Stage only obsolete leaves that have no remaining owner."""
        obsolete_paths = (
            set(state.owners.get(self.app_name, []))
            - owned
            - state.others(self.app_name)
        )
        for path in sorted(obsolete_paths):
            obsolete = os.path.join(state.root, path)
            if any(inside(obsolete, root) for root in changed_roots):
                continue
            if not os.path.lexists(obsolete):
                continue
            if not inside(
                os.path.realpath(os.path.dirname(obsolete)),
                os.path.realpath(state.root),
            ):
                raise ValueError(f"Cleanup path escapes storage: {obsolete}")
            if (
                os.path.isdir(obsolete)
                and not os.path.islink(obsolete)
                and os.listdir(obsolete)
            ):
                continue
            if (
                not self.dry_run
                and not self.replace_backup
                and not utils.confirm(
                    f"Remove obsolete backup entry {obsolete}?",
                )
            ):
                self.failed = True
                owned.add(path)
                self._report("conflict", src=obsolete, dst=obsolete)
                continue
            self._report(
                "stale_in_backup",
                src=obsolete,
                dst=obsolete,
                will_remove=True,
            )
            if not self.dry_run:
                transaction.prepare(obsolete, None)
        if not self.dry_run:
            state.save(transaction, self.app_name, owned)

    def _copy_entries(self, *, to_backup: bool) -> None:
        """Stage an application's replacements, cleanup, and ownership together."""
        self._restoring = not to_backup
        self.preflight(
            "copy_files_to_mackeep_folder"
            if to_backup
            else "copy_files_from_mackeep_folder",
        )
        self._restore_modes = (
            BackupState(self.mackeep.mackeep_folder).modes if not to_backup else {}
        )
        state = (
            BackupState(self.mackeep.mackeep_folder)
            if to_backup and self.app_name
            else None
        )
        if state and not state.owners:
            state.owners.update(self.ownership_baseline)
        transaction = Transaction()
        owned: set[str] = set()
        changed_roots: list[str] = []
        self._pending_events = [] if not self.dry_run else None
        try:
            for filename in self.files:
                self._prepare_entry(filename, transaction, state, owned, changed_roots)
            if state:
                self._prepare_cleanup(state, transaction, owned, changed_roots)
            if not self.dry_run:
                transaction.commit()
                events = self._pending_events or []
                self._pending_events = None
                for event, details in events:
                    self._report(event, **details)
        except OSError as exc:
            self.failed = True
            self._pending_events = None
            qualifier = (
                "permission issue" if isinstance(exc, PermissionError) else "I/O error"
            )
            print(
                f"Error: Unable to copy file for application {self.app_name} "
                f"from {self._active_source} ({qualifier}): {exc}",
            )
            self._report("error", message=str(exc))
        finally:
            self._pending_events = None
            self._staged_paths.clear()
            transaction.close()
            if self._sensitive_paths:
                paths = ", ".join(sorted(self._sensitive_paths)[:10])
                print(
                    f"Warning: {self.app_name or 'Application'} holds secrets in "
                    f"{len(self._sensitive_paths)} paths ({paths}). "
                    "Backups are unencrypted.",
                    file=sys.stderr,
                )
                self._sensitive_paths.clear()
        if state and not self.dry_run and not self.failed:
            state.prune_empty_parents(self.app_name, owned)

    def _inventory_filtered(self, source: str, relative: str) -> set[str]:
        """Inventory the dry-run without following nested directory links."""
        if os.path.islink(source) or not os.path.isdir(source):
            return {""}
        entries: set[str] = set()
        for name in os.listdir(source):
            path = os.path.join(source, name)
            entry = f"{relative}/{name}"
            if self.is_excluded(entry, os.path.isdir(path)):
                continue
            entries.update(
                os.path.join(name, leaf) if leaf else name
                for leaf in self._inventory_filtered(path, entry)
            )
        return entries or {""}

    def copy_files_to_mackeep_folder(self) -> None:
        """Replace this application's backup after preparing all its copies."""
        self._copy_entries(to_backup=True)

    def copy_files_from_mackeep_folder(self) -> None:
        """Restore this application while retaining excluded local entries."""
        self._copy_entries(to_backup=False)

    def _install_link(self, local: str, backup: str) -> None:
        """Stage both backup data and the local link before replacing either."""
        transaction = Transaction()
        try:
            transaction.prepare(backup, lambda staged: utils.copy(local, staged))
            transaction.prepare(local, lambda staged: os.symlink(backup, staged))
            transaction.commit()
        finally:
            transaction.close()

    @staticmethod
    def _replace_with_link(backup: str, local: str) -> None:
        """Create a link before replacing an existing local entry."""
        transaction = Transaction()
        try:
            transaction.prepare(local, lambda staged: utils.link(backup, staged))
            transaction.commit()
        finally:
            transaction.close()

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
                filename,
                home_filepath,
                home_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded",
                    src=home_filepath,
                    dst=mackeep_filepath,
                )
                continue

            # If the file exists and is not already a link pointing to Mackeep
            if (os.path.isfile(home_filepath) or os.path.isdir(home_filepath)) and not (
                os.path.islink(home_filepath)
                and (
                    os.path.isfile(mackeep_filepath) or os.path.isdir(mackeep_filepath)
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
                    if not utils.confirm(
                        f"A {file_type} named {mackeep_filepath} already exists "
                        "in the backup. Replace it?",
                    ):
                        continue
                self._install_link(home_filepath, mackeep_filepath)
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
                filename,
                mackeep_filepath,
                mackeep_filepath,
            )
            if reason:
                print(f"Skipping {filename}, {reason}")
                self._report(
                    "skip_excluded",
                    src=mackeep_filepath,
                    dst=home_filepath,
                )
                continue

            # If the file exists and is not already pointing to the mackeep file
            # and the folder makes sense on the current platform (Don't sync
            # any subfolder of ~/Library on GNU/Linux)
            file_or_dir_exists: bool = os.path.isfile(
                mackeep_filepath,
            ) or os.path.isdir(mackeep_filepath)
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
                        self._replace_with_link(mackeep_filepath, home_filepath)
                else:
                    self._replace_with_link(mackeep_filepath, home_filepath)
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
                        home_filepath,
                        mackeep_filepath,
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

                    transaction = Transaction()
                    try:
                        transaction.prepare(
                            home_filepath,
                            partial(utils.copy, mackeep_filepath),
                        )
                        transaction.commit()
                    finally:
                        transaction.close()
            elif self.verbose:
                print(f"Doing nothing, {mackeep_filepath} does not exist")
