import Foundation

/// Handles the `xcode_run` tool call.
/// Triggers the run action in Xcode for the specified or active scheme.
struct RunHandler: ToolHandler {

    let toolName = "xcode_run"

    let definition = ToolDefinition(
        name: "xcode_run",
        description: "Runs the application in Xcode for the specified scheme. Returns launch status or build errors if the build fails.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "scheme": [
                    "type": "string",
                    "description": "The scheme to run. If omitted, runs the active scheme."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController

    /// Creates a RunHandler with the given dependencies.
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
                    content: [ToolContent(type: "text", text: "Error: Xcode is not running. Please open Xcode and a project before using this tool.")],
                    isError: true
                )
            }
            guard try await controller.hasOpenProject() else {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: No project or workspace is open in Xcode. Please open a project before running.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Trigger run action
        do {
            _ = try await controller.run(scheme: scheme)
            let result = RunResult(status: "launched", errors: nil)
            let json = try JSONEncoder().encode(result)
            let text = String(data: json, encoding: .utf8) ?? "{}"
            return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
        } catch let error as XcodePowerError {
            switch error {
            case .jxaExecutionFailed(let stderr, _):
                // Build may have failed — try to get diagnostics
                let diagnostics = (try? await controller.getDiagnostics()) ?? []
                let result = RunResult(status: "failed", errors: diagnostics.isEmpty ? nil : diagnostics)
                do {
                    let json = try JSONEncoder().encode(result)
                    let text = String(data: json, encoding: .utf8) ?? "{}"
                    return ToolResult(content: [ToolContent(type: "text", text: text)], isError: true)
                } catch {
                    return ToolResult(
                        content: [ToolContent(type: "text", text: "Error: Run failed: \(stderr)")],
                        isError: true
                    )
                }
            default:
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to trigger run action: \(error)")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to trigger run action: \(error)")],
                isError: true
            )
        }
    }
}
