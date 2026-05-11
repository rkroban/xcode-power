import Foundation

/// Handles the `xcode_add_target` tool call.
/// Adds a new build target to the Xcode project.
struct AddTargetHandler: ToolHandler {

    let toolName = "xcode_add_target"

    let definition = ToolDefinition(
        name: "xcode_add_target",
        description: "Adds a new build target to the Xcode project with the specified name and product type. Creates Sources, Frameworks, and Resources build phases with default build settings.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "The name of the new target to create."
                ] as [String: Any],
                "productType": [
                    "type": "string",
                    "description": "The product type for the target: \"application\", \"framework\", \"staticLibrary\", \"dynamicLibrary\", \"unitTestBundle\", or \"uiTestBundle\".",
                    "enum": ["application", "framework", "staticLibrary", "dynamicLibrary", "unitTestBundle", "uiTestBundle"]
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["name", "productType"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates an AddTargetHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for modifying project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Validate required parameters
        guard let name = arguments?["name"]?.value as? String, !name.isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'name'.")],
                isError: true
            )
        }

        guard let productType = arguments?["productType"]?.value as? String, !productType.isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'productType'.")],
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

        // Add the target
        do {
            try await projectManager.addTarget(
                projectPath: projectPath,
                name: name,
                productType: productType
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Target '\(name)' added successfully.",
                "target": [
                    "name": name,
                    "productType": productType,
                    "bundleIdentifier": "com.example.\(name)"
                ] as [String: Any]
            ]

            let data = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to add target: \(error)")],
                isError: true
            )
        }
    }
}
