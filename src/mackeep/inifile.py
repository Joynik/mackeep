"""
Reading of the INI files of the configuration.

The config files of the applications and the config file of Mackeep are INI
files. A broken file does not stop the whole tool: the problem is reported
and the other options of the file are used.
"""

import configparser
from dataclasses import dataclass, field


@dataclass
class IniFile:
    """The content of an INI file, and the problems it holds."""

    # The parser that holds the options of the file.
    parser: configparser.ConfigParser

    # The problems of the file, they are reported, not fatal.
    problems: list[str] = field(default_factory=list)

    # Whether the file was read.
    read: bool = False


def read(
    path: str,
    *,
    allow_no_value: bool = True,
    inline_comment_prefixes: tuple[str, ...] | None = None,
    keep_case: bool = True,
) -> IniFile:
    """
    Read an INI file, the broken options are reported, not fatal.

    A duplicated option or section is the only problem that is reported
    here: the file is read again without the strict mode, so the other
    options of the file are usable.

    Args:
        path (str): The path of the file.
        allow_no_value (bool): Whether the options may have no value.
        inline_comment_prefixes (tuple of str): The prefixes of the comments
            that are at the end of a line.
        keep_case (bool): Whether the name of the options keeps its case.

    Returns:
        IniFile: The content of the file and its problems.
    """
    problems: list[str] = []

    parser: configparser.ConfigParser = _make_parser(
        strict=True,
        allow_no_value=allow_no_value,
        inline_comment_prefixes=inline_comment_prefixes,
        keep_case=keep_case,
    )

    try:
        read_files: list[str] = parser.read(path)
    except configparser.DuplicateOptionError as e:
        problems.append(
            f"Invalid option in {path}: '{e.option}' is duplicated in the "
            f"section [{e.section}]",
        )
        parser = _make_parser(
            strict=False,
            allow_no_value=allow_no_value,
            inline_comment_prefixes=inline_comment_prefixes,
            keep_case=keep_case,
        )
        read_files = parser.read(path)
    except configparser.DuplicateSectionError as e:
        problems.append(
            f"Invalid section in {path}: the section [{e.section}] is duplicated",
        )
        parser = _make_parser(
            strict=False,
            allow_no_value=allow_no_value,
            inline_comment_prefixes=inline_comment_prefixes,
            keep_case=keep_case,
        )
        read_files = parser.read(path)

    return IniFile(parser=parser, problems=problems, read=bool(read_files))


def _make_parser(
    *,
    strict: bool,
    allow_no_value: bool,
    inline_comment_prefixes: tuple[str, ...] | None,
    keep_case: bool,
) -> configparser.ConfigParser:
    """
    Build the parser that reads an INI file.

    Args:
        strict (bool): Whether the duplicated options are an error.
        allow_no_value (bool): Whether the options may have no value.
        inline_comment_prefixes (tuple of str): The prefixes of the comments
            that are at the end of a line.
        keep_case (bool): Whether the name of the options keeps its case.

    Returns:
        configparser.ConfigParser
    """
    parser: configparser.ConfigParser = configparser.ConfigParser(
        allow_no_value=allow_no_value,
        inline_comment_prefixes=inline_comment_prefixes,
        strict=strict,
    )

    if keep_case:
        # The names of the options are the paths and the patterns of the
        # user, their case matters.
        parser.optionxform = str  # type: ignore

    return parser
