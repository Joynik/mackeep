"""
Exclusion rules for Mackeep.

This module implements a gitignore-like matcher used by the ``[exclude]`` and
``[xdg_exclude]`` sections of the application config files, and by the global
``[exclude]`` section of the Mackeep config file.

The semantics are the following:

- Patterns are relative to a root directory (``$HOME`` for ``[exclude]``,
  ``$XDG_CONFIG_HOME`` for ``[xdg_exclude]``).
- ``*`` matches anything but a slash, ``?`` matches a single character but a
  slash and ``**`` matches anything, slashes included.
- A pattern without any slash matches a *name* at any depth.
- A pattern with a slash is relative to the root of the tree.
- A pattern ending with a slash only matches directories.
- A pattern starting with ``!`` re-includes a previously excluded path. The
  last matching pattern wins.
- Matching is case sensitive.
"""

import re
from dataclasses import dataclass, replace
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterable, Iterator

# Characters that make a path component a wildcard.
WILDCARD_CHARS: str = "*?"


@dataclass(frozen=True)
class Rule:
    """An exclusion rule, with the place it comes from."""

    pattern: str
    section: str = ""
    file: str = ""


@dataclass(frozen=True)
class Pattern:
    """A single, parsed exclusion pattern."""

    raw: str
    source: str
    negated: bool
    dir_only: bool
    anchored: bool
    scope: str
    regex: re.Pattern[str]
    section: str = ""
    file: str = ""

    def matches(self, path: str, is_dir: bool) -> bool:
        """
        Check if the given path matches this pattern.

        Args:
            path (str): Path relative to the root of the tree.
            is_dir (bool): Whether the path is a directory.

        Returns:
            bool
        """
        if self.anchored:
            if self.dir_only and not is_dir:
                return False
            return self.regex.fullmatch(path) is not None

        # A pattern without any slash matches a name at any depth.
        components: list[str] = path.split("/")
        last: int = len(components) - 1
        for index, component in enumerate(components):
            if self.regex.fullmatch(component) is None:
                continue
            if not self.dir_only:
                return True
            # A directory-only pattern matches an ancestor directory, or the
            # path itself when it is a directory.
            if index < last or is_dir:
                return True
        return False


def _translate(pattern: str) -> str:
    """
    Translate a gitignore-like pattern into a regular expression.

    Args:
        pattern (str): The pattern, without its leading ``!`` nor its
                       trailing ``/``.

    Returns:
        str: The regular expression source.
    """
    result: list[str] = []
    index: int = 0
    length: int = len(pattern)

    while index < length:
        char: str = pattern[index]
        if char == "*":
            if pattern.startswith("**/", index):
                result.append("(?:.*/)?")
                index += 3
            elif pattern.startswith("**", index):
                result.append(".*")
                index += 2
            else:
                result.append("[^/]*")
                index += 1
        elif char == "?":
            result.append("[^/]")
            index += 1
        elif char == "\\" and index + 1 < length:
            # An escaped character is taken literally.
            result.append(re.escape(pattern[index + 1]))
            index += 2
        else:
            result.append(re.escape(char))
            index += 1

    return "".join(result)


def _scope(pattern: str, anchored: bool) -> str:
    """
    Compute the static scope of a pattern.

    The scope is the leading part of the pattern that does not contain any
    wildcard. It is used to know if a pattern may match something inside a
    given directory. An empty scope means that the pattern may match
    anywhere.

    Args:
        pattern (str): The pattern, without its leading ``!`` nor its
                       trailing ``/``.
        anchored (bool): Whether the pattern is relative to the root.

    Returns:
        str
    """
    if not anchored:
        return ""

    scope: list[str] = []
    for component in pattern.split("/"):
        if any(char in component for char in WILDCARD_CHARS):
            break
        scope.append(component)

    return "/".join(scope)


def parse_pattern(raw: str) -> Pattern | None:
    """
    Parse a single exclusion pattern.

    Args:
        raw (str): The raw pattern, as read from a config file.

    Returns:
        Pattern or None: None when the pattern is empty or a comment.
    """
    source: str = raw.strip()
    if not source or source.startswith(("#", ";")):
        return None

    negated: bool = False
    if source.startswith("!"):
        negated = True
        source = source[1:].strip()
    elif source.startswith("\\!"):
        source = source[1:]

    dir_only: bool = source.endswith("/")
    if dir_only:
        source = source.rstrip("/")

    if not source:
        return None

    anchored: bool = "/" in source
    if source.startswith("/"):
        source = source.lstrip("/")
        anchored = True

    body: str = _translate(source)
    if anchored and not source.endswith("/**"):
        # The pattern also covers everything below a matching directory.
        body = f"{body}(?:/.*)?"

    return Pattern(
        raw=raw.strip(),
        source=source,
        negated=negated,
        dir_only=dir_only,
        anchored=anchored,
        scope=_scope(source, anchored),
        regex=re.compile(f"^{body}$"),
    )


class Matcher:
    """
    An immutable set of exclusion patterns.

    A matcher is built from a list of raw patterns and answers whether a path
    is excluded. The last matching pattern wins, so a pattern starting with
    ``!`` re-includes a path excluded by a previous pattern.
    """

    def __init__(self, patterns: Iterable[str | Rule] = ()) -> None:
        """
        Create a Matcher instance.

        Args:
            patterns (Iterable[str | Rule]): The raw exclusion patterns,
                or the rules, with the section and the file they come from.
        """
        parsed: list[Pattern] = []
        for item in patterns:
            rule: Rule = item if isinstance(item, Rule) else Rule(item)
            pattern: Pattern | None = parse_pattern(rule.pattern)
            if pattern is not None:
                parsed.append(
                    replace(pattern, section=rule.section, file=rule.file),
                )

        self._patterns: tuple[Pattern, ...] = tuple(parsed)

    @property
    def patterns(self) -> tuple[str, ...]:
        """
        The raw patterns of this matcher.

        Returns:
            tuple of str
        """
        return tuple(pattern.raw for pattern in self._patterns)

    def __bool__(self) -> bool:
        """Whether this matcher holds at least one pattern."""
        return bool(self._patterns)

    def __len__(self) -> int:
        """The number of patterns of this matcher."""
        return len(self._patterns)

    def extended(self, patterns: Iterable[str | Rule]) -> Matcher:
        """
        Return a new matcher with additional patterns.

        The patterns of this matcher come first, so the given ones have the
        last word when a path matches several patterns.

        Args:
            patterns (Iterable[str | Rule]): The raw exclusion patterns to
                add.

        Returns:
            Matcher
        """
        rules: list[str | Rule] = [
            Rule(pattern.raw, pattern.section, pattern.file)
            for pattern in self._patterns
        ]
        rules.extend(patterns)
        return Matcher(rules)

    def is_excluded(self, rel_path: str, is_dir: bool = False) -> bool:
        """
        Check if a path is excluded.

        Args:
            rel_path (str): The path, relative to the root of the tree.
            is_dir (bool): Whether the path is a directory.

        Returns:
            bool: True when the path is excluded.
        """
        pattern: Pattern | None = self.match(rel_path, is_dir)
        return pattern is not None and not pattern.negated

    def match(self, rel_path: str, is_dir: bool = False) -> Pattern | None:
        """
        Get the pattern that decides the exclusion of a path.

        Args:
            rel_path (str): The path, relative to the root of the tree.
            is_dir (bool): Whether the path is a directory.

        Returns:
            Pattern or None: The last matching pattern, None when no pattern
            matches the path.
        """
        if not self._patterns:
            return None
        path: str = self._normalize(rel_path)
        if not path:
            return None

        components: list[str] = path.split("/")
        last: int = len(components) - 1

        for index in range(len(components)):
            prefix: str = "/".join(components[: index + 1])
            prefix_is_dir: bool = index < last or is_dir
            deciding: Pattern | None = self._deciding(prefix, prefix_is_dir)
            if index < last:
                if deciding is not None and not deciding.negated:
                    # An excluded directory is not walked, so everything
                    # below it is excluded too.
                    return deciding
            else:
                return deciding

        return None

    def applies_to(self, rel_path: str) -> bool:
        """
        Check if a pattern may match something inside the given directory.

        This is used to know if a directory is impacted by the exclusion
        rules, e.g. when a symlink is created for it.

        Args:
            rel_path (str): The path of the directory, relative to the root
                            of the tree.

        Returns:
            bool: True when a pattern may match something inside.
        """
        path: str = self._normalize(rel_path)
        for pattern in self._patterns:
            if pattern.negated:
                # A negation does not exclude anything by itself.
                continue
            scope: str = pattern.scope
            if not scope:
                # The pattern matches at any depth.
                return True
            if (
                path == scope
                or path.startswith(f"{scope}/")
                or scope.startswith(f"{path}/")
            ):
                return True
        return False

    def _deciding(self, path: str, is_dir: bool) -> Pattern | None:
        """
        Get the last pattern matching a path.

        The last matching pattern wins.

        Args:
            path (str): The path, relative to the root of the tree.
            is_dir (bool): Whether the path is a directory.

        Returns:
            Pattern or None: The last matching pattern.
        """
        for pattern in reversed(self._patterns):
            if pattern.matches(path, is_dir):
                return pattern
        return None

    @staticmethod
    def _normalize(rel_path: str) -> str:
        """
        Normalize a path so it can be matched.

        Args:
            rel_path (str): The path, relative to the root of the tree.

        Returns:
            str
        """
        path: str = rel_path.strip()
        while path.startswith("./"):
            path = path[2:]
        return path.strip("/")


def iter_patterns(lines: Iterable[str]) -> Iterator[str]:
    """
    Filter out the empty lines and the comments of a list of patterns.

    Args:
        lines (Iterable[str]): The raw lines.

    Yields:
        str: The lines that may be patterns.
    """
    for line in lines:
        stripped: str = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        yield stripped
