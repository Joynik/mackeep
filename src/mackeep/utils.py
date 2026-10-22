"""System static utilities being used by the modules."""

import base64
import binascii
import errno
import fnmatch
import os
import platform
import shutil
import sqlite3
import stat
import subprocess
import sys
from contextlib import closing
from pathlib import Path
from typing import NoReturn

from . import constants

# Flag that controls how user confirmation works.
# If True, the user wants to say "yes" to everything.
FORCE_YES: bool = False
# If True, the user wants to say "no" to everything.
FORCE_NO: bool = False

# Flag that control if mackeep can be run as root
CAN_RUN_AS_ROOT: bool = False

# The legacy paths that were used during this run
LEGACY_WARNINGS: list[str] = []


# The files that hold a public key, they are not secrets
SAFE_SUFFIXES: tuple[str, ...] = (".pub",)


def sensitive_reason(path: str) -> str | None:
    """
    Get the reason why a path holds secrets, if it does.

    The path is relative to the home directory, or to the XDG config home.

    Args:
        path (str): The path, relative to the home directory.

    Returns:
        str or None: The reason, None when the path is not sensitive.
    """
    if path.endswith(SAFE_SUFFIXES):
        return None

    for pattern, reason in constants.SENSITIVE_PATTERNS.items():
        if fnmatch.fnmatch(path, pattern):
            return reason
    return None


def sensitive_path_reason(path: str) -> str | None:
    """Classify an absolute local path against HOME and XDG logical roots."""
    if not path:
        return None
    absolute = os.path.abspath(path)
    home = os.path.abspath(os.path.expanduser("~"))
    xdg = os.path.abspath(
        os.path.expanduser(
            os.environ.get("XDG_CONFIG_HOME", os.path.join(home, ".config")),
        ),
    )
    for root in (home, xdg):
        if os.path.commonpath((absolute, root)) == root:
            reason = sensitive_reason(os.path.relpath(absolute, root))
            if reason:
                return reason
    return sensitive_reason(absolute)




def legacy_warning(message: str) -> None:
    """
    Remember a legacy path that was used, to warn about it once.

    The same message is only remembered once, the warning is printed once
    per run.

    Args:
        message (str): What was found and what to do with it.
    """
    if message in LEGACY_WARNINGS:
        return

    LEGACY_WARNINGS.append(message)


def print_legacy_warnings() -> None:
    """Warn once about the legacy paths that were used."""
    if not LEGACY_WARNINGS:
        return

    warnings: list[str] = LEGACY_WARNINGS.copy()
    LEGACY_WARNINGS.clear()

    print("Warning: legacy Mackup paths are found:", file=sys.stderr)
    for warning in warnings:
        print(f"  - {warning}", file=sys.stderr)
    print(
        "Run 'mackeep migrate' to copy them to the new locations.",
        file=sys.stderr,
    )


def confirm(question: str) -> bool:
    """
    Ask the user if he really wants something to happen.

    Args:
        question(str): What can happen

    Returns:
        (boolean): Confirmed or not
    """
    if FORCE_YES:
        return True
    if FORCE_NO:
        return False

    while True:
        try:
            answer: str = input(question + " <Yes|No> ").lower()
        except EOFError:
            return False

        if answer in {"yes", "y"}:
            confirmed: bool = True
            break
        if answer in {"no", "n"}:
            confirmed = False
            break

    return confirmed




def copy(
    src: str,
    dst: str,
    *,
    preserve_link: bool = False,
    private: bool = True,
) -> None:
    """
    Copy a file or a folder (recursively) from src to dst.

    For the sake of simplicity, both src and dst must be absolute path and must
    include the filename of the file or folder.
    Also do not include any trailing slash.

    e.g. copy('/path/to/src_file', '/path/to/dst_file')
    or copy('/path/to/src_folder', '/path/to/dst_folder')

    But not: copy('/path/to/src_file', 'path/to/')
    or copy('/path/to/src_folder/', '/path/to/dst_folder')

    Args:
        src (str): Source file or folder
        dst (str): Destination file or folder
    """
    if not isinstance(src, str) or not isinstance(dst, str):
        raise TypeError("Copy paths must be strings")
    if not os.path.lexists(src):
        raise FileNotFoundError(src)

    # Create the path to the dst file if it does not exist
    abs_path = os.path.dirname(os.path.abspath(dst))
    if not os.path.isdir(abs_path):
        os.makedirs(abs_path)

    # Nested links are preserved without reading their targets.
    if preserve_link and os.path.islink(src):
        os.symlink(os.readlink(src), dst)
        return

    # We need to copy a single file
    if os.path.isfile(src):
        # Copy the src file to dst
        shutil.copy2(src, dst)

    # We need to copy a whole folder
    elif os.path.isdir(src):
        shutil.copytree(
            src,
            dst,
            dirs_exist_ok=True,
            symlinks=True,
            copy_function=shutil.copy2,
        )

    # What the heck is this?
    else:
        raise ValueError(f"Unsupported file: {src}")

    # Set the good mode to the file or folder recursively
    if private:
        chmod(dst)


def link(target: str, link_to: str) -> None:
    """
    Create a link to a target file or a folder.

    For the sake of simplicity, both target and link_to must be absolute path and must
    include the filename of the file or folder.
    Also do not include any trailing slash.

    e.g. link('/path/to/file', '/path/to/link')

    But not: link('/path/to/file', 'path/to/')
    or link('/path/to/folder/', '/path/to/link')

    Args:
        target (str): file or folder the link will point to
        link_to (str): Link to create
    """
    if not isinstance(target, str):
        raise TypeError("Target must be a string")
    if not os.path.exists(target):
        raise FileNotFoundError(target)
    if not isinstance(link_to, str):
        raise TypeError("Link path must be a string")

    # Create the path to the link if it does not exist
    abs_path = os.path.dirname(os.path.abspath(link_to))
    if not os.path.isdir(abs_path):
        os.makedirs(abs_path)

    # Make sure the file or folder recursively has the good mode
    chmod(target)

    # Create the link to target
    os.symlink(target, link_to)


def chmod(target: str) -> None:
    """
    Recursively set the chmod for files to 0600 and 0700 for folders.

    It's ok unless we need something more specific.

    Args:
        target (str): Root file or folder
    """
    if not isinstance(target, str):
        raise TypeError("Target must be a string")
    if not os.path.exists(target):
        raise FileNotFoundError(target)

    file_mode = stat.S_IRUSR | stat.S_IWUSR
    folder_mode = stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR

    if os.path.islink(target):
        return
    if os.path.isfile(target):
        set_mode(target, file_mode | (os.stat(target).st_mode & stat.S_IXUSR))

    elif os.path.isdir(target):
        # chmod the root item
        set_mode(target, folder_mode)

        # chmod recursively in the folder it it's one
        for root, dirs, files in os.walk(target):
            for cur_dir in dirs:
                directory = os.path.join(root, cur_dir)
                if not os.path.islink(directory):
                    set_mode(directory, folder_mode)
            for cur_file in files:
                fullpath = os.path.join(root, cur_file)
                if os.path.islink(fullpath):
                    continue
                try:
                    set_mode(
                        fullpath,
                        file_mode | (os.stat(fullpath).st_mode & stat.S_IXUSR),
                    )
                except FileNotFoundError:
                    # A broken symlink (e.g. a link restored before its
                    # target) is listed by os.walk but can't be followed by
                    # os.chmod. Skip it instead of crashing; re-raise for
                    # real missing regular files.
                    if os.path.islink(fullpath):
                        continue
                    raise

    else:
        raise ValueError(f"Unsupported file type: {target}")


def error(message: str) -> NoReturn:
    """
    Throw an error with the given message and immediately quit.

    Args:
        message(str): The message to display.
    """
    fail: str = "\033[91m"
    end: str = "\033[0m"
    text = f"Error: {message}"
    sys.exit(fail + text + end if sys.stderr.isatty() else text)


def get_dropbox_folder_location() -> str:
    """
    Try to locate the Dropbox folder.

    Returns:
        (str) Full path to the current Dropbox folder
    """
    host_db_path = os.path.join(os.path.expanduser("~"), ".dropbox/host.db")
    min_host_db_fields = 2
    try:
        with open(host_db_path, encoding="utf-8") as f_hostdb:
            data = f_hostdb.read().split()
        if len(data) < min_host_db_fields:
            raise ValueError("Malformed Dropbox host.db")
        dropbox_home = base64.b64decode(data[1], validate=True).decode()
    except (
        OSError,
        ValueError,
        binascii.Error,
        UnicodeEncodeError,
        UnicodeDecodeError,
    ):
        error(constants.ERROR_UNABLE_TO_FIND_STORAGE.format(provider="Dropbox install"))

    return dropbox_home


def get_google_drive_folder_location() -> str:
    """
    Try to locate the Google Drive folder.

    Returns:
        (str) Full path to the current Google Drive folder
    """
    gdrive_db_path = "Library/Application Support/Google/Drive/sync_config.db"
    yosemite_gdrive_db_path = (
        "Library/Application Support/Google/Drive/user_default/sync_config.db"
    )
    yosemite_gdrive_db = os.path.join(os.path.expanduser("~"), yosemite_gdrive_db_path)
    if os.path.isfile(yosemite_gdrive_db):
        gdrive_db_path = yosemite_gdrive_db

    googledrive_home: str | None = None

    gdrive_db = (
        gdrive_db_path
        if os.path.isabs(gdrive_db_path)
        else os.path.join(os.path.expanduser("~"), gdrive_db_path)
    )
    if os.path.isfile(gdrive_db):
        try:
            with closing(
                sqlite3.connect(Path(gdrive_db).as_uri() + "?mode=ro", uri=True),
            ) as con:
                cur = con.cursor()
                query = (
                    "SELECT data_value FROM data "
                    "WHERE entry_key = 'local_sync_root_path';"
                )
                cur.execute(query)
                data = cur.fetchone()
                if data and data[0]:
                    googledrive_home = str(data[0])
        except sqlite3.Error:
            googledrive_home = None

    if googledrive_home:
        return googledrive_home

    error(
        constants.ERROR_UNABLE_TO_FIND_STORAGE.format(
            provider="Google Drive install",
        ),
    )


def get_icloud_folder_location() -> str:
    """
    Try to locate the iCloud Drive folder.

    Returns:
        (str) Full path to the iCloud Drive folder.
    """
    yosemite_icloud_path = "~/Library/Mobile Documents/com~apple~CloudDocs/"

    icloud_home = os.path.expanduser(yosemite_icloud_path)

    if not os.path.isdir(icloud_home):
        error(constants.ERROR_UNABLE_TO_FIND_STORAGE.format(provider="iCloud Drive"))

    return str(icloud_home)






def set_mode(path: str, mode: int) -> None:
    """Set permissions, clearing an immutable flag only after an EPERM failure."""
    try:
        os.chmod(path, mode)
    except PermissionError as exc:
        if exc.errno != errno.EPERM or os.path.islink(path):
            raise
        if sys.platform == "darwin":
            flags = os.stat(path).st_flags & ~(stat.UF_IMMUTABLE | stat.UF_APPEND)
            os.chflags(path, flags)
        elif os.path.isfile("/usr/bin/chattr"):
            subprocess.run(["/usr/bin/chattr", "-f", "-i", "-a", path], check=True)
        else:
            raise
        os.chmod(path, mode)


def can_file_be_synced_on_current_platform(path: str) -> bool:
    """
    Check if the given path can be synced locally.

    Check if it makes sense to sync the file at the given path on the current
    platform.
    For now we don't sync any file in the ~/Library folder on GNU/Linux.
    There might be other exceptions in the future.

    Args:
        (str): Path to the file or folder to check. If relative, prepend it
               with the home folder.
               'abc' becomes '~/abc'
               '/def' stays '/def'

    Returns:
        (bool): True if given file can be synced
    """
    can_be_synced: bool = True

    # If the given path is relative, prepend home
    fullpath: str = os.path.join(os.path.expanduser("~"), path)

    # Compute the ~/Library path on macOS
    # End it with a slash because we are looking for this specific folder and
    # not any file/folder named LibrarySomething
    library_path: str = os.path.join(os.path.expanduser("~"), "Library/")

    is_linux = platform.system() == constants.PLATFORM_LINUX
    if is_linux and fullpath.startswith(library_path):
        can_be_synced = False

    return can_be_synced
