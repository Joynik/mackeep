import contextlib
import os
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from mackeep.application import ApplicationProfile
from mackeep.mackeep import Mackeep


class TestApplicationProfile(unittest.TestCase):
    def setUp(self):
        """Set up test fixtures."""
        self.mock_mackeep = Mock(spec=Mackeep)
        self.mock_mackeep.mackeep_folder = self.enterContext(
            tempfile.TemporaryDirectory(),
        )
        self.temp_home = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(patch.dict(os.environ, {
            "HOME": self.temp_home,
            "XDG_CONFIG_HOME": str(Path(self.temp_home) / ".config"),
        }))

        # Define test files
        self.test_files = {".testfile", ".testfolder"}

        # Create the ApplicationProfile instance
        self.app_profile = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=self.test_files,
            dry_run=False,
            verbose=False,
        )

    def test_files_are_sorted_for_deterministic_processing(self):
        """Application files should always be processed in sorted order."""
        unsorted_files = {"z-last", "a-first", "m-middle"}
        app_profile = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=unsorted_files,
            dry_run=False,
            verbose=False,
        )
        assert app_profile.files == ["a-first", "m-middle", "z-last"]

    def test_copy_files_to_mackeep_folder_dry_run_no_permission_error(self):
        """Test dry_run mode doesn't trigger PermissionError in backup."""
        # Create a dry_run ApplicationProfile
        app_profile_dry = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=self.test_files,
            dry_run=True,
            verbose=False,
        )

        # Create a test file in the home directory
        test_file = ".testfile"
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the actual file
        with open(home_filepath, "w") as f:
            f.write("test content")

        # Patch utils.copy - it should NOT be called in dry_run mode
        with patch("mackeep.application.utils.copy") as mock_copy:
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                app_profile_dry.copy_files_to_mackeep_folder()


            # Verify that copy was NOT called (dry_run mode)
            mock_copy.assert_not_called()

            # Verify that the backing up message was printed
            output = captured_output.getvalue()
            assert "Backing up" in output

    def test_copy_files_from_mackeep_folder_dry_run_no_permission_error(self):
        """Test dry_run mode doesn't trigger PermissionError in restore."""
        # Create a dry_run ApplicationProfile
        app_profile_dry = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=self.test_files,
            dry_run=True,
            verbose=False,
        )

        # Create a test file in the mackeep directory
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)

        # Create the actual file
        with open(mackeep_filepath, "w") as f:
            f.write("test content")

        # Patch utils.copy - it should NOT be called in dry_run mode
        with patch("mackeep.application.utils.copy") as mock_copy:
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                app_profile_dry.copy_files_from_mackeep_folder()


            # Verify that copy was NOT called (dry_run mode)
            mock_copy.assert_not_called()

            # Verify that the recovering message was printed
            output = captured_output.getvalue()
            assert "Recovering" in output

    def test_copy_files_to_mackeep_folder_decline_replace_skips_copy(self):
        """Test backup does not overwrite when user declines replacement."""
        test_file = ".testfile"
        home_filepath = os.path.join(self.temp_home, test_file)
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)

        with open(home_filepath, "w") as f:
            f.write("home content")
        with open(mackeep_filepath, "w") as f:
            f.write("existing backup")

        with (
            patch("mackeep.application.utils.confirm", return_value=False),
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            self.app_profile.copy_files_to_mackeep_folder()

            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

        with open(mackeep_filepath) as f:
            assert f.read() == "existing backup"

    def test_copy_files_from_mackeep_folder_decline_replace_skips_copy(self):
        """Test restore does not overwrite when user declines replacement."""
        test_file = ".testfile"
        home_filepath = os.path.join(self.temp_home, test_file)
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)

        with open(home_filepath, "w") as f:
            f.write("existing home")
        with open(mackeep_filepath, "w") as f:
            f.write("backup content")

        with (
            patch("mackeep.application.utils.confirm", return_value=False),
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            self.app_profile.copy_files_from_mackeep_folder()

            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

        with open(home_filepath) as f:
            assert f.read() == "existing home"

    def test_link_uninstall_mackeep_not_a_link(self):
        """Test link_uninstall skips when home file is not a symbolic link."""
        # Create a test file in the mackeep directory (regular file, not a link)
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the mackeep file as a regular file
        with open(mackeep_filepath, "w") as f:
            f.write("mackeep content")

        # Create the home file as a regular file (not a link)
        with open(home_filepath, "w") as f:
            f.write("home content")

        # Patch utils.delete and utils.copy
        with (
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                self.app_profile.link_uninstall()


            # Verify that delete and copy were NOT called
            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

            # Verify that the warning message was printed
            output = captured_output.getvalue()
            assert "Warning: the file in your home" in output
            assert "does not point to the original file" in output
            assert mackeep_filepath in output
            assert home_filepath in output
            assert "skipping" in output

    def test_link_uninstall_mackeep_points_to_wrong_target(self):
        """Test link_uninstall skips when home link points to wrong target."""
        # Create a test file
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the mackeep file
        with open(mackeep_filepath, "w") as f:
            f.write("mackeep content")

        # Create a different target file
        wrong_target = os.path.join(self.temp_home, ".wrongtarget")
        with open(wrong_target, "w") as f:
            f.write("wrong target content")

        # Create the home file as a symbolic link pointing to the wrong target
        os.symlink(wrong_target, home_filepath)

        # Patch utils.delete and utils.copy
        with (
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                self.app_profile.link_uninstall()


            # Verify that delete and copy were NOT called
            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

            # Verify that the warning message was printed
            output = captured_output.getvalue()
            assert "Warning: the file in your home" in output
            assert "does not point to the original file" in output
            assert mackeep_filepath in output
            assert home_filepath in output
            assert "skipping" in output

    def test_link_uninstall_mackeep_points_correctly(self):
        """Test link_uninstall proceeds when home link points to mackeep file."""
        # Create a test file
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the mackeep file first
        with open(mackeep_filepath, "w") as f:
            f.write("mackeep content")

        # Create the home file as a symbolic link pointing to the mackeep file
        os.symlink(mackeep_filepath, home_filepath)

        self.app_profile.link_uninstall()
        assert not os.path.islink(home_filepath)
        with open(home_filepath) as restored:
            assert restored.read() == "mackeep content"
        with open(mackeep_filepath) as backup:
            assert backup.read() == "mackeep content"

    def test_copy_files_to_mackeep_folder_skips_already_linked_files(self):
        """Test that backup skips files already linked from link install."""
        # Create a test file
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the mackeep file first (simulating link install)
        with open(mackeep_filepath, "w") as f:
            f.write("mackeep content")

        # Create the home file as a symbolic link pointing to the mackeep file
        # (simulating what link install does)
        os.symlink(mackeep_filepath, home_filepath)

        # Patch utils.delete and utils.copy
        with (
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                self.app_profile.copy_files_to_mackeep_folder()


            # Verify that delete and copy were NOT called (should skip)
            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

            # Verify that the skipping message was NOT printed (non-verbose)
            output = captured_output.getvalue()
            assert "Backing up" not in output

        # Verify the symlink still exists and points to mackeep file
        assert os.path.islink(home_filepath)
        assert os.path.samefile(home_filepath, mackeep_filepath)

        # Verify the mackeep file still exists with original content
        assert os.path.exists(mackeep_filepath)
        with open(mackeep_filepath) as f:
            assert f.read() == "mackeep content"

    def test_copy_files_to_mackeep_folder_skips_already_linked_files_verbose(self):
        """Test backup skips files already linked with verbose mode."""
        # Create a verbose ApplicationProfile
        app_profile_verbose = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=self.test_files,
            dry_run=False,
            verbose=True,
        )

        # Create a test file
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create the mackeep file first (simulating link install)
        with open(mackeep_filepath, "w") as f:
            f.write("mackeep content")

        # Create the home file as a symbolic link pointing to the mackeep file
        # (simulating what link install does)
        os.symlink(mackeep_filepath, home_filepath)

        # Patch utils.delete and utils.copy
        with (
            patch("mackeep.application.utils.delete") as mock_delete,
            patch("mackeep.application.utils.copy") as mock_copy,
        ):
            # Capture stdout
            captured_output = StringIO()
            with contextlib.redirect_stdout(captured_output):
                # Call the method
                app_profile_verbose.copy_files_to_mackeep_folder()


            # Verify that delete and copy were NOT called (should skip)
            mock_delete.assert_not_called()
            mock_copy.assert_not_called()

            # Verify that the skipping message WAS printed (verbose mode)
            output = captured_output.getvalue()
            assert "Skipping" in output
            assert "already linked to" in output
            assert home_filepath in output
            assert mackeep_filepath in output

        # Verify the symlink still exists and points to mackeep file
        assert os.path.islink(home_filepath)
        assert os.path.samefile(home_filepath, mackeep_filepath)

        # Verify the mackeep file still exists with original content
        assert os.path.exists(mackeep_filepath)
        with open(mackeep_filepath) as f:
            assert f.read() == "mackeep content"

    def test_copy_files_to_mackeep_folder_backs_up_symlink_to_different_location(self):
        """Test that backup works for symlinks pointing elsewhere."""
        # Create a test file
        test_file = ".testfile"
        mackeep_filepath = os.path.join(self.mock_mackeep.mackeep_folder, test_file)
        home_filepath = os.path.join(self.temp_home, test_file)

        # Create a different target file (not in mackeep folder)
        other_target = os.path.join(self.temp_home, ".otherlocation")
        with open(other_target, "w") as f:
            f.write("other content")

        # Create the home file as a symbolic link pointing to different location
        os.symlink(other_target, home_filepath)

        self.app_profile.copy_files_to_mackeep_folder()
        with open(mackeep_filepath) as backup:
            assert backup.read() == "other content"
        assert not os.path.islink(mackeep_filepath)


if __name__ == "__main__":
    unittest.main()


@pytest.mark.parametrize("operation", ["backup", "restore"])
@pytest.mark.parametrize("directory", [False, True])
@pytest.mark.parametrize("verbose", [False, True])
def test_copy_permission_failure_preserves_both_versions(
    home,
    capsys,
    operation,
    directory,
    verbose,
):
    """An injected copy failure must report failure and keep both original trees."""
    (home / ".mackeep.cfg").write_text(
        f"[storage]\nengine = file_system\npath = {home / 'storage'}\n",
    )
    mackeep = Mackeep(read_only=True)
    backup = Path(mackeep.mackeep_folder)
    backup.mkdir()
    for root, content in ((home, b"local"), (backup, b"backup")):
        target = root / "app"
        if directory:
            target.mkdir()
            target /= "settings"
        target.write_bytes(content)
    profile = ApplicationProfile(mackeep, {"app"}, False, verbose)
    method = (
        profile.copy_files_to_mackeep_folder
        if operation == "backup"
        else profile.copy_files_from_mackeep_folder
    )
    with patch("mackeep.application.utils.copy", side_effect=PermissionError("denied")):
        method()
    assert profile.failed
    for root, content in ((home, b"local"), (backup, b"backup")):
        target = root / ("app/settings" if directory else "app")
        assert target.read_bytes() == content
        assert (root / "app").is_dir() is directory
    output = capsys.readouterr().out
    assert "Error: Unable to copy file" in output
    assert "permission issue" in output
    if verbose:
        assert ("Backing up" if operation == "backup" else "Recovering") in output
