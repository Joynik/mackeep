"""Behavior and work bounds for CLI optimizations."""

from unittest.mock import patch

from mackeep.application import ApplicationProfile
from mackeep.excludes import Matcher
from mackeep.mackeep import Mackeep


def test_no_exclusions_need_no_directory_scan(home):
    """Link checks and restore preservation need no scan without any rules."""
    profile = ApplicationProfile(Mackeep(read_only=True), set(), True, False)
    existing = home / "existing"
    existing.mkdir()
    (existing / "preferences").write_text("keep")
    with patch("mackeep.application.os.listdir") as listing:
        assert not profile._contains_excluded(str(existing), "existing")  # noqa: SLF001
        profile._preserve_local_exclusions(  # noqa: SLF001
            str(existing), str(home / "staged"), "existing",
        )
        listing.assert_not_called()


def test_last_match_search_preserves_forward_reference():
    """The winning rule and its metadata must match a forward scan."""
    rule_sets = [
        [], ["*.log", "!keep.log"], ["cache/", "!cache/keep.log"],
        ["**/*.log", "!app/**", "app/private/**"],
        ["/app/cache/", "!app/cache/", "app/cache/private"],
    ]
    for rules in rule_sets:
        matcher = Matcher(rules)
        for path in ("app.log", "keep.log", "cache", "cache/keep.log",
                     "app/cache/private/file", "app/private/file.log"):
            for is_dir in (False, True):
                expected = None
                components = path.split("/")
                for index in range(len(components)):
                    prefix = "/".join(components[:index + 1])
                    directory = index < len(components) - 1 or is_dir
                    deciding = None
                    for pattern in matcher._patterns:  # noqa: SLF001
                        if pattern.matches(prefix, directory):
                            deciding = pattern
                    if index == len(components) - 1 or (
                        deciding is not None and not deciding.negated
                    ):
                        expected = deciding
                        break
                assert matcher.match(path, is_dir) == expected
