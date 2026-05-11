import Foundation

/// Handles the `xcode_remove_framework` tool call.
/// Removes a framework or library from a target's link build phase in the Xcode project.
struct RemoveFrameworkHandler: ToolHandler {

    let toolName = "xcode_remove_framework"

    let definition = ToolDefinition(
        name: "xcode_remove_framework",
        description: "Removes a framework or library from a target's link build phase. Matches the framework by name using a case-sensitive exact match.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "target": [
                    "type": "string",
                    "description": "The name of the target to remove the framework from."
                ] as [String: Any],
                "framework": [
                    "type": "string",
                    "description": "The framework name to remove (case-sensitive exact match). For example: \"UIKit.framework\", \"Alamofire\", or \"MyLib.framework\"."
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["target", "framework"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates a RemoveFrameworkHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for modifying project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Validate required 'target' parameter
        guard let targetName = arguments?["target"]?.value as? String,
              !targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'target'.")],
                isError: true
            )
        }

        // Validate required 'framework' parameter
        guard let frameworkName = arguments?["framework"]?.value as? String,
              !frameworkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'framework'.")],
                isError: true
            )
        }

        // Extract optional projectPath argument
        let explicitPath = arguments?["projectPath"]?.value as? String

        // Resolve the project path
        let projectPath: String
        do {
            projectPath = try await projectManager.resolveProjectPath(explicit: explicitPath)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: \(error)")],
                isError: true
            )
        }

        // Remove the framework
        do {
            try await projectManager.removeFramework(
                projectPath: projectPath,
                targetName: targetName,
                frameworkName: frameworkName
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Framework '\(frameworkName)' removed from target '\(targetName)' successfully."
            ]

            let data = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to remove framework: \(error)")],
                isError: true
            )
        }
    }
}
