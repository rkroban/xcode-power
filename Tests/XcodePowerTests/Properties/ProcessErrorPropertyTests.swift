import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Mock

/// A mock process executor that always throws `jxaExecutionFailed` with configurable stderr and exit code.
struct MockFailingProcessExecutor: ProcessExecuting {
    let stderrContent: String
    let exitCode: Int32

    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        throw XcodePowerError.jxaExecutionFailed(stderr: stderrContent, exitCode: exitCode)
    }
}

// MARK: - Generators

/// Generates non-empty stderr strings.
struct ArbitraryStderr: Arbitrary {
    let value: String

    static var arbitrary: Gen<ArbitraryStderr> {
        return String.arbitrary
            .suchThat { !$0.isEmpty }
            .map { ArbitraryStderr(value: $0) }
    }
}

/// Generates non-zero Int32 exit codes.
struct NonZeroExitCode: Arbitrary {
    let value: Int32

    static var arbitrary: Gen<NonZeroExitCode> {
        return Int32.arbitrary
            .suchThat { $0 != 0 }
            .map { NonZeroExitCode(value: $0) }
    }
}

// MARK: - Throwing async helper

/// Helper to run async throwing code synchronously in tests.
func runAsyncThrowing<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
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

final class ProcessErrorPropertyTests: XCTestCase {

    // MARK: - Property 12: Non-zero JXA exit propagates error

    /// Feature: xcode-power, Property 12: Non-zero JXA exit propagates error
    /// **Validates: Requirements 10.3**
    func testProperty12_NonZeroJXAExitPropagatesError() {
        property("Feature: xcode-power, Property 12: Non-zero JXA exit propagates error") <- forAll(ArbitraryStderr.arbitrary, NonZeroExitCode.arbitrary) { (stderr: ArbitraryStderr, exitCode: NonZeroExitCode) in
            let mockExecutor = MockFailingProcessExecutor(
                stderrContent: stderr.value,
                exitCode: exitCode.value
            )
            let controller = XcodeController(processExecutor: mockExecutor)

            do {
                _ = try runAsyncThrowing {
                    try await controller.executeJXA("some script", timeout: .seconds(5))
                }
                // Should have thrown
                return false
            } catch let error as XcodePowerError {
                switch error {
                case .jxaExecutionFailed(let capturedStderr, let capturedExitCode):
                    return capturedStderr == stderr.value && capturedExitCode == exitCode.value
                default:
                    return false
                }
            } catch {
                return false
            }
        }
    }
}
