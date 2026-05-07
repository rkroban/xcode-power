import Foundation

/// The MCP server that handles the initialize/initialized handshake
/// and routes tools/list and tools/call requests.
actor MCPServer {

    /// Server metadata
    static let serverName = "xcode-power"
    static let serverVersion = "1.0.0"
    static let protocolVersion = "2024-11-05"

    /// Server state
    enum State: Sendable, Equatable {
        case uninitialized
        case ready
    }

    /// Current server state
    private(set) var state: State = .uninitialized

    /// The tool registry for handling tools/list and tools/call
    private let toolRegistry: ToolRegistry

    /// Creates an MCPServer with the given tool registry.
    /// - Parameter toolRegistry: The registry containing all tool handlers.
    init(toolRegistry: ToolRegistry) {
        self.toolRegistry = toolRegistry
    }

    // MARK: - MCP Method Handlers

    /// Handles the `initialize` method.
    /// Returns server info, capabilities, and protocol version.
    func handleInitialize(request: JSONRPCRequest) async -> JSONRPCResponse {
        let result = InitializeResult(
            protocolVersion: Self.protocolVersion,
            capabilities: ServerCapabilities(
                tools: ToolsCapability(listChanged: false)
            ),
            serverInfo: ServerInfo(
                name: Self.serverName,
                version: Self.serverVersion
            )
        )

        guard let id = request.id else {
            // Should not happen for initialize (it requires a response), but handle defensively
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: .int(0),
                result: nil,
                error: JSONRPCError(code: -32600, message: "Initialize must include an id", data: nil)
            )
        }

        // Encode the result as AnyCodable
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(result),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: JSONRPCError(code: -32603, message: "Internal error: failed to encode initialize result", data: nil)
            )
        }

        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(dict),
            error: nil
        )
    }

    /// Handles the `initialized` notification.
    /// Transitions the server to the ready state.
    func handleInitialized() {
        state = .ready
    }

    /// Handles the `tools/list` method.
    /// Returns all registered tool definitions.
    func handleToolsList(request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let id = request.id else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: .int(0),
                result: nil,
                error: JSONRPCError(code: -32600, message: "tools/list must include an id", data: nil)
            )
        }

        let tools = await toolRegistry.listTools()

        // Encode tools as array of dictionaries
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(tools),
              let toolsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: JSONRPCError(code: -32603, message: "Internal error: failed to encode tools list", data: nil)
            )
        }

        let result: [String: Any] = ["tools": toolsArray]
        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(result),
            error: nil
        )
    }

    /// Handles the `tools/call` method.
    /// Dispatches to the appropriate tool handler via the ToolRegistry.
    func handleToolsCall(request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let id = request.id else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: .int(0),
                result: nil,
                error: JSONRPCError(code: -32600, message: "tools/call must include an id", data: nil)
            )
        }

        // Parse the params to extract tool name and arguments
        guard let params = request.params,
              let paramsDict = params.value as? [String: Any],
              let toolName = paramsDict["name"] as? String else {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: JSONRPCError(code: -32602, message: "Invalid params: missing 'name' field", data: nil)
            )
        }

        // Extract arguments (optional)
        let arguments: [String: AnyCodable]?
        if let argsDict = paramsDict["arguments"] as? [String: Any] {
            arguments = argsDict.mapValues { AnyCodable($0) }
        } else {
            arguments = nil
        }

        // Dispatch to the tool registry
        do {
            let toolResult = try await toolRegistry.callTool(name: toolName, arguments: arguments)

            // Encode the tool result
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(toolResult),
                  let resultDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: id,
                    result: nil,
                    error: JSONRPCError(code: -32603, message: "Internal error: failed to encode tool result", data: nil)
                )
            }

            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: AnyCodable(resultDict),
                error: nil
            )
        } catch let error as XcodePowerError {
            switch error {
            case .invalidToolArguments(let message):
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: id,
                    result: nil,
                    error: JSONRPCError(code: -32602, message: message, data: nil)
                )
            default:
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: id,
                    result: nil,
                    error: JSONRPCError(code: -32603, message: "Internal error: \(error)", data: nil)
                )
            }
        } catch {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: JSONRPCError(code: -32603, message: "Internal error: \(error)", data: nil)
            )
        }
    }

    /// Registers all MCP method handlers on the given router.
    /// - Parameter router: The JSON-RPC router to register handlers on.
    /// - Returns: The configured router with all MCP methods registered.
    func configureRouter(_ router: inout JSONRPCRouter) {
        // Capture self for use in closures
        let server = self

        router.registerMethod("initialize") { request in
            await server.handleInitialize(request: request)
        }

        // Note: initialized is a notification (no id), so the router will return nil.
        // We still register it to handle the state transition.
        router.registerMethod("initialized") { request in
            await server.handleInitialized()
            // This response won't be sent since notifications have no id,
            // but we need to return something from the handler signature.
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id ?? .int(0),
                result: AnyCodable([:] as [String: Any]),
                error: nil
            )
        }

        router.registerMethod("tools/list") { request in
            await server.handleToolsList(request: request)
        }

        router.registerMethod("tools/call") { request in
            await server.handleToolsCall(request: request)
        }
    }
}
