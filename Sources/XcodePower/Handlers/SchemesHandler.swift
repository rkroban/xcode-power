import Foundation

/// Handles the `xcode_list_schemes` tool call.
/// Queries Xcode for all available schemes in the active workspace/project.
struct SchemesHandler: ToolHandler {

    let toolName = "xcode_list_schemes"

    let definition = ToolDefinition(
        name: "xcode_list_schemes",
        description: "Lists all available schemes in the active Xcode workspace or project.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    /// Creates a SchemesHandler with the given dependencies.
    /// - Parameter controller: The Xcode controller for executing JXA scripts.
    init(controller: XcodeController) {
        self.controller = controller
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode before listing schemes.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Query schemes
        do {
            let schemes = try await controller.listSchemes()
            let json = try JSONEncoder().encode(schemes)
            let text = String(data: json, encoding: .utf8) ?? "[]"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to list schemes: \(error)")],
                isError: true
            )
        }
    }
}
