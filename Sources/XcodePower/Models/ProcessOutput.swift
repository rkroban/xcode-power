import Foundation

/// The output captured from a process execution.
struct ProcessOutput: Sendable {
    /// The standard output from the process.
    let stdout: String

    /// The standard error from the process.
    let stderr: String

    /// The exit code of the process.
    let exitCode: Int32
}
