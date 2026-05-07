import Foundation

/// Handles the `xcode_clean` tool call.
/// Triggers a clean build folder action in Xcode for the specified or active scheme.
struct CleanHandler: ToolHandler {

    let toolName = "xcode_clean"

    let definition = ToolDefinition(
        name: "xcode_clean",
        description: "Cleans the build folder in Xcode for the specified scheme.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "scheme": [
                    "type": "string",
                    "description": "The scheme to clean. If omitted, cleans the active scheme."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    /// Creates a CleanHandler with the given dependencies.
    /// - Parameter controller: The Xcode controller for executing JXA scripts.
    init(controller: XcodeController) {
        self.controller = controller
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Extract optional scheme parameter
        let scheme = arguments?["scheme"]?.value as? String

        // Validate scheme if provided
        if let scheme = scheme, scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: scheme parameter must be a non-empty string.")],
                isError: true
            )
        }

        // Check Xcode availability
        do {
            guard try await controller.isXcodeRunning() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode before cleaning.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Trigger clean action
        do {
            _ = try await controller.clean(scheme: scheme)
            let response: [String: Any] = ["status": "cleaned"]
            let json = try JSONSerialization.data(withJSONObject: response)
            let text = String(data: json, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to clean build folder: \(error)")],
                isError: true
            )
        }
    }
}
