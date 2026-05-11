import Foundation

/// Handles the `xcode_add_package` tool call.
/// Adds a Swift Package Manager dependency to the Xcode project.
struct AddPackageHandler: ToolHandler {

    let toolName = "xcode_add_package"

    let definition = ToolDefinition(
        name: "xcode_add_package",
        description: "Adds a Swift Package Manager dependency to the Xcode project with the specified repository URL and version requirement.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The repository URL of the Swift package (e.g., https://github.com/user/repo.git)."
                ] as [String: Any],
                "versionType": [
                    "type": "string",
                    "description": "The version requirement type: \"from\" (minimum version), \"exact\" (exact version), \"branch\" (branch name), or \"revision\" (commit hash).",
                    "enum": ["from", "exact", "branch", "revision"]
                ] as [String: Any],
                "versionValue": [
                    "type": "string",
                    "description": "The version value: a semver string for from/exact (e.g., \"1.0.0\"), a branch name for branch, or a 40-character hex commit hash for revision."
                ] as [String: Any],
                "projectPath": [
                    "type": "string",
                    "description": "Absolute path to the .xcodeproj bundle. If omitted, resolves from the active Xcode workspace."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["url", "versionType", "versionValue"] as [String]
        ])
    )

    private let projectManager: ProjectManager

    /// Creates an AddPackageHandler with the given dependencies.
    /// - Parameter projectManager: The project manager for modifying project files.
    init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Validate required parameters
        guard let url = arguments?["url"]?.value as? String, !url.isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'url'.")],
                isError: true
            )
        }

        guard let versionType = arguments?["versionType"]?.value as? String, !versionType.isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'versionType'.")],
                isError: true
            )
        }

        guard let versionValue = arguments?["versionValue"]?.value as? String, !versionValue.isEmpty else {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Missing required parameter 'versionValue'.")],
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

        // Add the package
        do {
            try await projectManager.addPackage(
                projectPath: projectPath,
                url: url,
                versionType: versionType,
                versionValue: versionValue
            )

            // Derive package name from URL for the success message
            let packageName = url.split(separator: "/").last
                .map { String($0) }?
                .replacingOccurrences(of: ".git", with: "") ?? url

            let result: [String: Any] = [
                "success": true,
                "message": "Package '\(packageName)' added successfully.",
                "package": [
                    "name": packageName,
                    "repositoryURL": url,
                    "versionType": versionType,
                    "versionValue": versionValue
                ] as [String: Any]
            ]

            let data = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to add package: \(error)")],
                isError: true
            )
        }
    }
}
