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
                ],
                "destination": [
                    "type": "string",
                    "description": "The run destination to build for (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination."
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
        let destination = arguments?["destination"]?.value as? String

        // Validate scheme if provided (must be non-empty string)
        if let scheme = scheme, scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolResult(
                content: [ToolContent(type: "text", text: "Error: scheme parameter must be a non-empty string.")],
                isError: true
            )
        }

        // Validate destination if provided (must be non-empty string)
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

        // Trigger build — Xcode's JXA build() command is synchronous and blocks until complete.
        // Use a long timeout (300s) since builds can take a while.
        let startTime = ContinuousClock.now
        do {
            let buildScript: String
            if let scheme = scheme {
                buildScript = XcodeController.jxaBuild(scheme: scheme, destination: destination)
            } else {
                buildScript = XcodeController.jxaBuild(scheme: nil, destination: destination)
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
