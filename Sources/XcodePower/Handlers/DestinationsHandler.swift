import Foundation

/// Handles the `xcode_list_destinations` tool call.
/// Queries Xcode for all available run destinations in the active workspace/project.
struct DestinationsHandler: ToolHandler {

    let toolName = "xcode_list_destinations"

    let definition = ToolDefinition(
        name: "xcode_list_destinations",
        description: "Lists all available run destinations (simulators, devices, My Mac) in the active Xcode workspace or project.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    /// Creates a DestinationsHandler with the given dependencies.
    /// - Parameter controller: The Xcode controller for executing JXA scripts.
    init(controller: XcodeController) {
        self.controller = controller
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode before listing destinations.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Query destinations
        do {
            let destinations = try await controller.listDestinations()
            let json = try JSONEncoder().encode(destinations)
            let text = String(data: json, encoding: .utf8) ?? "[]"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to list destinations: \(error)")],
                isError: true
            )
        }
    }
}
