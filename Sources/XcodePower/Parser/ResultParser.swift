import Foundation

/// Parses structured test results from .xcresult bundles produced by Xcode.
/// Uses `xcrun xcresulttool` to extract JSON data from the bundles.
struct ResultParser {

    /// The process executor used to run xcresulttool commands.
    private let processExecutor: ProcessExecuting

    /// Creates a ResultParser with the given process executor.
    /// - Parameter processExecutor: The executor used to run xcresulttool commands.
    init(processExecutor: ProcessExecuting = ProcessExecutor()) {
        self.processExecutor = processExecutor
    }

    // MARK: - Public API

    /// Locates the most recent .xcresult bundle in the given derived data path.
    /// - Parameter derivedDataPath: The path to the derived data directory (typically ~/Library/Developer/Xcode/DerivedData).
    /// - Returns: The URL of the most recent .xcresult bundle.
    /// - Throws: `XcodePowerError.xcresultNotFound` if no .xcresult bundle is found.
    func findLatestXCResult(derivedDataPath: String) throws -> URL {
        let derivedDataURL = URL(fileURLWithPath: derivedDataPath)
        let fileManager = FileManager.default

        // Look for .xcresult bundles in Logs/Test subdirectories of each project folder
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: derivedDataURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw XcodePowerError.xcresultNotFound(searchPath: derivedDataPath)
        }

        var latestBundle: URL?
        var latestDate: Date?

        for projectDir in projectDirs {
            let testLogsPath = projectDir.appendingPathComponent("Logs/Test")
            guard let contents = try? fileManager.contentsOfDirectory(
                at: testLogsPath,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for item in contents where item.pathExtension == "xcresult" {
                let attributes = try? fileManager.attributesOfItem(atPath: item.path)
                let modDate = attributes?[.modificationDate] as? Date

                if let modDate = modDate {
                    if latestDate == nil || modDate > latestDate! {
                        latestDate = modDate
                        latestBundle = item
                    }
                } else if latestBundle == nil {
                    latestBundle = item
                }
            }
        }

        guard let bundle = latestBundle else {
            throw XcodePowerError.xcresultNotFound(searchPath: derivedDataPath)
        }

        return bundle
    }

    /// Parses test results from an .xcresult bundle using `xcrun xcresulttool`.
    /// - Parameter bundlePath: The URL of the .xcresult bundle to parse.
    /// - Returns: Aggregated test results.
    /// - Throws: `XcodePowerError.xcresultParsingFailed` if parsing fails.
    func parseTestResults(bundlePath: URL) async throws -> TestResults {
        let output = try await processExecutor.run(
            command: "/usr/bin/xcrun",
            arguments: ["xcresulttool", "get", "--format", "json", "--path", bundlePath.path],
            timeout: .seconds(30)
        )

        guard let jsonData = output.stdout.data(using: .utf8) else {
            throw XcodePowerError.xcresultParsingFailed(reason: "Failed to read xcresulttool output as UTF-8")
        }

        let testCases = try extractTestCases(from: jsonData)
        return aggregateResults(from: testCases)
    }

    // MARK: - Extraction

    /// Extracts individual test case results from xcresulttool JSON output.
    /// - Parameter json: The raw JSON data from xcresulttool.
    /// - Returns: An array of individual test case results.
    /// - Throws: `XcodePowerError.xcresultParsingFailed` if the JSON structure is unexpected.
    func extractTestCases(from json: Data) throws -> [TestCaseResult] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw XcodePowerError.xcresultParsingFailed(reason: "Invalid JSON structure in xcresult output")
        }

        var testCases: [TestCaseResult] = []

        // Navigate the xcresulttool JSON structure to find test action results
        // The structure is: actions._values[].actionResult.testsRef -> then get the tests summary
        if let actions = root["actions"] as? [String: Any],
           let values = actions["_values"] as? [[String: Any]] {
            for action in values {
                if let actionResult = action["actionResult"] as? [String: Any],
                   let testsRef = actionResult["testsRef"] as? [String: Any],
                   let id = testsRef["id"] as? [String: Any],
                   let _ = id["_value"] as? String {
                    // In a real scenario, we'd need to fetch the test summary using the ref ID.
                    // For now, look for inline test summaries if available.
                }
            }
        }

        // Try the newer xcresulttool format where test results are embedded directly
        // Look for testPlanRunSummaries or testableSummaries
        testCases.append(contentsOf: try extractFromTestPlanSummaries(root))

        return testCases
    }

    // MARK: - Aggregation

    /// Aggregates individual test case results into a summary.
    /// - Parameter testCases: The individual test case results to aggregate.
    /// - Returns: Aggregated test results with counts and failure details.
    static func aggregateResults(from testCases: [TestCaseResult]) -> TestResults {
        let totalCount = testCases.count
        let passedCount = testCases.filter { $0.status == .passed }.count
        let failedCount = testCases.filter { $0.status == .failed }.count

        let failures: [TestFailure] = testCases
            .filter { $0.status == .failed }
            .map { testCase in
                TestFailure(
                    testName: "\(testCase.className)/\(testCase.name)",
                    failureMessage: testCase.failureMessage ?? "Test failed",
                    filePath: testCase.filePath,
                    lineNumber: testCase.lineNumber
                )
            }

        return TestResults(
            totalCount: totalCount,
            passedCount: passedCount,
            failedCount: failedCount,
            failures: failures
        )
    }

    /// Instance method wrapper for aggregateResults for convenience.
    func aggregateResults(from testCases: [TestCaseResult]) -> TestResults {
        Self.aggregateResults(from: testCases)
    }

    // MARK: - Private Parsing Helpers

    /// Extracts test cases from the test plan summaries structure in xcresulttool JSON.
    private func extractFromTestPlanSummaries(_ root: [String: Any]) throws -> [TestCaseResult] {
        var testCases: [TestCaseResult] = []

        // Navigate: actions._values[].actionResult.testPlanRunSummaries or similar
        // The xcresulttool JSON format varies by Xcode version, so we handle multiple paths

        // Path 1: Direct testableSummaries (older format)
        if let actions = root["actions"] as? [String: Any],
           let values = actions["_values"] as? [[String: Any]] {
            for action in values {
                if let actionResult = action["actionResult"] as? [String: Any],
                   let testsSummary = actionResult["testsSummary"] as? [String: Any] {
                    testCases.append(contentsOf: extractTestCasesFromSummary(testsSummary))
                }
            }
        }

        // Path 2: Look for tests at the top level (simplified format from xcresulttool get)
        if let testsNode = root["tests"] as? [String: Any] {
            testCases.append(contentsOf: extractTestCasesFromTestsNode(testsNode))
        }

        // Path 3: Flat array of test results (common in xcresulttool output)
        if let testResults = root["testResults"] as? [[String: Any]] {
            for result in testResults {
                if let testCase = parseTestCaseFromDict(result) {
                    testCases.append(testCase)
                }
            }
        }

        return testCases
    }

    /// Extracts test cases from a tests summary node.
    private func extractTestCasesFromSummary(_ summary: [String: Any]) -> [TestCaseResult] {
        var testCases: [TestCaseResult] = []

        if let testableSummaries = summary["testableSummaries"] as? [String: Any],
           let values = testableSummaries["_values"] as? [[String: Any]] {
            for testable in values {
                if let tests = testable["tests"] as? [String: Any] {
                    testCases.append(contentsOf: extractTestCasesFromTestsNode(tests))
                }
            }
        }

        return testCases
    }

    /// Recursively extracts test cases from a tests node in the xcresulttool JSON.
    private func extractTestCasesFromTestsNode(_ testsNode: [String: Any]) -> [TestCaseResult] {
        var testCases: [TestCaseResult] = []

        guard let values = testsNode["_values"] as? [[String: Any]] else {
            return testCases
        }

        for value in values {
            // Check if this is a leaf test case (has a testStatus)
            if let statusDict = value["testStatus"] as? [String: Any],
               let statusValue = statusDict["_value"] as? String {
                let testCase = parseTestCaseFromXCResult(value, statusString: statusValue)
                testCases.append(testCase)
            }

            // Recurse into subtests
            if let subtests = value["subtests"] as? [String: Any] {
                testCases.append(contentsOf: extractTestCasesFromTestsNode(subtests))
            }
        }

        return testCases
    }

    /// Parses a single test case from an xcresulttool JSON dictionary.
    private func parseTestCaseFromXCResult(_ dict: [String: Any], statusString: String) -> TestCaseResult {
        let name = (dict["name"] as? [String: Any])?["_value"] as? String ?? "Unknown"
        let className = (dict["identifier"] as? [String: Any])?["_value"] as? String ?? "Unknown"

        let status: TestCaseStatus
        switch statusString.lowercased() {
        case "success":
            status = .passed
        case "failure":
            status = .failed
        default:
            status = .skipped
        }

        let duration = (dict["duration"] as? [String: Any])?["_value"] as? Double ?? 0.0

        var failureMessage: String?
        var filePath: String?
        var lineNumber: Int?

        if let failureSummaries = dict["failureSummaries"] as? [String: Any],
           let failureValues = failureSummaries["_values"] as? [[String: Any]],
           let firstFailure = failureValues.first {
            failureMessage = (firstFailure["message"] as? [String: Any])?["_value"] as? String
            filePath = (firstFailure["fileName"] as? [String: Any])?["_value"] as? String
            if let lineStr = (firstFailure["lineNumber"] as? [String: Any])?["_value"] as? String {
                lineNumber = Int(lineStr)
            } else if let lineInt = (firstFailure["lineNumber"] as? [String: Any])?["_value"] as? Int {
                lineNumber = lineInt
            }
        }

        return TestCaseResult(
            name: name,
            className: className,
            status: status,
            duration: duration,
            failureMessage: failureMessage,
            filePath: filePath,
            lineNumber: lineNumber
        )
    }

    /// Parses a test case from a flat dictionary format.
    private func parseTestCaseFromDict(_ dict: [String: Any]) -> TestCaseResult? {
        guard let name = dict["name"] as? String,
              let className = dict["className"] as? String,
              let statusStr = dict["status"] as? String else {
            return nil
        }

        let status: TestCaseStatus
        switch statusStr.lowercased() {
        case "passed", "success":
            status = .passed
        case "failed", "failure":
            status = .failed
        default:
            status = .skipped
        }

        let duration = dict["duration"] as? Double ?? 0.0
        let failureMessage = dict["failureMessage"] as? String
        let filePath = dict["filePath"] as? String
        let lineNumber = dict["lineNumber"] as? Int

        return TestCaseResult(
            name: name,
            className: className,
            status: status,
            duration: duration,
            failureMessage: failureMessage,
            filePath: filePath,
            lineNumber: lineNumber
        )
    }
}
