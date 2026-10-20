import Foundation

/// The token of a command that can be stopped.
final class CommandCancellation: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var process: Process?
    private var stopped: Bool = false

    /// Whether the command was stopped.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Follow the process of the command.
    ///
    /// - Parameter process: The process.
    func attach(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        if stopped { process.terminate() }
    }

    /// The command was stopped.
    func forget() {
        lock.lock()
        defer { lock.unlock() }
        process = nil
    }

    /// Stop the command.
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        process?.terminate()
    }
}
