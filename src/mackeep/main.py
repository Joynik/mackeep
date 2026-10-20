"""Mackeep.

Keep your application settings in sync.

Mackeep is a fork of Mackup, written by Laurent Raufaste.
Copyright (C) 2013-2025 Laurent Raufaste <http://glop.org/>

Usage:
  mackeep [options] list
  mackeep [options] show <application>
  mackeep [options] config
  mackeep [options] backup [<application>]
  mackeep [options] restore [<application>]
  mackeep [options] link install [<application>]
  mackeep [options] link uninstall [<application>]
  mackeep [options] link [<application>]
  mackeep (-h | --help)

Options:
  -h --help                 Show this screen.
  -f --force                Force every question asked to be answered with "Yes".
  --force-no                Force every question asked to be answered with "No".
  -r --root                 Allow mackeep to be run as superuser.
  -n --dry-run              Show steps without executing.
  -v --verbose              Show additional details.
  -c --config-file=<path>   Specify custom config file path.
  --json                    Output machine-readable JSON.
  --version                 Show version.

Modes of action:
 - mackeep list: display a list of all supported applications.
 - mackeep show: display the details for a supported application.
 - mackeep config: display the configuration of Mackeep.
 - mackeep backup: copy local config files in the configured remote folder.
 - mackeep restore: copy config files from the configured remote folder locally.
 - mackeep link install: moves local config files in remote folder, and links.
 - mackeep link uninstall: removes the links and copy config files locally.
 - mackeep link: links local config files from the remote folder.

backup, restore, link install, link uninstall and link act on every configured
application by default. Name a single application (e.g. `mackeep backup vim`) to
limit a command to that app, overriding the applications_to_sync and
applications_to_ignore settings in your config.

By default, Mackeep syncs all application data via
Dropbox, but may be configured to exclude applications or use a different
backend with a .mackeep.cfg file.

The --json option writes a machine-readable answer, meant to be used by
graphical front-ends. In this mode, only JSON is written to stdout, the
human-readable output is written to stderr and no question is asked.

See https://github.com/Joynik/mackeep/tree/master/doc for more information.

"""

import os
import re
import sys
from dataclasses import dataclass
from typing import Any, TextIO

from docopt import docopt

from . import jsonapi, utils
from .application import ApplicationProfile, Reporter
from .appsdb import ApplicationsDatabase
from .config import ConfigError
from .constants import (
    CUSTOM_APPS_DIR,
    CUSTOM_APPS_DIR_XDG,
    MACKEEP_APP_NAME,
    VERSION,
)
from .excludes import Matcher
from .mackeep import Mackeep

# The ANSI escape codes used to color the error messages
ANSI_CODES = re.compile(r"\033\[[0-9;]*m")


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


def _print_app_header(app_name: str, verbose: bool) -> None:
    if verbose:
        header_str = header("---")
        print(f"\n{header_str} {bold(app_name)} {header_str}")


def _make_profile(ctx: _Context, app_name: str) -> ApplicationProfile:
    """Create the profile of an application, with its exclusion rules."""
    app: ApplicationProfile = ApplicationProfile(
        ctx.mckp, ctx.app_db.get_files(app_name), ctx.dry_run, ctx.verbose,
    )
    app.configure(
        exclude=Matcher(ctx.mckp.config.global_exclude).extended(
            ctx.app_db.get_exclude(app_name),
        ),
        xdg_exclude=Matcher(ctx.mckp.config.global_xdg_exclude).extended(
            ctx.app_db.get_xdg_exclude(app_name),
        ),
        reporter=ctx.reporter,
        app_name=app_name,
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
            sys.exit(f"Unsupported application: {app_name}")
        return {app_name}
    return ctx.mckp.get_apps_to_backup()


def _run_action(
    ctx: _Context, app_names: set[str], action: str, label: str = "",
) -> None:
    """Run an ApplicationProfile method over each app, in sorted order."""
    for app_name in sorted(app_names):
        app = _make_profile(ctx, app_name)
        _print_app_header(app_name, ctx.verbose)
        if ctx.reporter is not None:
            ctx.reporter("start", {"app": app_name, "action": label or action})
        getattr(app, action)()
        if ctx.reporter is not None:
            ctx.reporter("done", {"app": app_name, "action": label or action})


def _cmd_list(app_db: ApplicationsDatabase) -> None:
    output: str = "Supported applications:\n"
    for app_name in sorted(app_db.get_app_names()):
        output += f" - {app_name}\n"
    output += "\n"
    output += (
        f"{len(app_db.get_app_names())} applications supported in Mackeep v{VERSION}"
    )
    print(output)


def _cmd_show(args: dict[str, Any], app_db: ApplicationsDatabase) -> None:
    requested_app_name: str = args["<application>"]

    # Make sure the app exists
    if requested_app_name not in app_db.get_app_names():
        sys.exit(f"Unsupported application: {requested_app_name}")
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
    ctx.mckp.check_for_usable_backup_env()

    # Create a backup of the files of each application
    _run_action(ctx, app_names, "copy_files_to_mackeep_folder")


def _cmd_restore(args: dict[str, Any], ctx: _Context) -> None:
    app_names = _resolve_apps(args["<application>"], ctx)
    ctx.mckp.check_for_usable_restore_env()

    # Recover a backup of the files of each application
    _run_action(ctx, app_names, "copy_files_from_mackeep_folder")


def _cmd_link_install(args: dict[str, Any], ctx: _Context) -> None:
    app_names = _resolve_apps(args["<application>"], ctx)
    # Check the env where the command is being run
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
        app_names = ctx.mckp.get_apps_to_backup()
        app_names.discard(MACKEEP_APP_NAME)

        _run_action(ctx, app_names, "link_uninstall")

        # Restore the Mackeep config before any other config, as we might
        # need it to know about custom settings
        mackeep_app = _make_profile(ctx, MACKEEP_APP_NAME)
        mackeep_app.link_uninstall()

        # Delete the Mackeep folder in Dropbox
        # Don't delete this as there might be other Macs that aren't
        # uninstalled yet
        # delete(mckp.mackeep_folder)

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
    mackeep_app = _make_profile(ctx, MACKEEP_APP_NAME)
    _print_app_header(MACKEEP_APP_NAME, ctx.verbose)
    mackeep_app.link()

    # Initialize again the apps db, as the Mackeep config might have
    # changed it
    ctx.mckp = Mackeep(ctx.config_file)
    ctx.app_db = ApplicationsDatabase()

    # Restore the rest of the app configs, using the restored Mackeep config
    app_names = ctx.mckp.get_apps_to_backup()
    # Mackeep has already been done
    app_names.discard(MACKEEP_APP_NAME)

    _run_action(ctx, app_names, "link")


class _JsonReporter:
    """Collect or stream the operations of a command as JSON events."""

    def __init__(self, stream: TextIO, collect: bool = False) -> None:
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

    def __call__(self, action: str, payload: dict[str, Any]) -> None:
        """
        Report an operation.

        Args:
            action (str): The action, e.g. "copy" or "skip_excluded".
            payload (dict): The details of the operation.
        """
        if self.collect:
            if action not in {"start", "done"}:
                self.actions.append(payload)
            return

        if action == "copy":
            self.files += 1
            self.bytes += int(payload.get("size_bytes") or 0)
        elif action.startswith("skip"):
            self.skipped += 1

        event: str = "file"
        if action == "start":
            event = "start"
        elif action == "done":
            event = "done"
        elif action == "error":
            event = "error"

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
    home: str = os.environ["HOME"]
    xdg_config_home: str = os.environ.get(
        "XDG_CONFIG_HOME", os.path.join(home, ".config"),
    )

    files: list[dict[str, Any]] = []
    for path in sorted(app_db.get_home_files(app_name)):
        full_path: str = os.path.join(home, path)
        files.append(
            {
                "path": path,
                "exists": os.path.exists(full_path),
                "is_dir": os.path.isdir(full_path),
            },
        )

    xdg_files: list[dict[str, Any]] = []
    for path in sorted(app_db.get_xdg_files(app_name)):
        full_path = os.path.join(xdg_config_home, path)
        xdg_files.append(
            {
                "path": path,
                "exists": os.path.exists(full_path),
                "is_dir": os.path.isdir(full_path),
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
    home: str = os.environ["HOME"]
    xdg_config_home: str = os.environ.get(
        "XDG_CONFIG_HOME", os.path.join(home, ".config"),
    )

    return {
        "schema_version": jsonapi.SCHEMA_VERSION,
        "version": VERSION,
        "config_file": config.config_path,
        "custom_apps_dirs": [
            os.path.join(home, CUSTOM_APPS_DIR),
            os.path.join(xdg_config_home, CUSTOM_APPS_DIR_XDG),
        ],
        "storage": {
            "engine": config.engine,
            "path": config.path,
            "directory": config.directory,
            "resolved_backup_dir": config.fullpath,
            "exists": os.path.isdir(config.fullpath),
        },
        "apps_to_sync": sorted(config.apps_to_sync),
        "apps_to_ignore": sorted(config.apps_to_ignore),
        "global_exclude": config.global_exclude,
        "global_xdg_exclude": config.global_xdg_exclude,
    }


def _summary(actions: list[dict[str, Any]], app_names: set[str]) -> dict[str, Any]:
    """
    Build the summary of a dry-run.

    Args:
        actions (list): The actions of the dry-run.
        app_names (set): The names of the applications.

    Returns:
        dict
    """
    counts: dict[str, int] = {}
    total_bytes: int = 0
    for action in actions:
        name: str = str(action.get("action", "unknown"))
        counts[name] = counts.get(name, 0) + 1
        total_bytes += int(action.get("size_bytes") or 0)

    return {
        "apps": sorted(app_names),
        "actions": counts,
        "total_actions": len(actions),
        "total_bytes": total_bytes,
    }


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
    print(f"Applications to sync: {', '.join(sync) if sync else 'all'}")
    print(f"Applications to ignore: {', '.join(ignore) if ignore else 'none'}")
    if config.global_exclude:
        print("Global exclusions:")
        for pattern in config.global_exclude:
            print(f" - {pattern}")


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
            sys.exit(f"Unsupported application: {app_name}")
        jsonapi.emit(_app_json(ctx.app_db, app_name), stream)
    elif args["backup"] or args["restore"]:
        action: str = (
            "copy_files_to_mackeep_folder"
            if args["backup"]
            else "copy_files_from_mackeep_folder"
        )
        label: str = "backup" if args["backup"] else "restore"

        app_names = _resolve_apps(args["<application>"], ctx)
        if args["backup"]:
            ctx.mckp.check_for_usable_backup_env()
        else:
            ctx.mckp.check_for_usable_restore_env()

        reporter: _JsonReporter = _JsonReporter(stream, ctx.dry_run)
        ctx.reporter = reporter
        _run_action(ctx, app_names, action, label)

        if ctx.dry_run:
            jsonapi.emit(
                {
                    "schema_version": jsonapi.SCHEMA_VERSION,
                    "actions": reporter.actions,
                    "summary": _summary(reporter.actions, app_names),
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


def _error_code(message: str) -> str:
    """
    Guess the code of an error from its message.

    Args:
        message (str): The message of the error.

    Returns:
        str
    """
    if message.startswith("Unsupported application"):
        return "unsupported_application"
    if "config" in message.lower():
        return "config_error"
    return "error"


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

    args: dict[str, Any] = docopt(docstring, version=f"Mackeep {VERSION}")

    json_mode: bool = bool(args["--json"])
    stdout: TextIO = sys.stdout
    if json_mode:
        # In JSON mode, stdout only holds JSON. The human-readable output
        # goes to stderr.
        sys.stdout = sys.stderr

    try:
        _run(args, json_mode, stdout)
    except SystemExit as e:
        _handle_exit(e, json_mode, stdout)
    except ConfigError as e:
        if json_mode:
            jsonapi.emit_error("config_error", str(e), stdout)
            sys.exit(1)
        raise
    finally:
        sys.stdout = stdout


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
        error_code: str = _error_code(message)
    else:
        message = f"Mackeep failed with the exit code {code}"
        error_code = "error"

    if json_mode:
        jsonapi.emit_error(error_code, message, stdout)
        sys.exit(1)

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

    config_file: str | None = args.get("--config-file")
    ctx = _Context(
        config_file=config_file,
        mckp=Mackeep(config_file),
        app_db=ApplicationsDatabase(),
        dry_run=args["--dry-run"],
        verbose=args["--verbose"],
    )

    # If we want to answer mackeep with "yes" for each question
    if args["--force"]:
        utils.FORCE_YES = True

    # If we want to answer mackeep with "no" for each question
    if args["--force-no"]:
        utils.FORCE_NO = True
    elif json_mode:
        # No question can be asked in JSON mode
        utils.FORCE_NO = True

    # Allow mackeep to be run as root
    if args["--root"]:
        utils.CAN_RUN_AS_ROOT = True

    if json_mode:
        _cmd_json(args, ctx, stdout)
        return

    if args["list"]:
        ctx.mckp.check_for_usable_environment()
        _cmd_list(ctx.app_db)
    elif args["show"]:
        ctx.mckp.check_for_usable_environment()
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
