import Foundation

/// Errors that can occur during Xcode Power operations.
enum XcodePowerError: Error, Sendable {
    /// Xcode.app is not currently running.
    case xcodeNotRunning

    /// No project or workspace is open in Xcode.
    case noProjectOpen

    /// Xcode did not respond within the specified timeout.
    case xcodeUnresponsive(timeout: Duration)

    /// A build operation exceeded the maximum allowed duration.
    case buildTimeout(maxDuration: Duration)

    /// A JXA script execution failed with a non-zero exit code.
    case jxaExecutionFailed(stderr: String, exitCode: Int32)

    /// No .xcresult bundle was found at the expected location.
    case xcresultNotFound(searchPath: String)

    /// Failed to parse the contents of an .xcresult bundle.
    case xcresultParsingFailed(reason: String)

    /// Invalid arguments were provided to a tool call.
    case invalidToolArguments(message: String)
}
