import Foundation

/// Protocol for controlling Xcode via JXA scripting.
/// Enables dependency injection for testing without requiring a running Xcode instance.
protocol XcodeControlling: Sendable {
    /// Checks if Xcode.app is currently running.
    /// - Returns: `true` if Xcode is running, `false` otherwise.
    func isXcodeRunning() async throws -> Bool

    /// Checks if a project or workspace document is open in Xcode.
    /// - Returns: `true` if a project or workspace is open, `false` otherwise.
    func hasOpenProject() async throws -> Bool

    /// Executes a JXA (JavaScript for Automation) script against Xcode.
    /// - Parameters:
    ///   - script: The JXA script to execute.
    ///   - timeout: The maximum duration to wait for the script to complete.
    /// - Returns: The stdout output from the script execution.
    /// - Throws: `XcodePowerError.jxaExecutionFailed` if the script exits with non-zero status.
    func executeJXA(_ script: String, timeout: Duration) async throws -> String
}
