import Foundation

/// Handles the `xcode_test` tool call.
/// Validates parameters, checks Xcode availability, triggers tests, monitors completion,
/// and parses test results from the .xcresult bundle.
struct TestHandler: ToolHandler {

    let toolName = "xcode_test"

    let definition = ToolDefinition(
        name: "xcode_test",
        description: "Runs tests in Xcode for the specified scheme and optional test identifier. Returns test counts and failure details.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "scheme": [
                    "type": "string",
                    "description": "The scheme to test. If omitted, tests the active scheme."
                ],
                "testIdentifier": [
                    "type": "string",
                    "description": "A specific test to run (e.g., 'MyTestClass' or 'MyTestClass/testMethod'). If omitted, runs all tests."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController
    private let buildMonitor: BuildMonitor
    private let resultParser: ResultParser
    private let derivedDataPath: String

    /// Creates a TestHandler with the given dependencies.
    /// - Parameters:
    ///   - controller: The Xcode controller for executing JXA scripts.
    ///   - buildMonitor: The build monitor for polling test completion.
    ///   - resultParser: The parser for extracting test results from .xcresult bundles.
    ///   - derivedDataPath: The path to the derived data directory.
    init(
        controller: XcodeController,
        buildMonitor: BuildMonitor,
        resultParser: ResultParser,
        derivedDataPath: String = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
    ) {
        self.controller = controller
        self.buildMonitor = buildMonitor
        self.resultParser = resultParser
        self.derivedDataPath = derivedDataPath
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Extract optional parameters
        let scheme = arguments?["scheme"]?.value as? String
        let testIdentifier = arguments?["testIdentifier"]?.value as? String

        // Validate scheme if provided
        if let scheme = scheme, scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: scheme parameter must be a non-empty string.")],
                isError: true
            )
        }

        // Validate testIdentifier if provided
        if let testIdentifier = testIdentifier, testIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: testIdentifier parameter must be a non-empty string.")],
                isError: true
            )
        }

        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode and a project before using this tool.")],
                    isError: true
                )
            }
            guard try await controller.hasOpenProject() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: No project or workspace is open in Xcode. Please open a project before running tests.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Trigger test action
        do {
            _ = try await controller.test(scheme: scheme, testIdentifier: testIdentifier)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to trigger test action: \(error)")],
                isError: true
            )
        }

        // Await test completion
        do {
            let status = try await buildMonitor.awaitCompletion()

            switch status {
            case .succeeded, .failed:
                // Parse test results from .xcresult bundle
                return await parseAndReturnResults()

            case .timedOut:
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Test execution timed out after 300 seconds.")],
                    isError: true
                )

            case .running:
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Build monitor returned unexpected 'running' status.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Test monitoring failed: \(error)")],
                isError: true
            )
        }
    }

    // MARK: - Private Helpers

    /// Parses test results from the latest .xcresult bundle and returns them as a ToolResult.
    private func parseAndReturnResults() async -> ToolResult {
        do {
            let bundlePath = try resultParser.findLatestXCResult(derivedDataPath: derivedDataPath)
            let testResults = try await resultParser.parseTestResults(bundlePath: bundlePath)

            let encoder = JSONEncoder()
            let json = try encoder.encode(testResults)
            let text = String(data: json, encoding: .utf8) ?? "{}"

            let isError = testResults.failedCount > 0 ? true : nil
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: isError)
        } catch let error as XcodePowerError {
            switch error {
            case .xcresultNotFound(let searchPath):
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: No .xcresult bundle found at \(searchPath). Tests may not have produced results.")],
                    isError: true
                )
            case .xcresultParsingFailed(let reason):
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to parse test results: \(reason)")],
                    isError: true
                )
            default:
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: \(error)")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to parse test results: \(error)")],
                isError: true
            )
        }
    }
}
