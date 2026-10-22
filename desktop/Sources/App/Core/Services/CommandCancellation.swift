import Foundation

/// Serializes launch and cancellation so a stopped task cannot start afterward.
final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private let signal: Int32

    init(signal: Int32 = SIGTERM) { self.signal = signal }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if stopped { throw CancellationError() }
        try process.run()
        self.process = process
    }

    func forget() {
        lock.lock()
        defer { lock.unlock() }
        process = nil
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        if let process, process.isRunning { kill(process.processIdentifier, signal) }
    }
}
