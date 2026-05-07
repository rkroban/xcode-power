import Foundation

/// Handles the `xcode_get_errors` tool call.
/// Retrieves current build diagnostics (errors and warnings) from Xcode.
struct ErrorsHandler: ToolHandler {

    let toolName = "xcode_get_errors"

    let definition = ToolDefinition(
        name: "xcode_get_errors",
        description: "Retrieves current build diagnostics (errors and warnings) from Xcode.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    /// Creates an ErrorsHandler with the given dependencies.
    /// - Parameter controller: The Xcode controller for executing JXA scripts.
    init(controller: XcodeController) {
        self.controller = controller
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode before querying diagnostics.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Query diagnostics
        do {
            let diagnostics = try await controller.getDiagnostics()
            let json = try JSONEncoder().encode(diagnostics)
            let text = String(data: json, encoding: .utf8) ?? "[]"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to retrieve diagnostics: \(error)")],
                isError: true
            )
        }
    }
}
