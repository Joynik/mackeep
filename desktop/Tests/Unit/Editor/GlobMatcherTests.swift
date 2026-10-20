import XCTest

@testable import MackeepDesktop

/// The tests of the matcher of the exclusion masks.
final class GlobMatcherTests: XCTestCase {
    func testAMaskWithoutSlashMatchesANameAtAnyDepth() {
        let matcher: GlobMatcher = GlobMatcher(patterns: ["*.log"])

        XCTAssertTrue(matcher.matches("app.log"))
        XCTAssertTrue(matcher.matches("a/b/app.log"))
        XCTAssertFalse(matcher.matches("app.txt"))
    }

    func testAMaskWithSlashIsRelativeToTheRoot() {
        let matcher: GlobMatcher = GlobMatcher(patterns: ["app/cache"])

        XCTAssertTrue(matcher.matches("app/cache"))
        XCTAssertFalse(matcher.matches("a/app/cache"))
    }

    func testTheDoubleStarMatchesTheSlashes() {
        let matcher: GlobMatcher = GlobMatcher(patterns: ["**/cache/**"])

        XCTAssertTrue(matcher.matches("a/cache/b"))
        XCTAssertTrue(matcher.matches("cache/b"))
    }

    func testTheQuestionMarkMatchesOneCharacter() {
        let matcher: GlobMatcher = GlobMatcher(patterns: ["file?.txt"])

        XCTAssertTrue(matcher.matches("file1.txt"))
        XCTAssertFalse(matcher.matches("file12.txt"))
    }

    func testAnEmptyMatcherMatchesNothing() {
        let matcher: GlobMatcher = GlobMatcher(patterns: [])

        XCTAssertTrue(matcher.isEmpty)
        XCTAssertFalse(matcher.matches("anything"))
    }

    func testTheFilesOfAFolderAreFound() throws {
        let directory: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("sub"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try "a".write(
            to: directory.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "b".write(
            to: directory.appendingPathComponent("app.log"),
            atomically: true,
            encoding: .utf8
        )
        try "c".write(
            to: directory.appendingPathComponent("sub/app.log"),
            atomically: true,
            encoding: .utf8
        )

        let matcher: GlobMatcher = GlobMatcher(patterns: ["*.log"])
        let files: [String] = matcher.matchingFiles(in: directory)

        XCTAssertEqual(files.sorted(), ["app.log", "sub/app.log"])
    }
}
