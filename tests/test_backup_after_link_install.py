"""Test the edge case: running backup after link install."""
import os
import shutil
import sys
import tempfile
import unittest
from io import StringIO
from unittest.mock import Mock

from mackeep.application import ApplicationProfile
from mackeep.mackeep import Mackeep


class TestBackupAfterLinkInstall(unittest.TestCase):
    """Integration test for backup after link install edge case."""

    def setUp(self):
        """Set up test fixtures."""
        # Create a mock Mackeep instance
        self.mock_mackeep = Mock(spec=Mackeep)
        self.mock_mackeep.mackeep_folder = tempfile.mkdtemp()

        # Register cleanup for mackeep folder
        self.addCleanup(self._cleanup_directory, self.mock_mackeep.mackeep_folder)

        # Create a temporary home directory
        self.temp_home = tempfile.mkdtemp()

        # Register cleanup for temp home
        self.addCleanup(self._cleanup_directory, self.temp_home)

        # Save original HOME and set it to temp directory
        self.original_home = os.environ.get("HOME")
        os.environ["HOME"] = self.temp_home

        # Register cleanup for HOME restoration
        self.addCleanup(self._restore_home, self.original_home)

    def _cleanup_directory(self, directory):
        """Safely clean up a directory."""
        if os.path.exists(directory):
            shutil.rmtree(directory)

    def _restore_home(self, original_home):
        """Restore the original HOME environment variable."""
        if original_home is not None:
            os.environ["HOME"] = original_home
        elif "HOME" in os.environ:
            del os.environ["HOME"]

    def tearDown(self):
        """Clean up test fixtures."""
        # Cleanup is now handled by addCleanup, which runs even if test fails

    def test_backup_after_link_install_does_not_delete_mackeep_files(self):
        """
        Test the complete scenario:
        1. Run link install (moves files to mackeep and creates symlinks)
        2. Run backup (should skip already linked files)
        This prevents mackeep from trying to delete files in the backup folder.
        """
        # Define test files for this test
        test_files = {".testfile", ".testdir"}

        # Step 1: Simulate initial state - files exist in home
        home_file = os.path.join(self.temp_home, ".testfile")
        home_dir = os.path.join(self.temp_home, ".testdir")

        # Create initial files
        with open(home_file, "w") as f:
            f.write("original file content")
        os.makedirs(home_dir)
        with open(os.path.join(home_dir, "subfile.txt"), "w") as f:
            f.write("original dir content")

        # Step 2: Run link install
        app_profile = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=test_files,
            dry_run=False,
            verbose=False,
        )

        captured_output = StringIO()
        sys.stdout = captured_output
        app_profile.link_install()
        sys.stdout = sys.__stdout__

        # Verify link install worked correctly
        mackeep_file = os.path.join(self.mock_mackeep.mackeep_folder, ".testfile")
        mackeep_dir = os.path.join(self.mock_mackeep.mackeep_folder, ".testdir")

        # Files should exist in mackeep folder
        assert os.path.exists(mackeep_file)
        assert os.path.exists(mackeep_dir)

        # Home should have symlinks pointing to mackeep
        assert os.path.islink(home_file)
        assert os.path.islink(home_dir)
        assert os.path.samefile(home_file, mackeep_file)
        assert os.path.samefile(home_dir, mackeep_dir)

        # Verify content is preserved
        with open(mackeep_file) as f:
            assert f.read() == "original file content"
        with open(os.path.join(mackeep_dir, "subfile.txt")) as f:
            assert f.read() == "original dir content"

        # Step 3: Run backup (this is where the edge case would occur)
        captured_output = StringIO()
        sys.stdout = captured_output
        app_profile.copy_files_to_mackeep_folder()
        output = captured_output.getvalue()
        sys.stdout = sys.__stdout__

        # Verify backup skipped the already linked files
        # Should not print "Backing up" for these files
        assert "Backing up" not in output

        # Verify the mackeep files still exist and weren't deleted
        assert os.path.exists(mackeep_file)
        assert os.path.exists(mackeep_dir)

        # Verify content is still intact
        with open(mackeep_file) as f:
            assert f.read() == "original file content"
        with open(os.path.join(mackeep_dir, "subfile.txt")) as f:
            assert f.read() == "original dir content"

        # Verify symlinks are still in place
        assert os.path.islink(home_file)
        assert os.path.islink(home_dir)
        assert os.path.samefile(home_file, mackeep_file)
        assert os.path.samefile(home_dir, mackeep_dir)

    def test_backup_after_link_install_verbose_shows_skip_message(self):
        """Test that verbose mode shows skip messages for already linked files."""
        # Define test file for this test
        test_files = {".testfile"}

        # Create initial file
        home_file = os.path.join(self.temp_home, ".testfile")

        with open(home_file, "w") as f:
            f.write("test content")

        # Run link install
        app_profile = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=test_files,
            dry_run=False,
            verbose=False,
        )
        app_profile.link_install()

        # Run backup in verbose mode
        app_profile_verbose = ApplicationProfile(
            mackeep=self.mock_mackeep,
            files=test_files,
            dry_run=False,
            verbose=True,
        )

        captured_output = StringIO()
        sys.stdout = captured_output
        app_profile_verbose.copy_files_to_mackeep_folder()
        output = captured_output.getvalue()
        sys.stdout = sys.__stdout__

        # Verify skip message is shown
        assert "Skipping" in output
        assert "already linked to" in output
        assert home_file in output


if __name__ == "__main__":
    unittest.main()
