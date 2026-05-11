import Foundation

/// Handles the `xcode_list_targets` tool call.
/// Lists all build targets in the Xcode project.
struct ListTargetsHandler: ToolHandler {

    let toolName = "xcode_list_targets"

    let definition = ToolDefinition(
        name: "xcode_list_targets",
        description: "Lists all build targets in the Xcode project, including target name, product type, and bundle identifier.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": [] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates a ListTargetsHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for reading project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
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

        // List targets
        do {
            let targets = try await projectManager.listTargets(projectPath: projectPath)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let json = try encoder.encode(targets)
            let text = String(data: json, encoding: .utf8) ?? "[]"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to list targets: \(error)")],
                isError: true
            )
        }
    }
}
