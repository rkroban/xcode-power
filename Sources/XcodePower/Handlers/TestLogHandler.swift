import Foundation

/// Handles the `xcode_get_test_log` tool call.
/// Retrieves the test log from the last test action result with optional filtering.
struct TestLogHandler: ToolHandler {

    let toolName = "xcode_get_test_log"

    let definition = ToolDefinition(
        name: "xcode_get_test_log",
        description: "Retrieves the test log from the last test action. Supports filtering by line count (tail) and grep pattern. Useful for inspecting detailed test output, failures, and diagnostics.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "lines": [
                    "type": "integer",
                    "description": "Return only the last N lines of the test log. If omitted, returns the full log."
                ],
                "grep": [
                    "type": "string",
                    "description": "Filter the test log to only lines containing this substring (case-insensitive). Applied before line truncation."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    init(controller: XcodeController) {
        self.controller = controller
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        let lineLimit = arguments?["lines"]?.value as? Int
        let grepPattern = arguments?["grep"]?.value as? String

        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Fetch the test log via JXA
        // After a test action, lastSchemeActionResult() contains the test execution log.
        let script = """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];
        var result = workspace.lastSchemeActionResult();
        result.buildLog();
        """

        do {
            let output = try await controller.executeJXA(script, timeout: .seconds(30))
            var logLines = output.components(separatedBy: .newlines)

            // Apply grep filter if specified
            if let pattern = grepPattern, !pattern.isEmpty {
                let lowercasePattern = pattern.lowercased()
                logLines = logLines.filter { $0.lowercased().contains(lowercasePattern) }
            }

            // Apply line limit (tail N lines)
            if let limit = lineLimit, limit > 0, logLines.count > limit {
                logLines = Array(logLines.suffix(limit))
            }

            let result = logLines.joined(separator: "\n")

            if result.isEmpty {
                let msg = grepPattern != nil
                    ? "No lines matched the grep pattern '\(grepPattern!)'."
                    : "Test log is empty. Make sure you have run tests before retrieving the log."
                return ToolResult(content: [ToolContent(type: "text", text: msg)], isError: nil)
            }

            return ToolResult(content: [ToolContent(type: "text", text: result)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to retrieve test log: \(error)")],
                isError: true
            )
        }
    }
}
