import XCTest

@testable import MackeepDesktop

final class MackeepDiagnosticsTests: XCTestCase {
    func testInvalidDiagnosticEncodingStillReportsTheProcessFailure() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mackeep-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tool = directory.appendingPathComponent("cli")
        try "#!/bin/sh\nprintf '\\377' >&2\nexit 7\n".write(
            to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let command = MackeepCommand(path: tool.path, home: directory.path)
        XCTAssertThrowsError(try command.run(["--version"])) { error in
            guard case MackeepCommandError.failed(_, let code, let message) = error else {
                XCTFail("Expected the process failure, got \(error)")
                return
            }
            XCTAssertEqual(code, 7)
            XCTAssertEqual(message, "Command diagnostics are not UTF-8.")
        }
    }
}
