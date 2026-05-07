import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Mock Process Executor for BuildMonitor

/// A mock process executor that returns a sequence of build status responses.
/// Each call to `run` returns the next status in the sequence.
/// This simulates Xcode reporting "running" zero or more times before a terminal status.
actor MockBuildStatusExecutor: ProcessExecuting {
    private let responses: [String]
    private var callIndex: Int = 0

    /// Creates a mock executor with a sequence of status strings to return.
    /// - Parameter responses: Array of status strings (e.g., ["running", "running", "succeeded"]).
    init(responses: [String]) {
        self.responses = responses
    }

    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        let index = callIndex
        callIndex += 1

        // If we've exhausted responses, keep returning "running" (simulates never-ending build)
        let status: String
        if index < responses.count {
            status = responses[index]
        } else {
            status = "running"
        }

        return ProcessOutput(stdout: status + "\n", stderr: "", exitCode: 0)
    }
}

// MARK: - Generators

/// Represents a terminal build status (succeeded or failed).
enum TerminalStatus: CaseIterable {
    case succeeded
    case failed

    var statusString: String {
        switch self {
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        }
    }

    var expectedBuildStatus: BuildStatus {
        switch self {
        case .succeeded: return .succeeded
        case .failed: return .failed
        }
    }
}

/// Generates a sequence of poll responses: zero or more "running" followed by a terminal status.
struct BuildPollSequence: Arbitrary {
    let runningCount: Int
    let terminalStatus: TerminalStatus

    var responses: [String] {
        Array(repeating: "running", count: runningCount) + [terminalStatus.statusString]
    }

    static var arbitrary: Gen<BuildPollSequence> {
        // Generate 0-10 "running" responses before a terminal status
        let runningCountGen = Gen<Int>.fromElements(in: 0...10)
        let terminalGen = Gen<TerminalStatus>.fromElements(of: TerminalStatus.allCases)

        return Gen<BuildPollSequence>.compose { composer in
            let count = composer.generate(using: runningCountGen)
            let terminal = composer.generate(using: terminalGen)
            return BuildPollSequence(runningCount: count, terminalStatus: terminal)
        }
    }
}

/// Generates a sequence that never reaches a terminal status (all "running").
struct TimeoutPollSequence: Arbitrary {
    let runningCount: Int

    var responses: [String] {
        Array(repeating: "running", count: runningCount)
    }

    static var arbitrary: Gen<TimeoutPollSequence> {
        // Generate sequences that are all "running" — the monitor will time out
        Gen<Int>.fromElements(in: 1...20).map { TimeoutPollSequence(runningCount: $0) }
    }
}

// MARK: - Async Helper

/// Helper to run async code synchronously in tests.
private func runAsync<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task {
        do {
            let value = try await block()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}

// MARK: - Property Tests

final class BuildMonitorPropertyTests: XCTestCase {

    // MARK: - Property 5: Build monitor terminates with correct status

    /// Feature: xcode-power, Property 5: Build monitor terminates with correct status
    /// For any sequence of poll responses (zero or more "running" followed by terminal status),
    /// monitor returns the terminal status.
    /// **Validates: Requirements 3.3, 3.6**
    func testProperty5_BuildMonitorTerminatesWithCorrectStatus() {
        property("Feature: xcode-power, Property 5: Build monitor terminates with correct terminal status") <- forAll(BuildPollSequence.arbitrary) { (sequence: BuildPollSequence) in
            let mockExecutor = MockBuildStatusExecutor(responses: sequence.responses)
            let monitor = BuildMonitor(processExecutor: mockExecutor)

            do {
                let status = try runAsync {
                    try await monitor.awaitCompletion(
                        pollInterval: .milliseconds(1),
                        timeout: .seconds(60)
                    )
                }
                return status == sequence.terminalStatus.expectedBuildStatus
            } catch {
                return false
            }
        }
    }

    /// Feature: xcode-power, Property 5: Build monitor returns timedOut for non-terminating sequences
    /// For sequences exceeding timeout without a terminal status, returns "timedOut".
    /// **Validates: Requirements 3.3, 3.6**
    func testProperty5_BuildMonitorTimesOutForNonTerminatingSequences() {
        property("Feature: xcode-power, Property 5: Build monitor returns timedOut when timeout exceeded") <- forAll(TimeoutPollSequence.arbitrary) { (sequence: TimeoutPollSequence) in
            let mockExecutor = MockBuildStatusExecutor(responses: sequence.responses)
            let monitor = BuildMonitor(processExecutor: mockExecutor)

            do {
                let status = try runAsync {
                    // Use a very short timeout so the test doesn't actually wait long
                    try await monitor.awaitCompletion(
                        pollInterval: .milliseconds(1),
                        timeout: .milliseconds(10)
                    )
                }
                return status == .timedOut
            } catch {
                return false
            }
        }
    }
}
