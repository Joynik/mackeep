"""Tests for the exclusion rules applied to the backup and restore flows."""

import os
from unittest.mock import patch

import pytest

from mackup import utils
from mackup.main import main


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Set up a temporary home directory with a Mackup config file."""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / ".config"))
    monkeypatch.delenv("MACKUP_CONFIG", raising=False)

    utils.FORCE_YES = True
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = True

    yield tmp_path

    utils.FORCE_YES = False
    utils.FORCE_NO = False
    utils.CAN_RUN_AS_ROOT = False


def write_mackup_config(home, extra=""):
    """Write a Mackup config file using the file system storage engine."""
    storage = home / "storage"
    storage.mkdir(exist_ok=True)
    config = home / ".mackup.cfg"
    config.write_text(
        "[storage]\n"
        "engine = file_system\n"
        f"path = {storage}\n"
        "directory = Mackup\n"
        "\n"
        "[applications_to_sync]\n"
        "test-app\n" + extra,
    )
    return storage


def write_app_config(home, body):
    """Write a custom application config file."""
    apps_dir = home / ".mackup"
    apps_dir.mkdir(exist_ok=True)
    (apps_dir / "test-app.cfg").write_text(body)


def run(*args):
    """Run the Mackup command line with the given arguments."""
    with patch("sys.argv", ["mackup", *args]):
        main()


def test_backup_skips_the_excluded_files(home, capsys):
    """The excluded files of a folder are not backed up."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")
    (testdir / "skip.log").write_text("skip")

    run("backup")

    backup = home / "storage" / "Mackup" / ".testdir"
    assert (backup / "keep.txt").exists()
    assert not (backup / "skip.log").exists()
    assert "skip.log" not in capsys.readouterr().out.split("Backing up")[0]


def test_backup_skips_an_excluded_folder(home):
    """An excluded folder is not backed up at all."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")

    run("backup")

    assert not (home / "storage" / "Mackup" / ".testdir").exists()


def test_backup_skips_an_excluded_file_entry(home):
    """A file entry that is excluded is not backed up."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n"
        "app.log\n"
        "\n"
        "[exclude]\n"
        "*.log\n",
    )

    (home / ".testrc").write_text("config")
    (home / "app.log").write_text("log")

    run("backup")

    backup = home / "storage" / "Mackup"
    assert (backup / ".testrc").exists()
    assert not (backup / "app.log").exists()


def test_backup_skips_an_excluded_directory_content(home):
    """The excluded directories are not walked."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/cache\n",
    )

    testdir = home / ".testdir"
    (testdir / "cache").mkdir(parents=True)
    (testdir / "cache" / "big.bin").write_text("big")
    (testdir / "keep.txt").write_text("keep")

    run("backup")

    backup = home / "storage" / "Mackup" / ".testdir"
    assert (backup / "keep.txt").exists()
    assert not (backup / "cache").exists()


def test_the_global_exclude_applies_to_every_application(home):
    """The [exclude] section of the Mackup config applies to every app."""
    write_mackup_config(home, extra="\n[exclude]\n.testdir/.DS_Store\n")
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / ".DS_Store").write_text("junk")
    (testdir / "keep.txt").write_text("keep")

    run("backup")

    backup = home / "storage" / "Mackup" / ".testdir"
    assert (backup / "keep.txt").exists()
    assert not (backup / ".DS_Store").exists()


def test_the_xdg_exclude_applies_to_the_xdg_files(home):
    """The [xdg_exclude] section applies to the XDG config files."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[xdg_configuration_files]\n"
        "test-app/config\n"
        "\n"
        "[xdg_exclude]\n"
        "test-app/cache\n",
    )

    xdg = home / ".config" / "test-app"
    (xdg / "cache").mkdir(parents=True)
    (xdg / "cache" / "data.bin").write_text("data")
    (xdg / "config").write_text("config")

    run("backup")

    backup = home / "storage" / "Mackup" / ".config" / "test-app"
    assert (backup / "config").exists()
    assert not (backup / "cache").exists()


def test_restore_skips_the_excluded_files(home):
    """The excluded files of the backup are not restored."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )

    backup = home / "storage" / "Mackup" / ".testdir"
    backup.mkdir(parents=True)
    (backup / "keep.txt").write_text("keep")
    (backup / "skip.log").write_text("skip")

    run("restore")

    assert (home / ".testdir" / "keep.txt").exists()
    assert not (home / ".testdir" / "skip.log").exists()


def test_restore_skips_an_excluded_entry(home):
    """An excluded entry is not restored."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir\n",
    )

    backup = home / "storage" / "Mackup" / ".testdir"
    backup.mkdir(parents=True)
    (backup / "keep.txt").write_text("keep")

    run("restore")

    assert not (home / ".testdir").exists()


def test_the_dry_run_reports_the_stale_files_of_the_backup(home, capsys):
    """The files of the backup that are now excluded are reported."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")

    # A file that was backed up before the exclusion was added
    backup = home / "storage" / "Mackup" / ".testdir"
    backup.mkdir(parents=True)
    (backup / "skip.log").write_text("stale")

    run("backup", "--dry-run")

    out = capsys.readouterr().out
    assert "skip.log" in out
    # The stale file is not deleted
    assert (backup / "skip.log").exists()


def test_link_install_skips_a_folder_with_excluded_files(home, capsys):
    """A symlink cannot exclude anything, so the entry is skipped."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n"
        "\n"
        "[exclude]\n"
        ".testdir/skip.log\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "skip.log").write_text("skip")
    (testdir / "keep.txt").write_text("keep")

    run("link", "install")

    out = capsys.readouterr().out
    assert "Skipping .testdir" in out
    assert not os.path.islink(home / ".testdir")
    assert not (home / "storage" / "Mackup" / ".testdir").exists()


def test_link_install_links_a_folder_without_exclusions(home):
    """The entries that are not impacted by the exclusions are linked."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")

    run("link", "install")

    assert os.path.islink(home / ".testdir")
    assert (home / "storage" / "Mackup" / ".testdir" / "keep.txt").exists()


def test_link_install_skips_an_excluded_entry(home, capsys):
    """An excluded entry is not linked."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testrc\n"
        "\n"
        "[exclude]\n"
        ".testrc\n",
    )

    (home / ".testrc").write_text("config")

    run("link", "install")

    out = capsys.readouterr().out
    assert "Skipping .testrc" in out
    assert not os.path.islink(home / ".testrc")


def test_an_app_without_exclusion_is_not_impacted(home):
    """The apps that do not use the exclusions work as before."""
    write_mackup_config(home)
    write_app_config(
        home,
        "[application]\n"
        "name = Test App\n"
        "\n"
        "[configuration_files]\n"
        ".testdir\n",
    )

    testdir = home / ".testdir"
    testdir.mkdir()
    (testdir / "keep.txt").write_text("keep")
    (testdir / "skip.log").write_text("skip")

    run("backup")

    backup = home / "storage" / "Mackup" / ".testdir"
    assert (backup / "keep.txt").exists()
    assert (backup / "skip.log").exists()
