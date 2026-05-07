import Foundation

/// Aggregated test results from a test run.
struct TestResults: Codable, Sendable {
    let totalCount: Int
    let passedCount: Int
    let failedCount: Int
    let failures: [TestFailure]
}

/// Details of a single test failure.
struct TestFailure: Codable, Sendable {
    let testName: String
    let failureMessage: String
    let filePath: String?
    let lineNumber: Int?
}

/// The result of an individual test case.
struct TestCaseResult: Codable, Sendable {
    let name: String
    let className: String
    let status: TestCaseStatus
    let duration: Double
    let failureMessage: String?
    let filePath: String?
    let lineNumber: Int?
}

/// The execution status of a test case.
enum TestCaseStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
}
