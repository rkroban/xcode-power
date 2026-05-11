import Foundation

/// Handles the `xcode_list_frameworks` tool call.
/// Lists all frameworks and libraries linked to a specific target in the Xcode project.
struct ListFrameworksHandler: ToolHandler {

    let toolName = "xcode_list_frameworks"

    let definition = ToolDefinition(
        name: "xcode_list_frameworks",
        description: "Lists all frameworks and libraries linked to a specific target, including framework name, type (system, SPM product, or project-relative), and whether it is required or optional.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "target": [
                    "type": "string",
                    "description": "The name of the target to list frameworks for."
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["target"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates a ListFrameworksHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for reading project files.
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

        // List frameworks
        do {
            let frameworks = try await projectManager.listFrameworks(projectPath: projectPath, targetName: targetName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let json = try encoder.encode(frameworks)
            let text = String(data: json, encoding: .utf8) ?? "[]"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to list frameworks: \(error)")],
                isError: true
            )
        }
    }
}
