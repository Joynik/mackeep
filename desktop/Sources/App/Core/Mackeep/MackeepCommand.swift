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
    init(path: String, home: String = EditorPath.homeDirectory.path, xdgHome: String? = nil) {
        self.path = path
        self.home = home
        self.environment = [
            "HOME": home,
            "PATH": Self.searchPaths.joined(separator: ":"),
            "LANG": "en_US.UTF-8",
            "XDG_CONFIG_HOME": xdgHome
                ?? (home == EditorPath.homeDirectory.path
                    ? EditorPath.xdgDirectory.path
                    : URL(fileURLWithPath: home).appendingPathComponent(".config").path)
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
        try checkStatus(result)
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
            let object = try JSONSerialization.jsonObject(with: data)
            let objects =
                (object as? [[String: Any]]) ?? (object as? [String: Any]).map { [$0] } ?? []
            for object in objects {
                guard object["schema_version"] as? Int == MackeepSchema.version else {
                    throw MackeepCommandError.invalidAnswer(
                        path: path, message: "Unsupported JSON schema")
                }
            }
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
        allowEmpty: Bool = false,
        onEvent: @escaping (MackeepEvent) -> Void
    ) throws {
        var buffer = Data()
        var invalid: String?
        var active: Set<String> = []
        var completed = 0
        var sawError = false
        func consume(_ data: Data) {
            guard !data.isEmpty, invalid == nil else { return }
            do {
                let event = try JSONDecoder().decode(MackeepEvent.self, from: data)
                guard event.schemaVersion == MackeepSchema.version else {
                    throw MackeepCommandError.invalidAnswer(
                        path: path, message: "Unsupported event schema")
                }
                switch event.event {
                case "start":
                    guard let app = event.app, active.insert(app).inserted else {
                        throw MackeepCommandError.invalidAnswer(
                            path: path, message: "Invalid application start")
                    }
                case "done":
                    guard let app = event.app, active.remove(app) != nil else {
                        throw MackeepCommandError.invalidAnswer(
                            path: path, message: "Completion without start")
                    }
                    completed += 1
                case "error": sawError = true
                case "file", "skip": break
                default:
                    throw MackeepCommandError.invalidAnswer(
                        path: path, message: "Unknown event: \(event.event)")
                }
                onEvent(event)
            } catch {
                struct Failure: Decodable { let error: MackeepError }
                invalid =
                    (try? JSONDecoder().decode(Failure.self, from: data))?.error.message
                    ?? error.localizedDescription
            }
        }
        let result = try execute(arguments) { chunk in
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                consume(Data(buffer[..<newline]))
                buffer.removeSubrange(...newline)
            }
        }
        consume(buffer)
        if result.code != 0, result.error.isEmpty, let invalid {
            throw MackeepCommandError.failed(path: path, code: result.code, message: invalid)
        }
        try checkStatus(result)
        if let invalid { throw MackeepCommandError.invalidAnswer(path: path, message: invalid) }
        guard active.isEmpty, !sawError, completed > 0 || allowEmpty else {
            throw MackeepCommandError.invalidAnswer(
                path: path, message: "Missing successful completion")
        }
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
        let config = try? runJSON(["--json", "config"], as: MackeepConfig.self)
        return MackeepCapabilities(
            version: config?.version ?? version() ?? "",
            supportsJSON: config != nil,
            supportsExclusions: config?.schemaVersion == MackeepSchema.version
        )
    }

    // MARK: - Private

    /// Run the tool and collect its output.
    /// Both pipes must be drained while the child is running.
    private func execute(
        _ arguments: [String],
        onOutput: ((Data) -> Void)? = nil
    ) throws -> (output: String, error: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            if let cancellation { try cancellation.launch(process) } else { try process.run() }
        } catch is CancellationError { throw CancellationError() } catch {
            throw MackeepCommandError.cannotRun(path: path, error: error)
        }
        defer { cancellation?.forget() }
        let diagnostics = PipeData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            diagnostics.data = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if let onOutput { onOutput(chunk) } else { data.append(chunk) }
        }
        process.waitUntilExit()
        group.wait()
        if cancellation?.isCancelled == true { throw CancellationError() }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MackeepCommandError.invalidAnswer(path: path, message: "Output is not UTF-8")
        }
        return (text, String(decoding: diagnostics.data, as: UTF8.self), process.terminationStatus)
    }

    /// Read only after the dispatch group has synchronized the pipe reader.
    private final class PipeData: @unchecked Sendable { var data = Data() }

    private func checkStatus(_ result: (output: String, error: String, code: Int32)) throws {
        if result.code != 0 {
            throw MackeepCommandError.failed(
                path: path, code: result.code,
                message: result.error.isEmpty ? result.output : result.error)
        }
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
