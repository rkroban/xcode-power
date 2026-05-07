import Foundation

/// Handles the `xcode_build` tool call.
/// Validates parameters, checks Xcode availability, triggers a build, and monitors completion.
struct BuildHandler: ToolHandler {

    let toolName = "xcode_build"

    let definition = ToolDefinition(
        name: "xcode_build",
        description: "Triggers a build in Xcode using the warm build cache. Returns build status, duration, and any errors.",
        inputSchema: AnyCodable([
            "type": "object",
            "properties": [
                "scheme": [
                    "type": "string",
                    "description": "The scheme to build. If omitted, builds the active scheme."
                ]
            ],
            "required": [] as [String]
        ])
    )

    private let controller: XcodeController
    private let buildMonitor: BuildMonitor

    /// Creates a BuildHandler with the given dependencies.
    /// - Parameters:
    ///   - controller: The Xcode controller for executing JXA scripts.
    ///   - buildMonitor: The build monitor for polling build completion.
    init(controller: XcodeController, buildMonitor: BuildMonitor) {
        self.controller = controller
        self.buildMonitor = buildMonitor
    }

    func handle(arguments: [String: AnyCodable]?) async -> ToolResult {
        // Extract optional scheme parameter
        let scheme = arguments?["scheme"]?.value as? String

        // Validate scheme if provided (must be non-empty string)
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
                    content: [ToolContent(type: "text", text: "Error: No project or workspace is open in Xcode. Please open a project before building.")],
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Failed to check Xcode availability: \(error)")],
                isError: true
            )
        }

        // Trigger build — Xcode's JXA build() command is synchronous and blocks until complete.
        // Use a long timeout (300s) since builds can take a while.
        let startTime = ContinuousClock.now
        do {
            let buildScript: String
            if let scheme = scheme {
                buildScript = XcodeController.jxaBuild(scheme: scheme)
            } else {
                buildScript = XcodeController.jxaBuild(scheme: nil)
            }
            let output = try await controller.executeJXA(buildScript, timeout: .seconds(300))
            let duration = ContinuousClock.now - startTime
            let durationSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if trimmedOutput.contains("succeeded") || trimmedOutput == "build succeeded" {
                let result = BuildResult(status: .succeeded, duration: durationSeconds, errors: nil)
                let json = try JSONEncoder().encode(result)
                let text = String(data: json, encoding: .utf8) ?? "{}"
                return ToolResult(content: [ToolContent(type: "text", text: text)], isError: nil)
            } else {
                // Build failed — fetch diagnostics
                let diagnostics = (try? await controller.getDiagnostics()) ?? []
                let result = BuildResult(status: .failed, duration: durationSeconds, errors: diagnostics.isEmpty ? nil : diagnostics)
                let json = try JSONEncoder().encode(result)
                let text = String(data: json, encoding: .utf8) ?? "{}"
                return ToolResult(content: [ToolContent(type: "text", text: text)], isError: true)
            }
        } catch {
            let duration = ContinuousClock.now - startTime
            let durationSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

            // Check if it was a timeout
            if "\(error)".contains("timeout") || "\(error)".contains("Timeout") {
                let result = BuildResult(status: .timedOut, duration: durationSeconds, errors: nil)
                if let json = try? JSONEncoder().encode(result),
                   let text = String(data: json, encoding: .utf8) {
                    return ToolResult(content: [ToolContent(type: "text", text: text)], isError: true)
                }
            }

            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: Build failed: \(error)")],
                isError: true
            )
        }
    }
}
