import XCTest

/// Yield the main actor while waiting, but never turn a failed operation into a hung suite.
@MainActor
func waitUntil(
    _ description: String, timeout: Duration = .seconds(10),
    file: StaticString = #filePath, line: UInt = #line,
    condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            XCTFail("Timed out: \(description)", file: file, line: line)
            throw NSError(domain: "MackeepTests.Timeout", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: description])
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
