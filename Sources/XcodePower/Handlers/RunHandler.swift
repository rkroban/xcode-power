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
                ],
                "destination": [
                    "type": "string",
                    "description": "The run destination to run on (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination."
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
        let destination = arguments?["destination"]?.value as? String

        // Validate scheme if provided
        if let scheme = scheme, scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: scheme parameter must be a non-empty string.")],
                isError: true
            )
        }

        // Validate destination if provided
        if let destination = destination, destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: destination parameter must be a non-empty string.")],
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

        // Validate scheme exists if provided
        if let scheme = scheme {
            do {
                let availableSchemes = try await controller.listSchemes()
                let schemeNames = availableSchemes.map { $0.name }
                if !schemeNames.contains(scheme) {
                    let list = schemeNames.isEmpty ? "No schemes found." : "Available schemes: \(schemeNames.joined(separator: ", "))"
                    return ToolResult(
                        content: [ToolContent(type: "text", text: "Error: Scheme '\(scheme)' not found. \(list)")],
                        isError: true
                    )
                }
            } catch {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to validate scheme: \(error)")],
                    isError: true
                )
            }
        }

        // Validate destination exists if provided
        if let destination = destination {
            do {
                let availableDestinations = try await controller.listDestinations()
                let destNames = availableDestinations.map { $0.name }
                if !destNames.contains(destination) {
                    let list = destNames.isEmpty ? "No destinations found." : "Available destinations: \(destNames.joined(separator: ", "))"
                    return ToolResult(
                        content: [ToolContent(type: "text", text: "Error: Destination '\(destination)' not found. \(list)")],
                        isError: true
                    )
                }
            } catch {
                return ToolResult(
                    content: [ToolContent(type: "text", text: "Error: Failed to validate destination: \(error)")],
                    isError: true
                )
            }
        }

        // Trigger run action
        do {
            _ = try await controller.run(scheme: scheme, destination: destination)
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
