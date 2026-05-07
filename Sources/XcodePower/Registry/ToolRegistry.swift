import Foundation

/// Protocol for tool handlers that process tool call requests.
protocol ToolHandler: Sendable {
    /// The name of the tool this handler processes.
    var toolName: String { get }

    /// The tool definition including name, description, and input schema.
    var definition: ToolDefinition { get }

    /// Handles a tool call with the given arguments.
    /// - Parameter arguments: The arguments passed to the tool call.
    /// - Returns: The result of the tool execution.
    func handle(arguments: [String: AnyCodable]?) async -> ToolResult
}

/// Actor that manages tool definitions and dispatches tool call requests to appropriate handlers.
actor ToolRegistry {

    /// All registered tool handlers, keyed by tool name.
    private var handlers: [String: ToolHandler] = [:]

    /// Creates a ToolRegistry with the given handlers.
    /// - Parameter handlers: The tool handlers to register.
    init(handlers: [ToolHandler] = []) {
        for handler in handlers {
            self.handlers[handler.toolName] = handler
        }
    }

    /// Registers a tool handler.
    /// - Parameter handler: The handler to register.
    func register(_ handler: ToolHandler) {
        handlers[handler.toolName] = handler
    }

    /// Returns all registered tool definitions for tools/list responses.
    /// - Returns: An array of all tool definitions.
    func listTools() -> [ToolDefinition] {
        handlers.values.map { $0.definition }
    }

    /// Dispatches a tool call to the appropriate handler.
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: The arguments to pass to the tool.
    /// - Returns: The result of the tool execution.
    /// - Throws: `XcodePowerError.invalidToolArguments` if the tool name is not registered.
    func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> ToolResult {
        guard let handler = handlers[name] else {
            throw XcodePowerError.invalidToolArguments(message: "Unknown tool: \(name)")
        }
        return await handler.handle(arguments: arguments)
    }
}
