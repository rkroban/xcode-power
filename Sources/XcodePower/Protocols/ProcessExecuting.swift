import Foundation

/// Protocol for executing system processes with timeout support.
/// Enables dependency injection for testing without spawning real processes.
protocol ProcessExecuting: Sendable {
    /// Runs a command with the given arguments and timeout.
    /// - Parameters:
    ///   - command: The executable path or name to run.
    ///   - arguments: The arguments to pass to the command.
    ///   - timeout: The maximum duration to wait for the process to complete.
    /// - Returns: The captured process output including stdout, stderr, and exit code.
    /// - Throws: An error if the process times out or cannot be started.
    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput
}
