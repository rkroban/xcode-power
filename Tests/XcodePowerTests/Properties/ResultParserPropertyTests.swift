import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Generators

/// Generates arbitrary TestCaseStatus values.
extension TestCaseStatus: Arbitrary {
    public static var arbitrary: Gen<TestCaseStatus> {
        Gen<TestCaseStatus>.fromElements(of: [.passed, .failed, .skipped])
    }
}

/// Generates arbitrary TestCaseResult values with realistic data.
struct ArbitraryTestCaseResult: Arbitrary {
    let value: TestCaseResult

    static var arbitrary: Gen<ArbitraryTestCaseResult> {
        let nameGen = Gen<String>.fromElements(of: [
            "testExample", "testLogin", "testLogout", "testFetch",
            "testSave", "testDelete", "testUpdate", "testCreate",
            "testValidation", "testParsing", "testNetwork", "testCache"
        ])
        let classGen = Gen<String>.fromElements(of: [
            "AuthTests", "NetworkTests", "ModelTests", "ViewTests",
            "ServiceTests", "UtilityTests", "ParserTests", "CacheTests"
        ])
        let statusGen = TestCaseStatus.arbitrary
        let durationGen = Gen<Double>.fromElements(in: 0.001...10.0)

        return Gen<ArbitraryTestCaseResult>.compose { composer in
            let name = composer.generate(using: nameGen)
            let className = composer.generate(using: classGen)
            let status = composer.generate(using: statusGen)
            let duration = composer.generate(using: durationGen)

            let failureMessage: String?
            let filePath: String?
            let lineNumber: Int?

            if status == .failed {
                failureMessage = composer.generate(using: Gen<String>.fromElements(of: [
                    "XCTAssertEqual failed: (1) is not equal to (2)",
                    "XCTAssertTrue failed",
                    "XCTAssertNil failed: got Optional(value)",
                    "Asynchronous wait failed: Exceeded timeout"
                ]))
                filePath = composer.generate(using: Gen<String>.fromElements(of: [
                    "/Users/dev/Project/Tests/AuthTests.swift",
                    "/Users/dev/Project/Tests/NetworkTests.swift",
                    "/Users/dev/Project/Tests/ModelTests.swift"
                ]))
                lineNumber = composer.generate(using: Gen<Int>.fromElements(in: 1...500))
            } else {
                failureMessage = nil
                filePath = nil
                lineNumber = nil
            }

            return ArbitraryTestCaseResult(value: TestCaseResult(
                name: name,
                className: className,
                status: status,
                duration: duration,
                failureMessage: failureMessage,
                filePath: filePath,
                lineNumber: lineNumber
            ))
        }
    }
}

/// Generates a non-empty array of arbitrary TestCaseResult values.
struct ArbitraryTestCaseResultArray: Arbitrary {
    let values: [TestCaseResult]

    static var arbitrary: Gen<ArbitraryTestCaseResultArray> {
        // Generate 1-20 test case results
        let countGen = Gen<Int>.fromElements(in: 1...20)

        return Gen<ArbitraryTestCaseResultArray>.compose { composer in
            let count = composer.generate(using: countGen)
            var results: [TestCaseResult] = []
            for _ in 0..<count {
                let arb = composer.generate(using: ArbitraryTestCaseResult.arbitrary)
                results.append(arb.value)
            }
            return ArbitraryTestCaseResultArray(values: results)
        }
    }
}

/// Generates valid xcresulttool-style JSON containing test results in the flat format.
struct ArbitraryXCResultJSON: Arbitrary {
    let testCases: [TestCaseResult]
    let jsonData: Data

    static var arbitrary: Gen<ArbitraryXCResultJSON> {
        return ArbitraryTestCaseResultArray.arbitrary.map { array in
            let testCases = array.values
            let jsonDict = buildXCResultJSON(from: testCases)
            let data = try! JSONSerialization.data(withJSONObject: jsonDict)
            return ArbitraryXCResultJSON(testCases: testCases, jsonData: data)
        }
    }

    /// Builds a simplified xcresulttool JSON structure from test case results.
    private static func buildXCResultJSON(from testCases: [TestCaseResult]) -> [String: Any] {
        let testResults: [[String: Any]] = testCases.map { tc in
            var dict: [String: Any] = [
                "name": tc.name,
                "className": tc.className,
                "status": tc.status == .passed ? "passed" : (tc.status == .failed ? "failed" : "skipped"),
                "duration": tc.duration
            ]
            if let msg = tc.failureMessage {
                dict["failureMessage"] = msg
            }
            if let path = tc.filePath {
                dict["filePath"] = path
            }
            if let line = tc.lineNumber {
                dict["lineNumber"] = line
            }
            return dict
        }

        return ["testResults": testResults]
    }
}

// MARK: - Property Tests

final class ResultParserPropertyTests: XCTestCase {

    // MARK: - Property 7: xcresulttool JSON parsing round-trip

    /// Feature: xcode-power, Property 7: xcresulttool JSON parsing round-trip
    /// For any valid xcresulttool JSON output, parsing into TestResults and serializing back
    /// preserves counts and failure details.
    /// **Validates: Requirements 4.4, 4.5**
    func testProperty7_XCResultJSONParsingRoundTrip() {
        property("Feature: xcode-power, Property 7: xcresulttool JSON parsing preserves counts and failure details") <- forAll(ArbitraryXCResultJSON.arbitrary) { (xcResult: ArbitraryXCResultJSON) in
            let parser = ResultParser(processExecutor: MockNoOpExecutor())

            do {
                let parsedCases = try parser.extractTestCases(from: xcResult.jsonData)
                let aggregated = ResultParser.aggregateResults(from: parsedCases)

                // Verify counts match the original test cases
                let expectedTotal = xcResult.testCases.count
                let expectedPassed = xcResult.testCases.filter { $0.status == .passed }.count
                let expectedFailed = xcResult.testCases.filter { $0.status == .failed }.count

                guard aggregated.totalCount == expectedTotal else { return false }
                guard aggregated.passedCount == expectedPassed else { return false }
                guard aggregated.failedCount == expectedFailed else { return false }

                // Verify failure details are preserved
                let expectedFailures = xcResult.testCases.filter { $0.status == .failed }
                guard aggregated.failures.count == expectedFailures.count else { return false }

                for (failure, expectedCase) in zip(aggregated.failures.sorted(by: { $0.testName < $1.testName }),
                                                    expectedFailures.sorted(by: { "\($0.className)/\($0.name)" < "\($1.className)/\($1.name)" })) {
                    let expectedName = "\(expectedCase.className)/\(expectedCase.name)"
                    guard failure.testName == expectedName else { return false }
                    guard failure.failureMessage == (expectedCase.failureMessage ?? "Test failed") else { return false }
                    guard failure.filePath == expectedCase.filePath else { return false }
                    guard failure.lineNumber == expectedCase.lineNumber else { return false }
                }

                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - Property 8: Test result aggregation correctness

    /// Feature: xcode-power, Property 8: Test result aggregation correctness
    /// For any set of TestCaseResult objects, totalCount equals set size, passedCount equals
    /// passed count, failedCount equals failed count, failures array contains exactly the failed cases.
    /// **Validates: Requirements 4.4, 4.5**
    func testProperty8_TestResultAggregationCorrectness() {
        property("Feature: xcode-power, Property 8: Test result aggregation produces correct counts and failures") <- forAll(ArbitraryTestCaseResultArray.arbitrary) { (array: ArbitraryTestCaseResultArray) in
            let testCases = array.values
            let aggregated = ResultParser.aggregateResults(from: testCases)

            // totalCount equals set size
            guard aggregated.totalCount == testCases.count else { return false }

            // passedCount equals number with status "passed"
            let expectedPassed = testCases.filter { $0.status == .passed }.count
            guard aggregated.passedCount == expectedPassed else { return false }

            // failedCount equals number with status "failed"
            let expectedFailed = testCases.filter { $0.status == .failed }.count
            guard aggregated.failedCount == expectedFailed else { return false }

            // failures array contains exactly the failed test cases
            guard aggregated.failures.count == expectedFailed else { return false }

            // Each failure corresponds to a failed test case
            let failedCases = testCases.filter { $0.status == .failed }
            let failureNames = Set(aggregated.failures.map { $0.testName })
            let expectedNames = Set(failedCases.map { "\($0.className)/\($0.name)" })
            guard failureNames == expectedNames else { return false }

            return true
        }
    }
}

// MARK: - Mock Executor for ResultParser tests

/// A no-op process executor used when we don't need actual process execution.
private struct MockNoOpExecutor: ProcessExecuting {
    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        return ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }
}
