import Foundation

/// Handles the `xcode_remove_package` tool call.
/// Removes a Swift Package Manager dependency from the Xcode project,
/// including all product references from every target that linked products of that package.
struct RemovePackageHandler: ToolHandler {

    let toolName = "xcode_remove_package"

    let definition = ToolDefinition(
        name: "xcode_remove_package",
        description: "Removes a Swift Package Manager dependency from the Xcode project. Matches the identifier against the repository URL (exact match) or package name (case-insensitive). Also removes all linked product references from targets.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "identifier": [
                    "type": "string",
                    "description": "The package identifier to match. Can be the full repository URL (exact match) or the package name derived from the URL (case-insensitive match)."
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["identifier"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates a RemovePackageHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for modifying project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Validate required parameter
        guard let identifier = arguments?["identifier"]?.value as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing or empty required parameter 'identifier'. The package identifier is required.")],
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

        // Remove the package
        do {
            try await projectManager.removePackage(projectPath: projectPath, identifier: identifier)

            let result: [String: Any] = [
                "success": true,
                "message": "Package matching '\(identifier)' removed successfully."
            ]

            let data = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to remove package: \(error)")],
                isError: true
            )
        }
    }
}
