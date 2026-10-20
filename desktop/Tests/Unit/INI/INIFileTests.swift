import XCTest

@testable import MackeepDesktop

/// The tests of the INI files.
final class INIFileTests: XCTestCase {
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

    func testReadingAFile() throws {
        let url: URL = directory.appendingPathComponent("app.cfg")
        try "[application]\nname = Test App\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        let document: INIDocument = try INIFile.load(from: url)

        XCTAssertEqual(document.value(forKey: "name", inSection: "application"), "Test App")
    }

    func testWritingAFileKeepsThePreviousVersion() throws {
        let url: URL = directory.appendingPathComponent("app.cfg")
        try "[application]\nname = Old\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        var document: INIDocument = try INIFile.load(from: url)
        document.setValue("New", forKey: "name", inSection: "application")
        try INIFile.save(document, to: url)

        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "[application]\nname = New\n"
        )

        let backup: URL = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(
            try String(contentsOf: backup, encoding: .utf8),
            "[application]\nname = Old\n"
        )
    }

    func testWritingAFileDoesNotLeaveAnyTemporaryFile() throws {
        let url: URL = directory.appendingPathComponent("app.cfg")
        let document: INIDocument = INIDocument(text: "[application]\n")
        try INIFile.save(document, to: url)

        let files: [String] = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .sorted()
        XCTAssertEqual(files, ["app.cfg"])
    }

    func testWritingAFileCreatesItsDirectory() throws {
        let url: URL = directory
            .appendingPathComponent("nested")
            .appendingPathComponent("app.cfg")
        let document: INIDocument = INIDocument(text: "[application]\n")

        try INIFile.save(document, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
