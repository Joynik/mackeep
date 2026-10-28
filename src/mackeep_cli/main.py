"""Mackeep.

Keep your application settings in sync.

Copyright (C) 2013-2025 Laurent Raufaste <http://glop.org/>

Usage:
  mackeep-cli [options] list
  mackeep-cli [options] show <application>
  mackeep-cli [options] config
  mackeep-cli [options] migrate
  mackeep-cli [options] library check
  mackeep-cli [options] library update [<application>]
  mackeep-cli [options] library remove <application>
  mackeep-cli [options] backup [<application>]
  mackeep-cli [options] restore [<application>]
  mackeep-cli [options] link install [<application>]
  mackeep-cli [options] link uninstall [<application>]
  mackeep-cli [options] link [<application>]
  mackeep-cli (-h | --help)

Options:
  -h --help                 Show this screen.
  -f --force                Force every question asked to be answered with "Yes".
  --force-no                Force every question asked to be answered with "No".
  -r --root                 Allow mackeep to be run as superuser.
  -n --dry-run              Show steps without executing.
  --verbose                 Show additional details.
  --summary                 Show a compact backup result instead of progress.
  -c --config-file=<path>   Specify custom config file path.
  --json                    Output machine-readable JSON.
  --detail=<level>          Detail level of the dry-run: entries or files.
  --max-actions=<n>         Maximum number of actions of the JSON dry-run.
  -v -V --version           Show version.

Modes of action:
 - mackeep-cli list: display a list of all supported applications.
 - mackeep-cli show: display the details for a supported application.
 - mackeep-cli config: display the configuration of Mackeep.
 - mackeep-cli migrate: copy legacy configuration files to their new location.
 - mackeep-cli backup: copy local config files in the configured remote folder.
 - mackeep-cli restore: copy config files from the configured remote folder locally.
 - mackeep-cli link install: moves local config files in remote folder, and links.
 - mackeep-cli link uninstall: removes the links and copy config files locally.
 - mackeep-cli link: links local config files from the remote folder.

backup, restore, link install, link uninstall and link act on every configured
application by default. Name a single application (e.g. `mackeep-cli backup vim`) to
limit a command to that app, overriding the applications_to_sync and
applications_to_ignore settings in your config. Backup replaces the selected
snapshots without confirmation. Restore requires confirmation or --force.
The --force-no option preserves existing data and exits nonzero if replacement
is declined.

Choose a storage engine and path in .mackeep.cfg or in the desktop settings
before the first backup. A new configuration does not select storage automatically.

The --json option writes a machine-readable answer, meant to be used by
graphical front-ends. In this mode, only JSON is written to stdout, the
human-readable output is written to stderr and no question is asked.

The --detail option tells how detailed the dry-run is: "entries" (the
default) describes the top level entries, "files" describes every file.

Desktop application (macOS 15 or newer, Apple Silicon):
 Mackeep provides a native interface for choosing applications, editing file and
 folder rules, managing exclusions, previewing backup/restore, and viewing history.
 It uses this CLI and the same .mackeep.cfg and .mackeep/ definitions.
 Install the desktop application with: brew install joynik/tap/mackeep
 Install the required CLI separately: brew install joynik/tap/mackeep-cli
 Disk images (.dmg) are also available at:
 https://github.com/Joynik/mackeep/releases/latest
 Desktop guide: https://github.com/Joynik/mackeep/tree/master/desktop#readme

See https://github.com/Joynik/mackeep/tree/master/doc for more information.

"""

# Mackeep is a fork of Mackup, written by Laurent Raufaste.

import os
import re
import signal
import sys
import traceback
from contextlib import redirect_stdout
from dataclasses import dataclass
from typing import Any, TextIO

from docopt import docopt

from mackeep import jsonapi, library, utils
from mackeep.application import ApplicationProfile, Reporter
from mackeep.appsdb import ApplicationsDatabase
from mackeep.backupstate import BackupState
from mackeep.config import ConfigError
from mackeep.constants import (
    MACKEEP_APP_NAME,
    VERSION,
)
from mackeep.excludes import Matcher, Rule
from mackeep.locking import storage_lock
from mackeep.mackeep import Mackeep
from mackeep.migrate import plan as migration_plan
from mackeep.migrate import run as run_migration
from mackeep_cli.summary import BackupSummary, SummaryOutput

# The ANSI escape codes used to color the error messages
ANSI_CODES = re.compile(r"\033\[[0-9;]*m")

# The default maximum number of actions of the JSON dry-run
DEFAULT_MAX_ACTIONS: int = 5000
CANCELLED_EXIT_CODE = 130

# SIGUSR1 requests a stop between application transactions, never inside one.
_cancel_requested = False


def _request_cancel(_signum: int, _frame: object) -> None:
    """Request cancellation at the next application boundary."""
    global _cancel_requested  # noqa: PLW0603 - signal handler state
    _cancel_requested = True


class _UnsupportedApplicationError(ConfigError):
    """A requested application is missing from the loaded catalog."""

    code = "unsupported_application"


class ColorFormatCodes:
    BLUE = "\033[34m"
    BOLD = "\033[1m"
    NORMAL = "\033[0m"


def header(text: str) -> str:
    return ColorFormatCodes.BLUE + text + ColorFormatCodes.NORMAL


def bold(text: str) -> str:
    return ColorFormatCodes.BOLD + text + ColorFormatCodes.NORMAL


@dataclass
class _Context:
    """Shared state threaded through the command handlers."""

    config_file: str | None
    mckp: Mackeep
    app_db: ApplicationsDatabase
    dry_run: bool
    verbose: bool
    reporter: Reporter | None = None
    detail: str = "entries"
    max_actions: int = 5000
    replace_backup: bool = True


def _print_app_header(app_name: str, verbose: bool) -> None:
    if verbose:
        header_str = header("---")
        print(f"\n{header_str} {bold(app_name)} {header_str}")


def _make_profile(ctx: _Context, app_name: str) -> ApplicationProfile:
    """Create the profile of an application, with its exclusion rules."""
    app: ApplicationProfile = ApplicationProfile(
        ctx.mckp,
        ctx.app_db.get_files(app_name),
        ctx.dry_run,
        ctx.verbose,
    )
    app.replace_backup = ctx.replace_backup
    config_file: str = ctx.mckp.config.config_path
    app_file: str = ctx.app_db.get_config_file(app_name)
    app.configure(
        exclude=Matcher(
            [
                *[
                    Rule(pattern, "exclude", config_file)
                    for pattern in ctx.mckp.config.global_exclude
                ],
                *[
                    Rule(pattern, "exclude", app_file)
                    for pattern in ctx.app_db.get_exclude(app_name)
                ],
            ],
        ),
        xdg_exclude=Matcher(
            [
                *[
                    Rule(pattern, "xdg_exclude", config_file)
                    for pattern in ctx.mckp.config.global_xdg_exclude
                ],
                *[
                    Rule(pattern, "xdg_exclude", app_file)
                    for pattern in ctx.app_db.get_xdg_exclude(app_name)
                ],
            ],
        ),
        reporter=ctx.reporter,
        app_name=app_name,
        detail=ctx.detail,
    )
    return app


def _resolve_apps(app_name: str | None, ctx: _Context) -> set[str]:
    """Resolve which apps a per-app command should act on.

    If an application is named, error out when it is not a supported app
    (like the `show` command) and otherwise act on exactly that app,
    overriding the config's applications_to_sync / applications_to_ignore
    lists. If no application is named, fall back to every configured
    application.
    """
    if app_name:
        if app_name not in ctx.app_db.get_app_names():
            raise _UnsupportedApplicationError(f"Unsupported application: {app_name}")
        return {app_name}
    names = ctx.mckp.get_apps_to_backup(ctx.app_db)
    unknown = names - ctx.app_db.get_app_names()
    if unknown:
        raise _UnsupportedApplicationError(
            f"Unsupported application: {', '.join(sorted(unknown))}",
        )
    return names


def _preflight(
    ctx: _Context,
    app_names: set[str],
    action: str,
) -> list[tuple[str, ApplicationProfile]]:
    """Validate every selected entry before initialization or mutation."""
    if not ctx.mckp.config.path:
        utils.error(
            "Storage is not configured. Choose a storage engine and path first.",
        )
    profiles = [(name, _make_profile(ctx, name)) for name in sorted(app_names)]
    for name, profile in profiles:
        problem = ctx.app_db.get_error(name)
        if problem and name in ctx.app_db.unsafe_paths:
            raise ConfigError(problem)
        profile.preflight(action)
    return profiles


def _ownership_baseline(ctx: _Context, selected: set[str]) -> dict[str, list[str]]:
    """Infer current shared owners once when upgrading an unindexed backup."""
    configured = ctx.mckp.config.apps_to_sync | ctx.mckp.config.apps_to_ignore
    names = selected | configured
    baseline: dict[str, list[str]] = {}
    root = ctx.mckp.mackeep_folder
    for name in sorted(names & ctx.app_db.get_app_names()):
        profile = _make_profile(ctx, name)
        entries: set[str] = set()
        for filename in profile.files:
            try:
                _, backup = profile.get_filepaths(filename)
            except ConfigError:
                continue
            if not os.path.lexists(backup):
                continue
            if name in selected:
                leaves = profile._inventory(backup)  # noqa: SLF001
            elif profile.is_excluded(filename, os.path.isdir(backup)):
                continue
            else:
                leaves = profile._inventory_filtered(backup, filename)  # noqa: SLF001
            entries.update(
                os.path.relpath(os.path.join(backup, leaf), root) for leaf in leaves
            )
        baseline[name] = sorted(entries)
    return baseline


def _run_action(
    ctx: _Context,
    app_names: set[str],
    action: str,
    label: str = "",
) -> None:
    """Run an ApplicationProfile method over each app, in sorted order."""
    profiles = _preflight(ctx, app_names, action)
    if action == "copy_files_to_mackeep_folder":
        state = BackupState(ctx.mckp.mackeep_folder)
        if not state.owners:
            baseline = _ownership_baseline(ctx, app_names)
            for _, profile in profiles:
                profile.ownership_baseline = baseline
    failed = False
    for app_name, app in profiles:
        if _cancel_requested:
            sys.exit(CANCELLED_EXIT_CODE)
        _print_app_header(app_name, ctx.verbose)
        if ctx.reporter is not None:
            ctx.reporter("start", {"app": app_name, "action": label or action})
        try:
            getattr(app, action)()
        except (OSError, ConfigError, ValueError) as exc:
            app.failed = True
            print(f"Error: {app_name}: {exc}", file=sys.stderr)
            if ctx.reporter is not None:
                ctx.reporter("error", {"app": app_name, "message": str(exc)})
        if ctx.reporter is not None:
            ctx.reporter("done", {"app": app_name, "action": label or action})
        failed = failed or app.failed
    if _cancel_requested:
        sys.exit(CANCELLED_EXIT_CODE)
    if failed:
        sys.exit("One or more applications could not be copied.")


def _cmd_list(app_db: ApplicationsDatabase) -> None:
    output: str = "Supported applications:\n"
    for app_name in sorted(app_db.get_app_names()):
        output += f" - {app_name}\n"
    output += "\n"
    output += (
        f"{len(app_db.get_app_names())} applications supported in Mackeep v{VERSION}"
    )
    print(output)


def _print_warnings(ctx: _Context) -> None:
    """
    Tell the user about the rules that were skipped.

    The broken rules do not stop Mackeep from working, they are reported
    here, so the user can fix them.

    Args:
        ctx (_Context): The context of the command.
    """
    for message in ctx.mckp.config.errors:
        print(f"Warning: {message}", file=sys.stderr)

    for app_name in sorted(ctx.app_db.get_app_names()):
        error: str | None = ctx.app_db.get_error(app_name)
        if error:
            print(f"Warning: {error}", file=sys.stderr)


def _cmd_show(args: dict[str, Any], app_db: ApplicationsDatabase) -> None:
    requested_app_name: str = args["<application>"]

    # Make sure the app exists
    if requested_app_name not in app_db.get_app_names():
        raise _UnsupportedApplicationError(
            f"Unsupported application: {requested_app_name}",
        )
    print(f"Name: {app_db.get_name(requested_app_name)}")
    print("Configuration files:")
    for file in app_db.get_files(requested_app_name):
        print(f" - {file}")

    exclude: list[str] = app_db.get_exclude(requested_app_name)
    if exclude:
        print("Excluded paths:")
        for pattern in exclude:
            print(f" - {pattern}")

    xdg_exclude: list[str] = app_db.get_xdg_exclude(requested_app_name)
    if xdg_exclude:
        print("Excluded XDG paths:")
        for pattern in xdg_exclude:
            print(f" - {pattern}")


def _cmd_backup(args: dict[str, Any], ctx: _Context) -> None:
    # Resolve and validate the target apps before the env check, so an
    # unknown application name fails cleanly without creating the Mackeep
    # folder or prompting first.
    app_names = _resolve_apps(args["<application>"], ctx)
    _preflight(ctx, app_names, "copy_files_to_mackeep_folder")
    if ctx.dry_run:
        # A dry-run does not create anything.
        ctx.mckp.check_for_usable_environment()
    else:
        ctx.mckp.check_for_usable_backup_env()

    # Create a backup of the files of each application
    if args.get("--summary"):
        summary = BackupSummary()
        ctx.reporter = summary
        ctx.verbose = False
        try:
            with SummaryOutput() as output, redirect_stdout(output):
                _run_action(ctx, app_names, "copy_files_to_mackeep_folder")
        finally:
            summary.display()
    else:
        _run_action(ctx, app_names, "copy_files_to_mackeep_folder")


def _cmd_restore(args: dict[str, Any], ctx: _Context) -> None:
    app_names = _resolve_apps(args["<application>"], ctx)
    _preflight(ctx, app_names, "copy_files_from_mackeep_folder")
    if ctx.dry_run:
        # A dry-run does not need the backup folder to exist, the missing
        # files are reported as such.
        ctx.mckp.check_for_usable_environment()
    else:
        ctx.mckp.check_for_usable_restore_env()

    # Recover a backup of the files of each application
    _run_action(ctx, app_names, "copy_files_from_mackeep_folder")


def _cmd_link_install(args: dict[str, Any], ctx: _Context) -> None:
    app_names = _resolve_apps(args["<application>"], ctx)
    _preflight(ctx, app_names, "link_install")
    # Check the env where the command is being run
    if ctx.dry_run:
        ctx.mckp.check_for_usable_environment()
    else:
        ctx.mckp.check_for_usable_backup_env()

    # Create a link for each application
    _run_action(ctx, app_names, "link_install")


def _cmd_link_uninstall(args: dict[str, Any], ctx: _Context) -> None:
    # Validate any named application before the env check, so an unknown
    # name fails cleanly before any prompt or side effect.
    named_apps = (
        _resolve_apps(args["<application>"], ctx) if args["<application>"] else None
    )

    # Check the env where the command is being run
    ctx.mckp.check_for_usable_restore_env()

    if named_apps is not None:
        # Unlink only the named application, leaving the rest of Mackeep
        # (and the Mackeep config itself) in place. No global confirmation
        # is needed since the user explicitly scoped the uninstall.
        _run_action(ctx, named_apps, "link_uninstall")

    elif ctx.dry_run or (
        utils.confirm(
            "You are going to uninstall Mackeep.\n"
            "Every configuration file, setting and dotfile"
            " managed by Mackeep will be unlinked and copied back"
            " to their original place, in your home folder.\n"
            "Are you sure?",
        )
    ):
        # Uninstall the apps except Mackeep, which we'll uninstall last, to
        # keep the settings as long as possible
        app_names = ctx.mckp.get_apps_to_backup(ctx.app_db)
        app_names.discard(MACKEEP_APP_NAME)

        _run_action(ctx, app_names, "link_uninstall")

        # Restore the Mackeep config before any other config, as we might
        # need it to know about custom settings
        _run_action(ctx, {MACKEEP_APP_NAME}, "link_uninstall")

        print(
            "\n"
            "All your files have been put back into place. You can now"
            " safely uninstall Mackeep.\n"
            "\n"
            "Thanks for using Mackeep!",
        )


def _cmd_link(args: dict[str, Any], ctx: _Context) -> None:
    # Validate any named application before the env check.
    named_apps = (
        _resolve_apps(args["<application>"], ctx) if args["<application>"] else None
    )

    # Check the env where the command is being run
    ctx.mckp.check_for_usable_restore_env()

    if named_apps is not None:
        # Link only the named application. No need to restore the Mackeep
        # config first, as the app set is fixed and config-independent here.
        _run_action(ctx, named_apps, "link")
        return

    # Restore the Mackeep config before any other config, as we might
    # need it to know about custom settings
    original_storage = os.path.realpath(ctx.mckp.mackeep_folder)
    _run_action(ctx, {MACKEEP_APP_NAME}, "link")

    # Initialize again the apps db, as the Mackeep config might have
    # changed it
    ctx.mckp = Mackeep(ctx.config_file)
    ctx.app_db = ApplicationsDatabase(
        allow_external_paths=ctx.mckp.config.allow_external_paths,
    )

    # Restore the rest of the app configs, using the restored Mackeep config
    app_names = ctx.mckp.get_apps_to_backup(ctx.app_db)
    # Mackeep has already been done
    app_names.discard(MACKEEP_APP_NAME)

    if (
        not ctx.dry_run
        and os.path.realpath(ctx.mckp.mackeep_folder) != original_storage
    ):
        with storage_lock(ctx.mckp.mackeep_folder):
            _run_action(ctx, app_names, "link")
    else:
        _run_action(ctx, app_names, "link")


class _JsonReporter:
    """Collect or stream the operations of a command as JSON events."""

    def __init__(
        self,
        stream: TextIO,
        collect: bool = False,
        max_actions: int = DEFAULT_MAX_ACTIONS,
    ) -> None:
        """
        Create a _JsonReporter instance.

        Args:
            stream (TextIO): The stream the JSON is written to.
            collect (bool): Whether the operations are collected instead of
                            being streamed. Used by the dry-run mode, that
                            answers with a single JSON document.
        """
        self.stream: TextIO = stream
        self.collect: bool = collect
        self.actions: list[dict[str, Any]] = []
        self.files: int = 0
        self.bytes: int = 0
        self.skipped: int = 0
        self.max_actions = max_actions
        self.counts: dict[str, int] = {}
        self.total_actions = 0
        self.total_bytes = 0
        self.total_files = 0
        self._last_copy: tuple[Any, Any, Any] | None = None

    def summary(self, app_names: set[str]) -> dict[str, Any]:
        """Return complete totals while retaining only a bounded action list."""
        result: dict[str, Any] = {
            "apps": sorted(app_names),
            "actions": dict(self.counts),
            "total_actions": self.total_actions,
            "total_bytes": self.total_bytes,
            "files": self.total_files,
        }
        if self.total_actions > self.max_actions:
            result.update(truncated=True, limit=self.max_actions)
        return result

    def __call__(self, action: str, payload: dict[str, Any]) -> None:
        """
        Report an operation.

        Args:
            action (str): The action, e.g. "copy" or "skip_excluded".
            payload (dict): The details of the operation.
        """
        if self.collect:
            if action not in {"start", "done"}:
                self.total_actions += 1
                self.counts[action] = self.counts.get(action, 0) + 1
                key = (payload.get("app"), payload.get("src"), payload.get("dst"))
                if action != "conflict" or key != self._last_copy:
                    self.total_bytes += int(payload.get("size_bytes") or 0)
                if action == "copy":
                    self.total_files += 1
                self._last_copy = key if action == "copy" else None
                if len(self.actions) < self.max_actions:
                    self.actions.append(payload)
            return

        event: str = "file"
        if action == "start":
            # The counters of the "done" event are the ones of the
            # application, not the ones of the whole run.
            self.files = 0
            self.bytes = 0
            self.skipped = 0
            event = "start"
        elif action == "done":
            event = "done"
        elif action == "error":
            event = "error"
        elif action == "copy":
            self.files += 1
            self.bytes += int(payload.get("size_bytes") or 0)
        elif action.startswith("skip") or action == "conflict":
            self.skipped += 1

        details: dict[str, Any] = dict(payload)
        if action == "done":
            details["files"] = self.files
            details["bytes"] = self.bytes
            details["skipped"] = self.skipped

        jsonapi.emit(
            {"schema_version": jsonapi.SCHEMA_VERSION, "event": event, **details},
            self.stream,
        )


def _app_json(app_db: ApplicationsDatabase, app_name: str) -> dict[str, Any]:
    """
    Build the JSON description of an application.

    Args:
        app_db (ApplicationsDatabase): The database of the applications.
        app_name (str): The name of the application.

    Returns:
        dict
    """
    home: str = os.path.expanduser("~")
    xdg_config_home: str = os.environ.get(
        "XDG_CONFIG_HOME",
        os.path.join(home, ".config"),
    )

    files: list[dict[str, Any]] = []
    for path in sorted(app_db.get_home_files(app_name)):
        full_path: str = os.path.join(home, path)
        reason: str | None = utils.sensitive_path_reason(full_path)
        files.append(
            {
                "path": path,
                "exists": os.path.exists(full_path),
                "is_dir": os.path.isdir(full_path),
                "sensitive": reason is not None,
                "sensitive_reason": reason,
            },
        )

    xdg_files: list[dict[str, Any]] = []
    for path in sorted(app_db.get_xdg_files(app_name)):
        full_path = os.path.join(xdg_config_home, path)
        reason = utils.sensitive_path_reason(full_path)
        xdg_files.append(
            {
                "path": path,
                "exists": os.path.exists(full_path),
                "is_dir": os.path.isdir(full_path),
                "sensitive": reason is not None,
                "sensitive_reason": reason,
            },
        )

    return {
        "schema_version": jsonapi.SCHEMA_VERSION,
        "name": app_name,
        "display_name": app_db.get_name(app_name),
        "source": "custom" if app_db.is_custom(app_name) else "builtin",
        "cfg_path": app_db.get_config_file(app_name),
        "files": files,
        "xdg_files": xdg_files,
        "exclude": app_db.get_exclude(app_name),
        "xdg_exclude": app_db.get_xdg_exclude(app_name),
        "error": app_db.get_error(app_name),
    }


def _config_json(ctx: _Context) -> dict[str, Any]:
    """
    Build the JSON description of the configuration of Mackeep.

    Args:
        ctx (_Context): The context of the command.

    Returns:
        dict
    """
    config = ctx.mckp.config
    resolved_backup = config.fullpath

    return {
        "schema_version": jsonapi.SCHEMA_VERSION,
        "version": VERSION,
        "config_file": config.config_path,
        "custom_apps_dir": ApplicationsDatabase.get_custom_apps_dir(),
        "custom_apps_dirs": ApplicationsDatabase.get_custom_apps_dirs(),
        "errors": config.errors,
        "storage": {
            "engine": config.engine,
            "path": config.path,
            "directory": config.directory,
            "resolved_backup_dir": resolved_backup,
            "exists": os.path.isdir(resolved_backup),
        },
        "apps_to_sync": sorted(config.apps_to_sync),
        "apps_to_ignore": sorted(config.apps_to_ignore),
        "allow_external_paths": config.allow_external_paths,
        "storage_configured": bool(config.path),
        "supports_safe_cancellation": True,
        "global_exclude": config.global_exclude,
        "global_xdg_exclude": config.global_xdg_exclude,
    }


def _cmd_migrate(dry_run: bool) -> None:
    """
    Copy legacy configuration files to their new location.

    Args:
        dry_run (bool): Whether the files are only copied in the plan.
    """
    actions: list[dict[str, str]] = migration_plan()
    copied: int = 0
    if not dry_run:
        copied = run_migration(actions)

    for action in actions:
        if action["action"] == "copy":
            print(f"Copy {action['src']}\n  to {action['dst']}")
        elif action["action"] == "set_directory":
            print(
                f"Set the storage directory to {action['directory']}\n"
                f"  in {action['dst']}",
            )
        else:
            print(f"Skip {action['src']}\n  {action['dst']} already exists")

    if dry_run:
        print("\nNothing was copied, this was a dry-run.")
    else:
        print(f"\n{copied} file(s) copied, the old ones were kept.")


def _cmd_config(ctx: _Context) -> None:
    """Display the configuration of Mackeep."""
    config = ctx.mckp.config
    print(f"Version: {VERSION}")
    print(f"Config file: {config.config_path}")
    print(f"Storage engine: {config.engine}")
    print(f"Storage path: {config.path}")
    print(f"Storage directory: {config.directory}")
    print(f"Backup directory: {config.fullpath}")
    sync: list[str] = sorted(config.apps_to_sync)
    ignore: list[str] = sorted(config.apps_to_ignore)
    sync_label = (
        ", ".join(sync)
        if sync
        else ("none" if config.apps_to_sync_is_explicit else "all")
    )
    print(f"Applications to sync: {sync_label}")
    print(f"Applications to ignore: {', '.join(ignore) if ignore else 'none'}")
    if config.global_exclude:
        print("Global exclusions:")
        for pattern in config.global_exclude:
            print(f" - {pattern}")


def _cmd_json_migrate(dry_run: bool, stream: TextIO) -> None:
    """
    Write the plan of the migration as JSON.

    Args:
        dry_run (bool): Whether the files are only copied in the plan.
        stream (TextIO): The stream the JSON is written to.
    """
    actions: list[dict[str, str]] = migration_plan()
    copied: int = 0
    if not dry_run:
        copied = run_migration(actions)
    skipped: int = sum(1 for action in actions if action["action"] == "skip")
    updated: int = sum(1 for action in actions if action["action"] == "set_directory")
    jsonapi.emit(
        {
            "schema_version": jsonapi.SCHEMA_VERSION,
            "actions": actions,
            "summary": {
                "copied": copied,
                "skipped": skipped,
                "updated": updated,
                "total_actions": len(actions),
                "dry_run": dry_run,
            },
        },
        stream,
    )


def _cmd_json(args: dict[str, Any], ctx: _Context, stream: TextIO) -> None:
    """Run a command and write its JSON answer to the given stream."""
    if args["config"]:
        jsonapi.emit(_config_json(ctx), stream)
    elif args["list"]:
        apps: list[dict[str, Any]] = [
            _app_json(ctx.app_db, app_name)
            for app_name in sorted(ctx.app_db.get_app_names())
        ]
        jsonapi.emit(apps, stream)
    elif args["show"]:
        app_name: str = args["<application>"]
        if app_name not in ctx.app_db.get_app_names():
            raise _UnsupportedApplicationError(f"Unsupported application: {app_name}")
        jsonapi.emit(_app_json(ctx.app_db, app_name), stream)
    elif args["backup"] or args["restore"]:
        action: str = (
            "copy_files_to_mackeep_folder"
            if args["backup"]
            else "copy_files_from_mackeep_folder"
        )
        label: str = "backup" if args["backup"] else "restore"

        app_names = _resolve_apps(args["<application>"], ctx)
        _preflight(ctx, app_names, action)
        if ctx.dry_run:
            # A dry-run does not create anything and does not need the
            # backup folder to exist.
            ctx.mckp.check_for_usable_environment()
        elif args["backup"]:
            ctx.mckp.check_for_usable_backup_env()
        else:
            ctx.mckp.check_for_usable_restore_env()

        reporter: _JsonReporter = _JsonReporter(stream, ctx.dry_run, ctx.max_actions)
        ctx.reporter = reporter
        _run_action(ctx, app_names, action, label)

        if ctx.dry_run:
            actions = reporter.actions
            summary = reporter.summary(app_names)
            jsonapi.emit(
                {
                    "schema_version": jsonapi.SCHEMA_VERSION,
                    "actions": actions,
                    "summary": summary,
                },
                stream,
            )
    else:
        sys.exit("The --json option is not supported for this command.")


def _clean_error(message: str) -> str:
    """
    Clean up an error message, so it can be shown as is.

    Args:
        message (str): The raw message.

    Returns:
        str
    """
    text: str = ANSI_CODES.sub("", message).strip()
    return text.removeprefix("Error: ")



def main() -> None:
    """Main function."""
    # Get the command line arg
    docstring = __doc__
    if not docstring:
        sys.exit(
            "Usage information is not available because __doc__ is None. "
            "This can happen when running Python with optimizations (python -OO). "
            "Please run Mackeep without -OO to use the command-line interface.",
        )
    assert docstring is not None  # for type narrowing after sys.exit

    # The version is shown with -v, -V and --version. docopt only knows
    # one short option per line, so they are handled here.
    if any(argument in {"-v", "-V", "--version"} for argument in sys.argv[1:]):
        print(f"Mackeep {VERSION}")
        sys.exit(0)

    json_mode: bool = "--json" in sys.argv[1:]
    stdout: TextIO = sys.stdout
    if json_mode:
        # In JSON mode, stdout only holds JSON. The human-readable output
        # goes to stderr.
        sys.stdout = sys.stderr

    global _cancel_requested  # noqa: PLW0603 - signal handler state
    _cancel_requested = False
    previous_flags = utils.FORCE_YES, utils.FORCE_NO, utils.CAN_RUN_AS_ROOT
    previous_handler = signal.signal(signal.SIGUSR1, _request_cancel)
    try:
        args: dict[str, Any] = docopt(docstring, version=f"Mackeep {VERSION}")
        _run(args, json_mode, stdout)
    except SystemExit as e:
        _handle_exit(e, json_mode, stdout)
    except ConfigError as e:
        if json_mode:
            jsonapi.emit_error(e.code, str(e), stdout)
            sys.exit(1)
        sys.exit(str(e))
    except Exception as exc:
        if json_mode:
            jsonapi.emit_error("error", str(exc), stdout)
            traceback.print_exc(file=sys.stderr)
            sys.exit(1)
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        signal.signal(signal.SIGUSR1, previous_handler)
        utils.FORCE_YES, utils.FORCE_NO, utils.CAN_RUN_AS_ROOT = previous_flags
        sys.stdout = stdout


def _detail_level(detail: str | None) -> str:
    """
    Get the detail level of the dry-run.

    Args:
        detail (str): The value of the --detail option.

    Returns:
        str: "entries" or "files".
    """
    if not detail:
        return "entries"
    if detail not in {"entries", "files"}:
        sys.exit(f"Unknown detail level: {detail} (use entries or files)")
    return detail


def _max_actions(max_actions: str | None) -> int:
    """
    Get the maximum number of actions of the JSON dry-run.

    Args:
        max_actions (str): The value of the --max-actions option.

    Returns:
        int
    """
    if not max_actions:
        return DEFAULT_MAX_ACTIONS
    try:
        limit: int = int(max_actions)
    except ValueError:
        sys.exit(f"Invalid number of actions: {max_actions}")
    if limit < 1:
        sys.exit(f"Invalid number of actions: {max_actions}")
    return limit


def _handle_exit(exc: SystemExit, json_mode: bool, stdout: TextIO) -> None:
    """
    Handle the exit of a command.

    In JSON mode, the error is written as a JSON document and the exit code
    is not zero.

    Args:
        exc (SystemExit): The exception that ended the command.
        json_mode (bool): Whether the JSON output is enabled.
        stdout (TextIO): The stream the JSON is written to.
    """
    code: Any = exc.code
    if code is None or code == 0:
        raise exc

    if isinstance(code, str):
        message: str = _clean_error(code)
        error_code: str = "error"
    elif code == CANCELLED_EXIT_CODE:
        message = "Cancelled after the current application."
        error_code = "cancelled"
    else:
        message = f"Mackeep failed with the exit code {code}"
        error_code = "error"

    if json_mode:
        jsonapi.emit_error(error_code, message, stdout)
        sys.exit(CANCELLED_EXIT_CODE if code == CANCELLED_EXIT_CODE else 1)

    raise exc


def _run(args: dict[str, Any], json_mode: bool, stdout: TextIO) -> None:
    """
    Run the command line.

    Args:
        args (dict): The parsed command line arguments.
        json_mode (bool): Whether the JSON output is enabled.
        stdout (TextIO): The stream the JSON is written to.
    """
    if args["--force"] and args["--force-no"]:
        sys.exit("Options --force and --force-no are mutually exclusive.")
    if args.get("--summary") and (not args["backup"] or args["--dry-run"]):
        sys.exit("The --summary option requires backup without --dry-run.")

    if args.get("library"):
        if args["--dry-run"]:
            sys.exit("Library commands do not support --dry-run; use library check.")
        if args["remove"]:
            result = library.remove(args["<application>"], args.get("--config-file"))
        elif args["update"]:
            result = library.update(args["<application>"])
        else:
            result = library.check()
        if json_mode:
            jsonapi.emit(result, stdout)
        else:
            print(f"Library updates available: {len(result['updates'])}")
        return

    if args["migrate"]:
        # The migrate command does not need a usable storage, it is the way
        # to fix a configuration that does not work yet.
        dry_run: bool = bool(args["--dry-run"])
        if json_mode:
            _cmd_json_migrate(dry_run, stdout)
        else:
            _cmd_migrate(dry_run)
        return

    config_file: str | None = args.get("--config-file")
    mckp = Mackeep(config_file, read_only=bool(args["--dry-run"]))
    ctx = _Context(
        config_file=config_file,
        mckp=mckp,
        app_db=ApplicationsDatabase(
            allow_external_paths=mckp.config.allow_external_paths,
        ),
        dry_run=args["--dry-run"],
        verbose=args["--verbose"],
        detail=_detail_level(args.get("--detail")),
        max_actions=_max_actions(args.get("--max-actions")),
        replace_backup=not args["--force-no"],
    )

    if args["--force"]:
        utils.FORCE_YES = True
    if args["--force-no"] or json_mode:
        utils.FORCE_NO = True
    if args["--force-no"]:
        utils.FORCE_YES = False

    # Allow mackeep to be run as root
    if args["--root"]:
        utils.CAN_RUN_AS_ROOT = True

    if args["config"]:
        _ = mckp.config.path
    _print_warnings(ctx)

    if (
        not ctx.dry_run
        and (args["backup"] or args["restore"] or args["link"])
        and mckp.config.path
    ):
        with storage_lock(mckp.mackeep_folder):
            _dispatch(args, ctx, json_mode, stdout)
    else:
        _dispatch(args, ctx, json_mode, stdout)


def _dispatch(
    args: dict[str, Any], ctx: _Context, json_mode: bool, stdout: TextIO,
) -> None:
    """Dispatch after acquiring a local lock for filesystem writes."""
    if json_mode:
        _cmd_json(args, ctx, stdout)
        return

    if args["list"]:
        _cmd_list(ctx.app_db)
    elif args["show"]:
        _cmd_show(args, ctx.app_db)
    elif args["config"]:
        _cmd_config(ctx)
    elif args["backup"]:
        _cmd_backup(args, ctx)
    elif args["restore"]:
        _cmd_restore(args, ctx)
    elif args["link"] and args["install"]:
        _cmd_link_install(args, ctx)
    elif args["link"] and args["uninstall"]:
        _cmd_link_uninstall(args, ctx)
    elif args["link"]:
        _cmd_link(args, ctx)
