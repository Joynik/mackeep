import XCTest

@testable import MackeepDesktop

/// The tests of the parser against the config files of Mackeep.
final class INICompatibilityTests: XCTestCase {
    /// The directory of the repository.
    static var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // INI
            .deletingLastPathComponent()  // Unit
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // desktop
            .deletingLastPathComponent()  // the repository
    }

    /// The config files of the applications of Mackeep.
    static var applicationConfigs: [URL] {
        let directory: URL = repository
            .appendingPathComponent("src")
            .appendingPathComponent("mackeep")
            .appendingPathComponent("applications")
        return (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "cfg" } ?? []
    }

    func testTheConfigFilesOfTheApplicationsAreReadWithoutLoss() throws {
        let configs: [URL] = Self.applicationConfigs
        XCTAssertGreaterThan(configs.count, 500)

        for url in configs {
            let text: String = try String(contentsOf: url, encoding: .utf8)
            let document: INIDocument = INIDocument(text: text)

            // The file is written back the way it was read
            XCTAssertEqual(document.text, text, "The file \(url.lastPathComponent) is not lossless")

            // The name of the application is there
            XCTAssertFalse(
                document.value(forKey: "name", inSection: "application")?.isEmpty ?? true,
                "The file \(url.lastPathComponent) has no name"
            )
        }
    }

    func testTheConfigFilesOfTheApplicationsHavePaths() throws {
        for url in Self.applicationConfigs {
            let document: INIDocument = try INIFile.load(from: url)
            let paths: [String] =
                document.values(inSection: "configuration_files")
                + document.values(inSection: "xdg_configuration_files")
            XCTAssertFalse(
                paths.isEmpty,
                "The file \(url.lastPathComponent) has no path"
            )
            for path in paths {
                XCTAssertFalse(
                    path.hasPrefix("/"),
                    "The path \(path) of \(url.lastPathComponent) is absolute"
                )
            }
        }
    }
}
