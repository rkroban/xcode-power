import Foundation

/// Handles the `xcode_test` tool call.
/// Validates parameters, checks Xcode availability, triggers tests (with polling),
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
                ],
                "destination": [
                    "type": "string",
                    "description": "The run destination to test on (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController
    private let buildMonitor: BuildMonitor
    private let resultParser: ResultParser
    private let derivedDataPath: String

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
        let destination = arguments?["destination"]?.value as? String

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

        // Validate destination if provided
        if let destination = destination, destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: destination parameter must be a non-empty string.")],
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

        // Validate scheme exists if provided
        if let scheme = scheme {
            do {
                let availableSchemes = try await controller.listSchemes()
                let schemeNames = availableSchemes.map { $0.name }
                if !schemeNames.contains(scheme) {
                    let list = schemeNames.isEmpty ? "No schemes found." : "Available schemes: \(schemeNames.joined(separator: ", "))"
                    return ToolResult(
                        content: [ToolContent(type: "text", text: "Error: Scheme '\(scheme)' not found. \(list)")],
                        isError: true
                    )
                }
            } catch {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to validate scheme: \(error)")],
                    isError: true
                )
            }
        }

        // Validate destination exists if provided
        if let destination = destination {
            do {
                let availableDestinations = try await controller.listDestinations()
                let destNames = availableDestinations.map { $0.name }
                if !destNames.contains(destination) {
                    let list = destNames.isEmpty ? "No destinations found." : "Available destinations: \(destNames.joined(separator: ", "))"
                    return ToolResult(
                        content: [ToolContent(type: "text", text: "Error: Destination '\(destination)' not found. \(list)")],
                        isError: true
                    )
                }
            } catch {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to validate destination: \(error)")],
                    isError: true
                )
            }
        }

        // Trigger test action — the JXA script polls until completion and returns the status.
        let startTime = ContinuousClock.now
        do {
            let testScript = XcodeController.jxaTest(scheme: scheme, testIdentifier: testIdentifier, destination: destination)
            let output = try await controller.executeJXA(testScript, timeout: .seconds(300))
            let duration = ContinuousClock.now - startTime
            let durationSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Try to parse test results from .xcresult bundle
            let testResults = await parseTestResults()

            if let results = testResults {
                let encoder = JSONEncoder()
                let json = try encoder.encode(results)
                let text = String(data: json, encoding: .utf8) ?? "{}"
                let isError = results.failedCount > 0 ? true : nil
                return ToolResult(content: [ToolContent(type: "text", text: text)], isError: isError)
            }

            // Fallback: return status if we can't parse xcresult
            if trimmedOutput.contains("succeeded") {
                let result: [String: Any] = ["status": "succeeded", "duration": durationSeconds, "message": "Tests passed"]
                let json = try JSONSerialization.data(withJSONObject: result)
                let text = String(data: json, encoding: .utf8) ?? "{}"
                return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
            } else {
                // Get diagnostics for failure info
                let diagnostics = (try? await controller.getDiagnostics()) ?? []
                var result: [String: Any] = ["status": "failed", "duration": durationSeconds]
                if !diagnostics.isEmpty {
                    let diagEncoder = JSONEncoder()
                    if let diagData = try? diagEncoder.encode(diagnostics),
                       let diagArray = try? JSONSerialization.jsonObject(with: diagData) {
                        result["errors"] = diagArray
                    }
                }
                let json = try JSONSerialization.data(withJSONObject: result)
                let text = String(data: json, encoding: .utf8) ?? "{}"
                return ToolResult(content: [ToolContent(type: "text", text: text)], isError: true)
            }
        } catch {
            if "\(error)".contains("timeout") || "\(error)".contains("Timeout") {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Test execution timed out after 300 seconds.")],
                    isError: true
                )
            }
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Test execution failed: \(error)")],
                isError: true
            )
        }
    }

    // MARK: - Private Helpers

    /// Attempts to parse test results from the latest .xcresult bundle.
    private func parseTestResults() async -> TestResults? {
        do {
            let bundlePath = try resultParser.findLatestXCResult(derivedDataPath: derivedDataPath)
            return try await resultParser.parseTestResults(bundlePath: bundlePath)
        } catch {
            return nil
        }
    }
}
