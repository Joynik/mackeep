import XCTest

@testable import MackeepDesktop

/// The tests of the command line tool of Mackeep.
final class MackeepCommandTests: XCTestCase {
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

    /// The directory of the fixtures of the tests.
    static var fixtureDirectory: String {
        guard let url: URL = Bundle(for: Self.self).url(
            forResource: "config",
            withExtension: "json"
        ) else {
            return ""
        }
        return url.deletingLastPathComponent().path
    }

    /// Write a fake tool and return its path.
    private func makeTool(_ script: String) throws -> String {
        let url: URL = directory.appendingPathComponent("mackeep-cli")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url.path
    }

    func testTheOutputOfTheToolIsRead() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo "hello $1"
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")

        let output: String = try command.run(["--version"])

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "hello --version")
    }

    func testTheEnvironmentOfTheToolIsExplicit() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo "HOME=$HOME"
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp/mackeep-home")

        let output: String = try command.run([])

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "HOME=/tmp/mackeep-home")
        XCTAssertEqual(command.environment["HOME"], "/tmp/mackeep-home")
        XCTAssertTrue(command.environment["PATH"]?.contains("/opt/homebrew/bin") ?? false)
    }

    func testAFailingToolGivesAnError() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo "boom" >&2
            exit 3
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")

        XCTAssertThrowsError(try command.run([])) { error in
            guard let error = error as? MackeepCommandError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue("\(error)".contains("boom"))
        }
    }

    func testTheJSONAnswerIsDecoded() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo '{"schema_version": 4, "version": "1.2.3"}'
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")

        struct Answer: Decodable {
            let schemaVersion: Int
            let version: String

            enum CodingKeys: String, CodingKey {
                case schemaVersion = "schema_version"
                case version
            }
        }

        let answer: Answer = try command.runJSON(["--json", "config"], as: Answer.self)

        XCTAssertEqual(answer.version, "1.2.3")
    }

    func testTheEventsAreStreamed() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo '{"schema_version": 4, "event": "start", "app": "demo"}'
            echo '{"schema_version": 4, "event": "file", "app": "demo", "size_bytes": 7}'
            echo '{"schema_version": 4, "event": "done", "app": "demo", "files": 1, "bytes": 7, "skipped": 0}'
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")
        var events: [MackeepEvent] = []

        try command.streamEvents(["--json", "backup"]) { event in
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].event, "start")
        XCTAssertEqual(events[1].sizeBytes, 7)
        XCTAssertEqual(events[2].files, 1)
    }

    func testTheVersionOfTheToolIsRead() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            echo "Mackeep 0.15.1"
            """
        )
        let command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")

        XCTAssertEqual(command.version(), "0.15.1")
    }

    func testTheCapabilitiesOfAnOldToolAreDetected() throws {
        // A tool without JSON
        let old: String = try makeTool(
            """
            #!/bin/sh
            echo "Mackeep 0.12.1"
            """
        )
        let oldCommand: MackeepCommand = MackeepCommand(path: old, home: "/tmp")
        let oldCapabilities: MackeepCapabilities = oldCommand.capabilities()

        XCTAssertEqual(oldCapabilities.version, "0.12.1")
        XCTAssertFalse(oldCapabilities.supportsJSON)
        XCTAssertFalse(oldCapabilities.supportsExclusions)
        XCTAssertFalse(oldCapabilities.isSupported)
    }

    func testTheCapabilitiesOfANewToolAreDetected() throws {
        let path: String = try makeTool(
            """
            #!/bin/sh
            if [ "$2" = "config" ]; then
              cat "$FIXTURE_DIR/config.json"
              exit 0
            fi
            if [ "$2" = "list" ]; then
              cat "$FIXTURE_DIR/list.json"
              exit 0
            fi
            echo "Mackeep 0.15.1"
            """
        )
        var command: MackeepCommand = MackeepCommand(path: path, home: "/tmp")
        command.environment["FIXTURE_DIR"] = Self.fixtureDirectory
        let capabilities: MackeepCapabilities = command.capabilities()

        XCTAssertEqual(capabilities.version, "0.15.1")
        XCTAssertTrue(capabilities.supportsJSON)
        XCTAssertTrue(capabilities.supportsExclusions)
        XCTAssertTrue(capabilities.isSupported)
    }

    func testTheBinaryIsFoundInTheKnownPaths() throws {
        let path: String = try makeTool("#!/bin/sh\necho ok\n")

        XCTAssertTrue(MackeepDiscovery.isExecutable(path))
        XCTAssertFalse(MackeepDiscovery.isExecutable(directory.path))
        XCTAssertFalse(MackeepDiscovery.isExecutable("/does/not/exist"))
    }

    func testTheManualPathOfTheBinaryHasThePriority() throws {
        let path: String = try makeTool("#!/bin/sh\necho ok\n")

        XCTAssertEqual(MackeepDiscovery.find(manualPath: path), path)
            // An unknown path falls back to the known directories
        XCTAssertNotEqual(
            MackeepDiscovery.find(manualPath: "/does/not/exist/mackeep-cli"),
            "/does/not/exist/mackeep-cli"
        )
    }
    func testBothPipesAreDrainedWithoutDeadlock() throws {
        let path = try makeTool("#!/bin/sh\nhead -c 262144 /dev/zero >&2\necho ok\n")
        XCTAssertEqual(
            try MackeepCommand(path: path).run([]).trimmingCharacters(in: .whitespacesAndNewlines),
            "ok")
    }

    func testMalformedAndIncompleteStreamsAreRejected() throws {
        for text in [
            "not-json", "{\"schema_version\":4,\"event\":\"start\",\"app\":\"demo\"}",
            "{\"schema_version\":99,\"event\":\"done\",\"app\":\"demo\"}",
        ] {
            let path = try makeTool("#!/bin/sh\nprintf '%s\\n' '\(text)'\n")
            XCTAssertThrowsError(try MackeepCommand(path: path).streamEvents([]) { _ in })
        }
    }

    func testExplicitEmptySelectionAllowsAnEmptyStream() throws {
        let path = try makeTool("#!/bin/sh\nexit 0\n")
        let command = MackeepCommand(path: path)
        XCTAssertThrowsError(try command.streamEvents([]) { _ in })
        XCTAssertNoThrow(try command.streamEvents([], allowEmpty: true) { _ in })
    }

    func testCancellationBeforeLaunchDoesNotExecuteTheTool() throws {
        let marker = directory.appendingPathComponent("started")
        let path = try makeTool("#!/bin/sh\ntouch '\(marker.path)'\n")
        var command = MackeepCommand(path: path)
        let token = CommandCancellation()
        token.cancel()
        command.cancellation = token
        XCTAssertThrowsError(try command.run([]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testSplitUTF8EventIsDecodedAfterTheLineIsComplete() throws {
        let path = try makeTool(
            """
            #!/bin/sh
            echo '{"schema_version":4,"event":"start","app":"demo"}'
            printf '%s' '{"schema_version":4,"event":"file","app":"demo","src":"'
            printf '\\303'
            sleep 0.05
            printf '\\251"}\\n'
            echo '{"schema_version":4,"event":"done","app":"demo"}'
            """)
        var names: [String] = []
        try MackeepCommand(path: path).streamEvents([]) { event in
            if let src = event.src { names.append(src) }
        }
        XCTAssertEqual(names, ["é"])
    }

}
