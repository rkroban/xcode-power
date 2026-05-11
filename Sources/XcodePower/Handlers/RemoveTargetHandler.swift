import Foundation

/// Handles the `xcode_remove_target` tool call.
/// Removes a build target from the Xcode project, including its build configurations,
/// build phases, target dependencies from other targets, and references from shared schemes.
struct RemoveTargetHandler: ToolHandler {

    let toolName = "xcode_remove_target"

    let definition = ToolDefinition(
        name: "xcode_remove_target",
        description: "Removes a build target from the Xcode project, including its build configurations, build phases, dependencies from other targets, and references from shared schemes.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "The exact name of the target to remove (case-sensitive)."
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["name"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates a RemoveTargetHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for modifying project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Validate required parameter
        guard let name = arguments?["name"]?.value as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing or empty required parameter 'name'. The target name is required.")],
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

        // Remove the target
        do {
            try await projectManager.removeTarget(projectPath: projectPath, name: name)

            let result: [String: Any] = [
                "success": true,
                "message": "Target '\(name)' removed successfully."
            ]

            let data = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to remove target: \(error)")],
                isError: true
            )
        }
    }
}
