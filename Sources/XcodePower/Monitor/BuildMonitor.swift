import Foundation

/// Actor that polls Xcode's build status until completion or timeout.
/// Uses a `ProcessExecuting` dependency for testability.
actor BuildMonitor {

    /// Default poll interval between status checks.
    static let defaultPollInterval: Duration = .seconds(2)

    /// Default timeout for build/test operations.
    static let defaultTimeout: Duration = .seconds(300)

    /// The injected process executor for running JXA status queries.
    private let processExecutor: ProcessExecuting

    /// Creates a BuildMonitor with the given process executor.
    /// - Parameter processExecutor: The executor used to run osascript commands for status polling.
    init(processExecutor: ProcessExecuting) {
        self.processExecutor = processExecutor
    }

    // MARK: - Public API

    /// Polls build status at the configured interval until a terminal status is detected or timeout is exceeded.
    /// - Parameters:
    ///   - pollInterval: Time between status checks (default 2 seconds).
    ///   - timeout: Maximum wait time (default 300 seconds for builds).
    /// - Returns: The final build status (`.succeeded`, `.failed`, or `.timedOut`).
    func awaitCompletion(
        pollInterval: Duration = BuildMonitor.defaultPollInterval,
        timeout: Duration = BuildMonitor.defaultTimeout
    ) async throws -> BuildStatus {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            let status = try await checkStatus()

            switch status {
            case .succeeded, .failed:
                return status
            case .running:
                // Not yet complete — wait before polling again
                try await Task.sleep(for: pollInterval)
            case .timedOut:
                // Shouldn't be returned by checkStatus, but handle defensively
                return .timedOut
            }
        }

        return .timedOut
    }

    /// Executes a lightweight JXA script to check the current build state.
    /// - Returns: The current build status as reported by Xcode.
    func checkStatus() async throws -> BuildStatus {
        let script = Self.jxaCheckBuildStatus()
        let output = try await processExecutor.run(
            command: "/usr/bin/osascript",
            arguments: ["-l", "JavaScript", "-e", script],
            timeout: .seconds(30)
        )

        return parseBuildStatus(from: output.stdout)
    }

    // MARK: - JXA Script Generation (internal for testing)

    /// Generates a lightweight JXA script to query Xcode's current build state.
    static func jxaCheckBuildStatus() -> String {
        """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];
        var lastBuildResult = workspace.lastBuildResult();
        if (lastBuildResult === "running" || lastBuildResult === undefined) {
            "running";
        } else if (lastBuildResult === "succeeded") {
            "succeeded";
        } else {
            "failed";
        }
        """
    }

    // MARK: - Private Helpers

    /// Parses the stdout from the JXA status script into a `BuildStatus`.
    private func parseBuildStatus(from output: String) -> BuildStatus {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "succeeded":
            return .succeeded
        case "failed":
            return .failed
        case "running":
            return .running
        default:
            // Unknown status treated as still running to allow further polling
            return .running
        }
    }
}
