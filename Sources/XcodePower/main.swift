// Xcode Power MCP Server - Entry Point
//
// This is the main entry point for the Xcode Power MCP server.
// It wires together all components and starts the message read loop.

import Foundation

// MARK: - Main Run Loop

/// Runs the MCP server, reading messages from stdin and writing responses to stdout.
func runServer() async {
    // Create the process executor (shared dependency)
    let processExecutor = ProcessExecutor()

    // Create core components
    let controller = XcodeController(processExecutor: processExecutor)
    let buildMonitor = BuildMonitor(processExecutor: processExecutor)
    let resultParser = ResultParser(processExecutor: processExecutor)

    // Create tool handlers
    let handlers: [ToolHandler] = [
        BuildHandler(controller: controller, buildMonitor: buildMonitor),
        TestHandler(controller: controller, buildMonitor: buildMonitor, resultParser: resultParser),
        RunHandler(controller: controller),
        SchemesHandler(controller: controller),
        ErrorsHandler(controller: controller),
        CleanHandler(controller: controller),
    ]

    // Create tool registry with all handlers
    let toolRegistry = ToolRegistry(handlers: handlers)

    // Create MCP server and configure the router
    let mcpServer = MCPServer(toolRegistry: toolRegistry)
    var router = JSONRPCRouter()
    await mcpServer.configureRouter(&router)

    // Create transport
    let transport = StdioTransport()

    // Log to stderr so it doesn't interfere with JSON-RPC on stdout
    FileHandle.standardError.write("Xcode Power MCP Server started\n".data(using: .utf8)!)

    // Start the message read loop
    let messages = transport.messages()

    for await message in messages {
        // Debug: log received message to stderr
        let msgStr = String(data: message, encoding: .utf8) ?? "<non-utf8>"
        FileHandle.standardError.write("Received: \(msgStr)\n".data(using: .utf8)!)

        // Route the message through the JSON-RPC router
        if let responseData = await router.route(message) {
            // Debug: log response to stderr
            let respStr = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
            FileHandle.standardError.write("Sending: \(respStr)\n".data(using: .utf8)!)

            // Write the response back via transport
            transport.writeMessage(responseData)

            FileHandle.standardError.write("Response written\n".data(using: .utf8)!)
        }
        // If route returns nil, it was a notification — no response needed
    }

    // stdin closed (EOF) — graceful shutdown
    FileHandle.standardError.write("Xcode Power MCP Server shutting down\n".data(using: .utf8)!)
}

// MARK: - Entry Point

// Start the async run loop
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runServer()
    semaphore.signal()
}
semaphore.wait()
