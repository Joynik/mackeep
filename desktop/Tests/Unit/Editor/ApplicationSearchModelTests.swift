import XCTest

@testable import MackeepDesktop

/// The tests of the search of the files of an application.
final class ApplicationSearchModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Write a file in the test folder.
    @discardableResult
    private func write(_ name: String, in folder: URL? = nil) throws -> URL {
        let target: URL = folder ?? directory
        let url: URL = target.appendingPathComponent(name)
        try "content".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testTheFilesAreFound() throws {
        _ = try write("config.yml")
        _ = try write("notes.txt")

        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "",
            known: []
        )

        // The folder itself is a file of the application
        XCTAssertEqual(
            found.map(\.url.lastPathComponent).sorted(),
            ["config.yml", directory.lastPathComponent, "notes.txt"]
        )
    }

    func testTheFilesThatMatchTheTextAreFound() throws {
        _ = try write("config.yml")
        _ = try write("notes.txt")

        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "conf",
            known: []
        )

        XCTAssertEqual(found.map(\.url.lastPathComponent), ["config.yml"])
    }

    func testTheFilesThatAreAlreadyKnownAreSkipped() throws {
        _ = try write("config.yml")
        _ = try write("notes.txt")

        let known: Set<String> = [
            "home:" + directory.appendingPathComponent("config.yml").path
        ]
        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "",
            known: known
        )

        XCTAssertEqual(
            found.map(\.url.lastPathComponent).filter { $0 != directory.lastPathComponent },
            ["notes.txt"]
        )
    }

    func testTheFoldersAreFound() throws {
        let folder: URL = directory.appendingPathComponent("sub")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        _ = try write("inside.txt", in: folder)

        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "",
            known: []
        )

        XCTAssertTrue(found.contains { $0.url.lastPathComponent == "sub" })
        XCTAssertTrue(found.contains { $0.isDirectory })
        XCTAssertTrue(found.contains { $0.url.lastPathComponent == "inside.txt" })
    }

    func testTheSizeOfTheFilesIsKnown() throws {
        _ = try write("config.yml")

        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "",
            known: []
        )
        let file: FoundFile? = found.first { $0.url.lastPathComponent == "config.yml" }

        XCTAssertEqual(file?.size, 7)
        XCTAssertFalse(file?.sizeText.isEmpty ?? true)
    }

    func testTheHiddenFilesAreFound() throws {
        _ = try write(".hidden.yml")
        _ = try write("visible.yml")

        let found: [FoundFile] = ApplicationSearchModel.find(
            in: [directory],
            matching: "",
            known: []
        )

        let names: [String] = found.map(\.url.lastPathComponent)
        XCTAssertTrue(names.contains(".hidden.yml"))
        XCTAssertTrue(names.contains("visible.yml"))
    }

    func testTheFilesOfTheHomeFolderAreFound() throws {
        // A folder that is named after the application, in the home directory
        let home: URL = ApplicationSearchModel.home
        let folder: URL = home.appendingPathComponent(".mackeep-demo-app")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        _ = try write("data.yml", in: folder)

        let found: [FoundFile] = ApplicationSearchModel.homeFiles(
            named: ["mackeep-demo-app"],
            matching: "",
            known: []
        )

        XCTAssertTrue(
            found.contains { $0.url.lastPathComponent == "data.yml" }
        )
    }

    func testTheStandardPlacesOfAnApplication() {
        let places: [URL] = ApplicationSearchModel.standardPlaces(named: "AnyDesk")
        let paths: [String] = places.map(\.path)

        XCTAssertTrue(
            paths.contains { $0.hasSuffix("Library/Application Support/AnyDesk") }
        )
        XCTAssertTrue(paths.contains { $0.hasSuffix(".config/AnyDesk") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("Library/Logs/AnyDesk") })
        // The cache is not worth being backed up
        XCTAssertFalse(paths.contains { $0.hasSuffix("Library/Caches/AnyDesk") })
    }

    func testSpotlightResultsAreFilteredAndDeduplicated() throws {
        let home = ApplicationSearchModel.home.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let expected = try write("Mackeep config", in: home)
        let known = try write("Mackeep known", in: home)
        let other = try write("unrelated", in: home)
        let outside = try write("Mackeep outside")
        var queries: [String] = []
        let found = ApplicationSearchModel.spotlightSearch(
            names: ["Mackeep", "Mackeep"], matching: "Mackeep",
            known: ["home:" + home.lastPathComponent + "/Mackeep known"],
            query: { query, _ in
                queries.append(query)
                return [expected.path, outside.path, expected.path, known.path, other.path]
            })
        XCTAssertEqual(queries, Array(repeating: "kMDItemFSName == '*Mackeep*'c", count: 2))
        XCTAssertEqual(found.map(\.url), [expected])
        XCTAssertEqual(found.first?.size, 7)
    }
}
