import os
import sqlite3
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import pytest

from mackeep import utils


def convert_to_octal(file_name):
    """
    Using os.stat, returns file permissions (read, write, execute) as an octal.
    """
    return oct(os.stat(file_name)[stat.ST_MODE])[-3:]


class TestMackeep(unittest.TestCase):
    def test_confirm_yes(self):
        # Override the input used in utils
        with patch.object(utils, "input", return_value="Yes", create=True):
            assert utils.confirm("Answer Yes to this question")

    def test_confirm_no(self):
        # Override the input used in utils
        with patch.object(utils, "input", return_value="No", create=True):
            assert not utils.confirm("Answer No to this question")

    def test_confirm_typo(self):
        for answer, expected in (("No", False), ("Yes", True)):
            with (
                self.subTest(answer=answer),
                patch.object(
                    utils,
                    "input",
                    side_effect=["unexpected", answer],
                    create=True,
                ) as prompt,
            ):
                assert utils.confirm("Retry invalid input") is expected
                assert prompt.call_count == len(["unexpected", answer])

    def test_delete_file(self):
        # Create a tmp file
        with tempfile.NamedTemporaryFile(delete=False) as tfile:
            tfpath = tfile.name

        # Make sure the created file exists
        assert os.path.isfile(tfpath)

        # Check if mackeep can really delete it
        utils.delete(tfpath)
        assert not os.path.exists(tfpath)

    def test_delete_folder_recursively(self):
        # Create a tmp folder
        tfpath = tempfile.mkdtemp()

        # Let's put a file in it just for fun
        with tempfile.NamedTemporaryFile(dir=tfpath, delete=False) as tfile:
            filepath = tfile.name

        # Let's put another folder in it
        subfolder_path = tempfile.mkdtemp(dir=tfpath)

        # And a file in the subfolder
        with tempfile.NamedTemporaryFile(dir=subfolder_path, delete=False) as tfile:
            subfilepath = tfile.name

        # Make sure the created files and folders exists
        assert os.path.isdir(tfpath)
        assert os.path.isfile(filepath)
        assert os.path.isdir(subfolder_path)
        assert os.path.isfile(subfilepath)

        # Check if mackeep can really delete it
        utils.delete(tfpath)
        assert not os.path.exists(tfpath)
        assert not os.path.exists(filepath)
        assert not os.path.exists(subfolder_path)
        assert not os.path.exists(subfilepath)

    def test_copy_file(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            destination = Path(directory) / "nested/copy"
            content = b"settings=enabled\n\x00\xff"
            source.write_bytes(content)
            utils.copy(str(source), str(destination))
            assert destination.is_file()
            assert destination.read_bytes() == content
            assert source.read_bytes() == content

    def test_copy_fail(self):
        # Create a tmp FIFO file
        with tempfile.NamedTemporaryFile() as tfile:
            srcfile = tfile.name
        os.mkfifo(srcfile)

        # Create a tmp folder
        dstpath = tempfile.mkdtemp()
        # Set the destination filename
        dstfile = os.path.join(dstpath, "subfolder", os.path.basename(srcfile))

        # Make sure the source file and destination folder exist and the
        # destination file doesn't yet exist
        assert not os.path.isfile(srcfile)
        assert stat.S_ISFIFO(os.stat(srcfile).st_mode)
        assert os.path.isdir(dstpath)
        assert not os.path.exists(dstfile)

        # Check if mackeep can copy it
        with pytest.raises(ValueError, match="Unsupported file"):
            utils.copy(srcfile, dstfile)
        assert not os.path.isfile(srcfile)
        assert stat.S_ISFIFO(os.stat(srcfile).st_mode)
        assert os.path.isdir(dstpath)
        assert not os.path.exists(dstfile)

        # Let's clean up
        utils.delete(srcfile)
        utils.delete(dstpath)

    def test_copy_file_to_dir(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            destination = Path(directory) / "existing"
            destination.mkdir()
            source.write_bytes(b"nonempty config\x00\xff")
            # utils.copy takes the complete destination path, including the filename.
            utils.copy(str(source), str(destination / source.name))
            assert list(destination.iterdir()) == [destination / source.name]
            assert (destination / source.name).read_bytes() == source.read_bytes()
            assert source.read_bytes() == b"nonempty config\x00\xff"

    def test_copy_dir(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            destination = Path(directory) / "new/tree"
            (source / "sub").mkdir(parents=True)
            expected = {"config": b"main", "sub/binary": b"\x00\xffnested"}
            for relative, content in expected.items():
                (source / relative).write_bytes(content)
            utils.copy(str(source), str(destination))
            assert destination.is_dir()
            for root in (source, destination):
                assert {
                    str(p.relative_to(root)): p.read_bytes()
                    for p in root.rglob("*")
                    if p.is_file()
                } == expected

    def test_copy_dir_that_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            destination = Path(directory) / "destination"
            for root in (source, destination):
                (root / "sub").mkdir(parents=True)
            (source / "sub/config").write_bytes(b"new contents\x00")
            (destination / "sub/config").write_bytes(b"old contents")
            (destination / "unrelated").write_bytes(b"keep")
            utils.copy(str(source), str(destination))
            assert destination.is_dir()
            assert (source / "sub/config").read_bytes() == b"new contents\x00"
            assert {
                str(p.relative_to(destination)): p.read_bytes()
                for p in destination.rglob("*")
                if p.is_file()
            } == {
                "sub/config": b"new contents\x00",
                "unrelated": b"keep",
            }

    def test_link_file(self):
        # Create a tmp file
        with tempfile.NamedTemporaryFile(delete=False) as tfile:
            srcfile = tfile.name

        # Create a tmp folder
        dstpath = tempfile.mkdtemp()
        # Set the destination filename
        dstfile = os.path.join(dstpath, "subfolder", os.path.basename(srcfile))

        # Make sure the source file and destination folder exist and the
        # destination file doesn't yet exist
        assert os.path.isfile(srcfile)
        assert os.path.isdir(dstpath)
        assert not os.path.exists(dstfile)

        # Check if mackeep can link it and the link points to the correct place
        utils.link(srcfile, dstfile)
        assert os.path.isfile(srcfile)
        assert os.path.isdir(dstpath)
        assert os.path.exists(dstfile)
        assert os.readlink(dstfile) == srcfile

        # Let's clean up
        utils.delete(srcfile)
        utils.delete(dstpath)

    def test_chmod_file(self):
        # Create a tmp file
        with tempfile.NamedTemporaryFile(delete=False) as tfile:
            file_name = tfile.name

        # Create a tmp directory with a sub folder
        dir_name = tempfile.mkdtemp()
        nested_dir = tempfile.mkdtemp(dir=dir_name)

        # # File Tests

        # Change the tmp file stats to S_IWRITE (200), write access only
        os.chmod(file_name, stat.S_IWRITE)
        assert convert_to_octal(file_name) == "200"

        # Check to make sure that utils.chmod changes the bits to 600,
        # which is read and write access for the owner
        utils.chmod(file_name)
        assert convert_to_octal(file_name) == "600"

        # # Directory Tests

        # Change the tmp folder stats to S_IREAD (400), read access only
        os.chmod(dir_name, stat.S_IREAD)
        assert convert_to_octal(dir_name) == "400"

        # Check to make sure that utils.chmod changes the bits of all
        # directories to 700, which is read, write, and execute access for the
        # owner
        utils.chmod(dir_name)
        assert convert_to_octal(dir_name) == "700"
        assert convert_to_octal(nested_dir) == "700"

        # Use an "unsupported file type". In this case, /dev/null
        with pytest.raises(ValueError, match="Unsupported file type"):
            utils.chmod(os.devnull)

        # # Orphaned symlink test

        # An orphaned symlink (e.g. a link restored before its target) is
        # listed by os.walk but can't be followed by os.chmod. utils.chmod
        # must skip it instead of crashing with FileNotFoundError.
        link_target = os.path.join(nested_dir, "orphaned_target")
        link_name = os.path.join(dir_name, "orphaned_link")
        os.symlink(link_target, link_name)
        assert not os.path.exists(link_target)
        assert os.path.islink(link_name)

        # This used to raise FileNotFoundError
        utils.chmod(dir_name)

        # # Let's clean up
        utils.delete(file_name)
        utils.delete(dir_name)

    def test_error(self):
        test_string = "Hello World"
        with pytest.raises(SystemExit):
            utils.error(test_string)

    def test_failed_backup_location(self):
        """
        Tests for the error that should occur if the backup folder cannot be
        found for Dropbox and Google
        """
        with (
            tempfile.TemporaryDirectory() as temp_home,
            patch.dict(
                os.environ,
                {"HOME": temp_home},
            ),
        ):
            # Check for the missing Dropbox folder
            assert not os.path.exists(os.path.join(temp_home, ".dropbox/host.db"))
            with pytest.raises(SystemExit):
                utils.get_dropbox_folder_location()

            # Check for the missing Google Drive folder
            assert not os.path.exists(
                os.path.join(
                    temp_home,
                    "Library/Application Support/Google/Drive/sync_config.db",
                ),
            )
            with pytest.raises(SystemExit):
                utils.get_google_drive_folder_location()

    def test_dropbox_folder_location_with_malformed_host_db(self):
        """Malformed Dropbox host.db should fail with a user-facing error."""
        with (
            tempfile.TemporaryDirectory() as temp_home,
            patch.dict(
                os.environ,
                {"HOME": temp_home},
            ),
        ):
            host_db_path = os.path.join(temp_home, ".dropbox", "host.db")
            os.makedirs(os.path.dirname(host_db_path), exist_ok=True)
            with open(host_db_path, "w") as f:
                f.write("malformed-content-without-base64-path")

            with pytest.raises(SystemExit):
                utils.get_dropbox_folder_location()

    def test_dropbox_folder_location_with_invalid_base64(self):
        """Invalid base64 in Dropbox host.db should fail with a user-facing error."""
        with (
            tempfile.TemporaryDirectory() as temp_home,
            patch.dict(
                os.environ,
                {"HOME": temp_home},
            ),
        ):
            host_db_path = os.path.join(temp_home, ".dropbox", "host.db")
            os.makedirs(os.path.dirname(host_db_path), exist_ok=True)
            with open(host_db_path, "w") as f:
                f.write("first-field invalid-base64-!@#$")

            with pytest.raises(SystemExit):
                utils.get_dropbox_folder_location()

    def test_google_drive_folder_location_with_missing_path_entry(self):
        """Google Drive DB without local_sync_root_path should fail cleanly."""
        with (
            tempfile.TemporaryDirectory() as temp_home,
            patch.dict(
                os.environ,
                {"HOME": temp_home},
            ),
        ):
            gdrive_db = os.path.join(
                temp_home,
                "Library/Application Support/Google/Drive/sync_config.db",
            )
            os.makedirs(os.path.dirname(gdrive_db), exist_ok=True)

            con = sqlite3.connect(gdrive_db)
            cur = con.cursor()
            cur.execute("CREATE TABLE data (entry_key TEXT, data_value TEXT)")
            cur.execute(
                "INSERT INTO data (entry_key, data_value) VALUES (?, ?)",
                ("another_key", "/tmp/whatever"),
            )
            con.commit()
            con.close()

            with pytest.raises(SystemExit):
                utils.get_google_drive_folder_location()

    def test_google_drive_folder_location_uses_user_default_db(self):
        """Read Google Drive location from user_default sync DB when present."""
        with (
            tempfile.TemporaryDirectory() as temp_home,
            patch.dict(
                os.environ,
                {"HOME": temp_home},
            ),
        ):
            gdrive_db = os.path.join(
                temp_home,
                "Library/Application Support/Google/Drive/user_default/sync_config.db",
            )
            os.makedirs(os.path.dirname(gdrive_db), exist_ok=True)

            expected_path = os.path.join(temp_home, "Google Drive")
            con = sqlite3.connect(gdrive_db)
            cur = con.cursor()
            cur.execute("CREATE TABLE data (entry_key TEXT, data_value TEXT)")
            cur.execute(
                "INSERT INTO data (entry_key, data_value) VALUES (?, ?)",
                ("local_sync_root_path", expected_path),
            )
            con.commit()
            con.close()

            assert utils.get_google_drive_folder_location() == expected_path

    def test_is_process_running(self):
        with patch.object(utils.os.path, "isfile", return_value=True):
            with patch.object(utils.subprocess, "call", return_value=0):
                assert utils.is_process_running("application")
            with patch.object(utils.subprocess, "call", return_value=1):
                assert not utils.is_process_running("application")
            with patch.object(utils.subprocess, "call", return_value=2):
                assert not utils.is_process_running("application")

    def test_can_file_be_synced_on_current_platform(self):
        # Any file path will do, even if it doesn't exist
        path = "some/file"

        # Force the Mac OSX Test using mock
        with patch.object(
            utils.platform,
            "system",
            return_value=utils.constants.PLATFORM_DARWIN,
        ):
            assert utils.can_file_be_synced_on_current_platform(path)

        # Force the Linux Test using mock
        with patch.object(
            utils.platform,
            "system",
            return_value=utils.constants.PLATFORM_LINUX,
        ):
            assert utils.can_file_be_synced_on_current_platform(path)

            # Try to use the library path on Linux, which shouldn't work
            path = os.path.join(os.environ["HOME"], "Library/")
            assert not utils.can_file_be_synced_on_current_platform(path)
