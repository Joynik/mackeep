import Foundation

/// The error of a call to Mackeep.
enum MackeepCommandError: LocalizedError {
    /// The tool cannot be run.
    case cannotRun(path: String, error: Error)

    /// The tool failed.
    case failed(path: String, code: Int32, message: String)

    /// The answer of the tool cannot be read.
    case invalidAnswer(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotRun(path, error):
            "Cannot run \(path): \(error.localizedDescription)"
        case let .failed(path, code, message):
            "\(path) failed with the code \(code): \(message)"
        case let .invalidAnswer(path, message):
            "Cannot read the answer of \(path): \(message)"
        }
    }
}

/// The command line tool of Mackeep.
///
/// The tool is run with an explicit environment: the applications started
/// from the Finder do not inherit the environment of the shell.
struct MackeepCommand: Sendable {
    /// The path of the binary.
    let path: String

    /// The home directory of the user.
    let home: String

    /// The paths of the tools, given to the process.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Create a command.
    ///
    /// - Parameters:
    ///   - path: The path of the binary.
    ///   - home: The home directory of the user.
    init(path: String, home: String = NSHomeDirectory()) {
        self.path = path
        self.home = home
        self.environment = [
            "HOME": home,
            "PATH": Self.searchPaths.joined(separator: ":"),
            "LANG": "en_US.UTF-8",
        ]
    }

    /// The environment of the processes.
    ///
    /// It is explicit: the applications started from the Finder do not
    /// inherit the environment of the shell.
    var environment: [String: String]

    /// The token that can stop the command.
    var cancellation: CommandCancellation?

    /// Run the tool and return what it writes on the standard output.
    ///
    /// - Parameter arguments: The arguments of the command.
    /// - Returns: The output of the command.
    func run(_ arguments: [String]) throws -> String {
        let result: (output: String, error: String, code: Int32) = try execute(arguments)
        guard result.code == 0 else {
            throw MackeepCommandError.failed(
                path: path,
                code: result.code,
                message: result.error.isEmpty ? result.output : result.error
            )
        }
        return result.output
    }

    /// Run the tool and decode its JSON answer.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the command.
    ///   - type: The type of the answer.
    /// - Returns: The answer of the command.
    func runJSON<T: Decodable>(_ arguments: [String], as type: T.Type) throws -> T {
        let output: String = try run(arguments)
        guard let data: Data = output.data(using: .utf8) else {
            throw MackeepCommandError.invalidAnswer(path: path, message: "Not UTF-8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MackeepCommandError.invalidAnswer(
                path: path,
                message: String(describing: error)
            )
        }
    }

    /// Run the tool and give its JSON events as they come.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the command.
    ///   - onEvent: The callback called for every event.
    func streamEvents(
        _ arguments: [String],
        onEvent: (MackeepEvent) -> Void
    ) throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment

        let output: Pipe = Pipe()
        let errors: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = errors

        cancellation?.attach(process)

        do {
            try process.run()
        } catch {
            throw MackeepCommandError.cannotRun(path: path, error: error)
        }

        let handle: FileHandle = output.fileHandleForReading
        var buffer: String = ""
        while true {
            let data: Data = handle.availableData
            if data.isEmpty { break }
            buffer += String(decoding: data, as: UTF8.self)
            var lines: [String] = buffer.components(separatedBy: "\n")
            buffer = lines.popLast() ?? ""
            for line in lines {
                guard let event: MackeepEvent = Self.decodeEvent(line) else { continue }
                onEvent(event)
            }
        }
        if !buffer.isEmpty, let event: MackeepEvent = Self.decodeEvent(buffer) {
            onEvent(event)
        }

        let errorData: Data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        cancellation?.forget()
        guard process.terminationStatus == 0 else {
            throw MackeepCommandError.failed(
                path: path,
                code: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
            )
        }
    }

    /// Stop the tool that is running.
    func terminate() {
        // The processes are terminated by the system when they exit, the
        // cancellation is handled by the caller.
    }

    /// The version of the tool.
    func version() -> String? {
        guard
            let output: String = try? run(["--version"]),
            let index: String.Index = output.firstIndex(of: " ")
        else {
            return nil
        }
        return String(output[output.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The capabilities of the tool.
    ///
    /// The tool is asked what it can do, so an old version of Mackeep, that
    /// has no JSON and no exclusion rules, is detected.
    func capabilities() -> MackeepCapabilities {
        let version: String = self.version() ?? ""
        let supportsJSON: Bool = (try? runJSON(["--json", "config"], as: MackeepConfig.self)) != nil
        var supportsExclusions: Bool = false
        if supportsJSON,
           let output: String = try? run(["--json", "list"]),
           let data: Data = output.data(using: .utf8),
           let object: Any = try? JSONSerialization.jsonObject(with: data),
           let applications: [Any] = object as? [Any],
           let first: [String: Any] = applications.first as? [String: Any]
        {
            supportsExclusions = first["exclude"] != nil
        }
        return MackeepCapabilities(
            version: version,
            supportsJSON: supportsJSON,
            supportsExclusions: supportsExclusions
        )
    }

    // MARK: - Private

    /// Run the tool and collect its output.
    private func execute(
        _ arguments: [String]
    ) throws -> (output: String, error: String, code: Int32) {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment

        let output: Pipe = Pipe()
        let errors: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw MackeepCommandError.cannotRun(path: path, error: error)
        }

        let outputData: Data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData: Data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            String(decoding: outputData, as: UTF8.self),
            String(decoding: errorData, as: UTF8.self),
            process.terminationStatus
        )
    }

    /// Decode a JSON event.
    private static func decodeEvent(_ line: String) -> MackeepEvent? {
        let trimmed: String = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data: Data = trimmed.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MackeepEvent.self, from: data)
    }
}

/// The capabilities of the tool of Mackeep.
struct MackeepCapabilities: Equatable {
    /// The version of the tool.
    let version: String

    /// Whether the tool writes JSON.
    let supportsJSON: Bool

    /// Whether the tool knows the exclusion rules.
    let supportsExclusions: Bool

    /// Whether the tool is recent enough for the application.
    var isSupported: Bool { supportsJSON && supportsExclusions }
}
