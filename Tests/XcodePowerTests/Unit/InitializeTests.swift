import XCTest
@testable import XcodePower

/// Unit tests for the MCP server initialization handshake.
final class InitializeTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an MCPServer with a ToolRegistry containing all 6 tool handlers using a mock executor.
    private func makeServer() -> MCPServer {
        let executor = MockProcessExecutor()
        let controller = XcodeController(processExecutor: executor)
        let buildMonitor = BuildMonitor(processExecutor: executor)
        let resultParser = ResultParser(processExecutor: executor)

        let handlers: [ToolHandler] = [
            BuildHandler(controller: controller, buildMonitor: buildMonitor),
            TestHandler(controller: controller, buildMonitor: buildMonitor, resultParser: resultParser),
            RunHandler(controller: controller),
            SchemesHandler(controller: controller),
            ErrorsHandler(controller: controller),
            CleanHandler(controller: controller),
        ]

        let toolRegistry = ToolRegistry(handlers: handlers)
        return MCPServer(toolRegistry: toolRegistry)
    }

    /// Runs an async block synchronously for testing.
    private func runAsync<T>(_ block: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T!
        Task {
            result = await block()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Test: Initialize response contains correct server name, version, and capabilities

    func testInitializeResponseContainsCorrectServerInfo() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "initialize",
            params: nil
        )

        let response = runAsync { await server.handleInitialize(request: request) }

        // Verify response structure
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .int(1))
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)

        // Parse the result to verify contents
        guard let resultValue = response.result?.value as? [String: Any] else {
            XCTFail("Expected result to be a dictionary")
            return
        }

        // Check protocol version
        XCTAssertEqual(resultValue["protocolVersion"] as? String, "2024-11-05")

        // Check server info
        guard let serverInfo = resultValue["serverInfo"] as? [String: Any] else {
            XCTFail("Expected serverInfo in result")
            return
        }
        XCTAssertEqual(serverInfo["name"] as? String, "xcode-power")
        XCTAssertEqual(serverInfo["version"] as? String, "1.0.0")

        // Check capabilities
        guard let capabilities = resultValue["capabilities"] as? [String: Any] else {
            XCTFail("Expected capabilities in result")
            return
        }
        guard let tools = capabilities["tools"] as? [String: Any] else {
            XCTFail("Expected tools capability")
            return
        }
        XCTAssertNotNil(tools["listChanged"])
    }

    func testInitializeResponseEchoesStringId() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .string("init-request-42"),
            method: "initialize",
            params: nil
        )

        let response = runAsync { await server.handleInitialize(request: request) }

        XCTAssertEqual(response.id, .string("init-request-42"))
        XCTAssertNil(response.error)
    }

    // MARK: - Test: State transition from uninitialized to ready

    func testStateTransitionFromUninitializedToReady() {
        let server = makeServer()

        // Initially should be uninitialized
        let initialState = runAsync { await server.state }
        XCTAssertEqual(initialState, .uninitialized)

        // Send initialized notification
        runAsync { await server.handleInitialized() }

        // Should now be ready
        let readyState = runAsync { await server.state }
        XCTAssertEqual(readyState, .ready)
    }

    func testStateRemainsUninitializedBeforeInitializedNotification() {
        let server = makeServer()

        // Call initialize (but not initialized)
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "initialize",
            params: nil
        )
        _ = runAsync { await server.handleInitialize(request: request) }

        // State should still be uninitialized (initialize alone doesn't change state)
        let state = runAsync { await server.state }
        XCTAssertEqual(state, .uninitialized)
    }

    // MARK: - Test: tools/list returns all 6 tools with correct schemas

    func testToolsListReturnsAllSixTools() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(2),
            method: "tools/list",
            params: nil
        )

        let response = runAsync { await server.handleToolsList(request: request) }

        // Verify response structure
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .int(2))
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)

        // Parse the result
        guard let resultValue = response.result?.value as? [String: Any],
              let tools = resultValue["tools"] as? [[String: Any]] else {
            XCTFail("Expected result with tools array")
            return
        }

        // Should have exactly 6 tools
        XCTAssertEqual(tools.count, 6)

        // Extract tool names
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        // Verify all expected tools are present
        let expectedTools: Set<String> = [
            "xcode_build",
            "xcode_test",
            "xcode_run",
            "xcode_list_schemes",
            "xcode_get_errors",
            "xcode_clean"
        ]
        XCTAssertEqual(toolNames, expectedTools)

        // Verify each tool has required fields
        for tool in tools {
            XCTAssertNotNil(tool["name"] as? String, "Tool missing 'name'")
            XCTAssertNotNil(tool["description"] as? String, "Tool missing 'description'")
            XCTAssertNotNil(tool["inputSchema"], "Tool missing 'inputSchema'")
        }
    }

    func testToolsListEchoesRequestId() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .string("list-tools-99"),
            method: "tools/list",
            params: nil
        )

        let response = runAsync { await server.handleToolsList(request: request) }

        XCTAssertEqual(response.id, .string("list-tools-99"))
        XCTAssertNil(response.error)
    }

    // MARK: - Test: tools/call dispatches correctly

    func testToolsCallWithUnknownToolReturnsError() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(3),
            method: "tools/call",
            params: AnyCodable(["name": "nonexistent_tool"])
        )

        let response = runAsync { await server.handleToolsCall(request: request) }

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .int(3))
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
    }

    func testToolsCallWithMissingNameReturnsInvalidParams() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(4),
            method: "tools/call",
            params: AnyCodable(["arguments": [:] as [String: Any]])
        )

        let response = runAsync { await server.handleToolsCall(request: request) }

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .int(4))
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
    }

    func testToolsCallWithNilParamsReturnsInvalidParams() {
        let server = makeServer()

        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            id: .int(5),
            method: "tools/call",
            params: nil
        )

        let response = runAsync { await server.handleToolsCall(request: request) }

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .int(5))
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
    }

    // MARK: - Test: Full router integration

    func testRouterIntegrationInitialize() {
        let server = makeServer()
        var router = JSONRPCRouter()
        runAsync { await server.configureRouter(&router) }

        // Send an initialize request through the router
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [:] as [String: Any]
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
            XCTFail("Failed to serialize request")
            return
        }

        let responseData = runAsync { await router.route(requestData) }
        XCTAssertNotNil(responseData)

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse response")
            return
        }

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertNil(json["error"])

        guard let result = json["result"] as? [String: Any] else {
            XCTFail("Expected result in response")
            return
        }
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
    }

    func testRouterIntegrationInitializedNotification() {
        let server = makeServer()
        var router = JSONRPCRouter()
        runAsync { await server.configureRouter(&router) }

        // Send an initialized notification (no id)
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized"
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
            XCTFail("Failed to serialize request")
            return
        }

        let responseData = runAsync { await router.route(requestData) }

        // Notifications should produce no response
        XCTAssertNil(responseData)

        // Server state should be ready
        let state = runAsync { await server.state }
        XCTAssertEqual(state, .ready)
    }

    func testRouterIntegrationToolsList() {
        let server = makeServer()
        var router = JSONRPCRouter()
        runAsync { await server.configureRouter(&router) }

        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list"
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
            XCTFail("Failed to serialize request")
            return
        }

        let responseData = runAsync { await router.route(requestData) }
        XCTAssertNotNil(responseData)

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse response")
            return
        }

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 2)
        XCTAssertNil(json["error"])

        guard let result = json["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            XCTFail("Expected tools array in result")
            return
        }

        XCTAssertEqual(tools.count, 6)
    }
}

// MARK: - Mock Process Executor

/// A mock process executor that returns configurable responses for testing.
private struct MockProcessExecutor: ProcessExecuting {
    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        // Default: return "false" for Xcode running checks (simulates Xcode not running)
        return ProcessOutput(stdout: "false\n", stderr: "", exitCode: 0)
    }
}
