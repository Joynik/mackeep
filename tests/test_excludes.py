"""Tests for the gitignore-like exclusion matcher."""

from mackup.excludes import Matcher


def test_empty_matcher_excludes_nothing():
    matcher = Matcher()
    assert not matcher
    assert len(matcher) == 0
    assert not matcher.is_excluded("anything")
    assert not matcher.is_excluded("a/b/c.txt")


def test_matcher_is_falsy_with_patterns():
    assert Matcher(["*.log"])


def test_exact_file_name_is_excluded():
    matcher = Matcher([".DS_Store"])
    assert matcher.is_excluded(".DS_Store")
    assert not matcher.is_excluded(".DS_Store2")
    assert matcher.is_excluded("sub/.DS_Store")


def test_exact_name_matches_at_any_depth():
    matcher = Matcher([".DS_Store"])
    assert matcher.is_excluded("a/b/.DS_Store")
    assert matcher.is_excluded(".DS_Store")


def test_exact_path_is_relative_to_the_root():
    matcher = Matcher(["Library/Application Support/Code/User"])
    assert matcher.is_excluded("Library/Application Support/Code/User")
    assert not matcher.is_excluded("Code/User")
    assert not matcher.is_excluded("other/Library/Application Support/Code/User")


def test_leading_slash_anchors_the_pattern():
    matcher = Matcher(["/Library/Caches"])
    assert matcher.is_excluded("Library/Caches")
    assert not matcher.is_excluded("foo/Library/Caches")


def test_star_matches_within_a_component():
    matcher = Matcher(["*.log"])
    assert matcher.is_excluded("app.log")
    assert matcher.is_excluded("deep/dir/app.log")
    assert not matcher.is_excluded("app.txt")


def test_star_does_not_match_a_slash():
    matcher = Matcher(["a*b"])
    assert matcher.is_excluded("axxb")
    assert not matcher.is_excluded("a/xb")


def test_question_mark_matches_a_single_character():
    matcher = Matcher(["file?.txt"])
    assert matcher.is_excluded("file1.txt")
    assert not matcher.is_excluded("file12.txt")
    assert not matcher.is_excluded("file.txt")


def test_question_mark_does_not_match_a_slash():
    matcher = Matcher(["a?c"])
    assert matcher.is_excluded("abc")
    assert not matcher.is_excluded("a/c")


def test_double_star_matches_across_slashes():
    matcher = Matcher(["**/target/debug"])
    assert matcher.is_excluded("target/debug")
    assert matcher.is_excluded("a/target/debug")
    assert matcher.is_excluded("a/b/target/debug")


def test_double_star_at_the_end_matches_everything_below():
    matcher = Matcher(["globalStorage/**"])
    assert matcher.is_excluded("globalStorage/state.json")
    assert matcher.is_excluded("globalStorage/a/b.json")
    assert not matcher.is_excluded("globalStorage")


def test_double_star_only_matches_files():
    matcher = Matcher(["**/*.log"])
    assert matcher.is_excluded("a/b/app.log")
    assert matcher.is_excluded("app.log")


def test_trailing_slash_only_matches_directories():
    matcher = Matcher(["cache/"])
    assert matcher.is_excluded("cache", True)
    assert not matcher.is_excluded("cache", False)


def test_trailing_slash_excludes_the_content_of_the_directory():
    matcher = Matcher(["cache/"])
    assert matcher.is_excluded("cache/file.txt")
    assert matcher.is_excluded("cache/file.txt", False)


def test_negation_re_includes_a_file():
    matcher = Matcher(["*.log", "!keep.log"])
    assert matcher.is_excluded("app.log")
    assert not matcher.is_excluded("keep.log")


def test_negation_can_re_include_a_file_in_a_subdirectory():
    matcher = Matcher(["*.log", "!logs/keep.log"])
    assert matcher.is_excluded("logs/app.log")
    assert not matcher.is_excluded("logs/keep.log")


def test_the_last_matching_pattern_wins():
    matcher = Matcher(["*.log", "!keep.log", "keep.log"])
    assert matcher.is_excluded("keep.log")


def test_a_negated_pattern_alone_excludes_nothing():
    matcher = Matcher(["!keep.log"])
    assert not matcher.is_excluded("keep.log")
    assert not matcher.is_excluded("app.log")


def test_a_negation_does_not_re_include_inside_an_excluded_directory():
    matcher = Matcher(["logs/", "!logs/keep.log"])
    assert matcher.is_excluded("logs/keep.log")


def test_excluded_directory_excludes_everything_below():
    matcher = Matcher(["node_modules"])
    assert matcher.is_excluded("node_modules")
    assert matcher.is_excluded("node_modules/pkg/index.js")


def test_matching_is_case_sensitive():
    matcher = Matcher([".DS_Store"])
    assert matcher.is_excluded(".DS_Store")
    assert not matcher.is_excluded(".ds_store")


def test_paths_with_spaces_are_supported():
    matcher = Matcher(["Library/Application Support/Code/User/workspaceStorage"])
    assert matcher.is_excluded("Library/Application Support/Code/User/workspaceStorage")
    assert matcher.is_excluded(
        "Library/Application Support/Code/User/workspaceStorage/state.db",
    )
    assert not matcher.is_excluded("Library/Application Support/Code/User")


def test_paths_with_unicode_are_supported():
    matcher = Matcher(["Кэш/файл.txt", "données/*.csv"])
    assert matcher.is_excluded("Кэш/файл.txt")
    assert matcher.is_excluded("données/rapport.csv")
    assert not matcher.is_excluded("données/rapport.pdf")


def test_unicode_pattern_matches_at_any_depth():
    matcher = Matcher(["*.缓存"])
    assert matcher.is_excluded("a/b/文件.缓存")


def test_comments_and_empty_lines_are_ignored():
    matcher = Matcher(["# a comment", "", "   ", "; another comment", "*.log"])
    assert len(matcher) == 1
    assert matcher.is_excluded("app.log")


def test_patterns_are_trimmed():
    matcher = Matcher(["  *.log  "])
    assert matcher.is_excluded("app.log")


def test_the_matcher_keeps_its_raw_patterns():
    matcher = Matcher(["*.log", "!keep.log"])
    assert matcher.patterns == ("*.log", "!keep.log")


def test_extended_returns_a_new_matcher():
    matcher = Matcher(["*.log"])
    extended = matcher.extended(["*.txt"])
    assert matcher.is_excluded("app.log")
    assert not matcher.is_excluded("app.txt")
    assert extended.is_excluded("app.log")
    assert extended.is_excluded("app.txt")
    assert matcher is not extended


def test_extended_keeps_the_order_of_the_patterns():
    matcher = Matcher(["*.log"])
    extended = matcher.extended(["!keep.log"])
    assert extended.is_excluded("app.log")
    assert not extended.is_excluded("keep.log")


def test_applies_to_detects_an_anchored_scope():
    matcher = Matcher(["Library/Application Support/Code/User/workspaceStorage"])
    assert matcher.applies_to("Library/Application Support/Code/User")
    assert matcher.applies_to("Library/Application Support/Code/User/workspaceStorage")
    assert matcher.applies_to("Library/Application Support/Code")
    assert not matcher.applies_to("Library/Application Support/Code/User/settings")


def test_applies_to_detects_a_name_pattern():
    matcher = Matcher(["*.log"])
    assert matcher.applies_to("any/folder")


def test_applies_to_ignores_negated_patterns():
    matcher = Matcher(["!*.log"])
    assert not matcher.applies_to("any/folder")


def test_applies_to_is_false_without_pattern():
    assert not Matcher().applies_to("any/folder")


def test_a_directory_pattern_matches_the_files_it_contains():
    matcher = Matcher(["cache/"])
    assert matcher.is_excluded("cache", True)
    assert matcher.is_excluded("cache/sub/file")
    assert not matcher.is_excluded("cache", False)


def test_a_pattern_may_match_a_file_or_a_directory():
    matcher = Matcher(["build"])
    assert matcher.is_excluded("build", True)
    assert matcher.is_excluded("build", False)


def test_the_root_of_the_tree_is_never_excluded():
    matcher = Matcher(["**"])
    assert not matcher.is_excluded("")
    assert not matcher.is_excluded("/")


def test_paths_are_normalized():
    matcher = Matcher(["app.log"])
    assert matcher.is_excluded("./app.log")
    assert matcher.is_excluded("/app.log")
    assert matcher.is_excluded("app.log")


def test_a_pattern_with_a_dot_is_matched_literally():
    matcher = Matcher(["config.json"])
    assert matcher.is_excluded("config.json")
    assert not matcher.is_excluded("configXjson")


def test_a_pattern_may_be_escaped():
    matcher = Matcher(["\\!important"])
    assert matcher.is_excluded("!important")
    assert not matcher.is_excluded("important")
