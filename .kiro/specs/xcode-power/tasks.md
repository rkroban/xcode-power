# Implementation Plan: Xcode Power

## Overview

This plan implements a Swift-based MCP server that controls Xcode.app via JXA scripting. Tasks are ordered from foundational infrastructure (transport, protocol) through core logic (controllers, monitors, parsers) to tool handlers and final packaging. Property-based tests use SwiftCheck and are placed close to their corresponding implementation tasks.

## Tasks

- [x] 1. Set up Swift package structure and core protocols
  - [x] 1.1 Create Swift Package with directory structure and Package.swift
    - Initialize `Package.swift` with targets: `XcodePower` (executable), `XcodePowerTests` (test target)
    - Add SwiftCheck dependency for property-based testing
    - Create directory structure: `Sources/XcodePower/`, `Tests/XcodePowerTests/Properties/`, `Tests/XcodePowerTests/Unit/`, `Tests/XcodePowerTests/Integration/`
    - _Requirements: 11.3_

  - [x] 1.2 Define core data models and error types
    - Create `Models/JSONRPCModels.swift` with `JSONRPCRequest`, `JSONRPCId`, `JSONRPCResponse`, `JSONRPCError`
    - Create `Models/MCPModels.swift` with `InitializeResult`, `ServerCapabilities`, `ServerInfo`, `ToolDefinition`, `ToolCallParams`, `ToolResult`, `ToolContent`
    - Create `Models/BuildModels.swift` with `BuildStatus`, `BuildResult`, `Diagnostic`, `DiagnosticSeverity`
    - Create `Models/TestModels.swift` with `TestResults`, `TestFailure`, `TestCaseResult`, `TestCaseStatus`
    - Create `Models/SchemeModels.swift` with `SchemeInfo`, `RunResult`
    - Create `Errors/XcodePowerError.swift` with all error cases
    - _Requirements: 1.1, 3.4, 3.5, 4.5, 6.2, 7.2_

  - [x] 1.3 Define protocols for dependency injection
    - Create `Protocols/ProcessExecuting.swift` with `run(command:arguments:timeout:)` method
    - Create `Protocols/XcodeControlling.swift` with `isXcodeRunning()`, `hasOpenProject()`, `executeJXA(_:timeout:)` methods
    - Create `Models/ProcessOutput.swift` with `stdout`, `stderr`, `exitCode` fields
    - _Requirements: 10.1, 10.2, 10.3_

- [x] 2. Implement transport and JSON-RPC routing layer
  - [x] 2.1 Implement StdioTransport actor
    - Create `Transport/StdioTransport.swift` as an actor
    - Implement `readMessage()` reading newline-delimited JSON from stdin
    - Implement `writeMessage(_:)` writing JSON followed by newline to stdout
    - Implement `messages()` returning an `AsyncStream<Data>`
    - Support Content-Length header framing for compatibility
    - _Requirements: 1.3, 9.4_

  - [x] 2.2 Implement JSONRPCRouter
    - Create `Router/JSONRPCRouter.swift`
    - Implement method registration with `registerMethod(_:handler:)`
    - Implement `route(_:)` that parses JSON, dispatches to handlers, returns response Data
    - Return error code -32700 for malformed JSON
    - Return error code -32601 for unknown methods
    - Return nil for notifications (messages without `id`)
    - Ensure every response includes `"jsonrpc": "2.0"` and echoes the request `id`
    - _Requirements: 1.4, 1.5, 9.1, 9.2, 9.3_

  - [x] 2.3 Write property tests for JSON-RPC routing (Properties 1, 2, 10, 11)
    - **Property 1: Malformed JSON produces parse error** — For any byte sequence that is not valid JSON, response contains error code -32700
    - **Property 2: Unknown methods produce method-not-found error** — For any valid JSON-RPC request with unregistered method, response contains error code -32601
    - **Property 10: JSON-RPC response structure compliance** — For any valid request with id, response contains `"jsonrpc": "2.0"` and matching id
    - **Property 11: Notifications produce no response** — For any valid JSON-RPC message without id, no output is produced
    - **Validates: Requirements 1.4, 1.5, 9.1, 9.2, 9.3**

- [x] 3. Implement ProcessExecutor and XcodeController
  - [x] 3.1 Implement ProcessExecutor
    - Create `Execution/ProcessExecutor.swift` conforming to `ProcessExecuting`
    - Wrap Foundation `Process` with async/await execution
    - Capture stdout and stderr as strings
    - Implement timeout using `Task.sleep` with cancellation
    - Throw on non-zero exit code with stderr content
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [x] 3.2 Implement XcodeController actor
    - Create `Controller/XcodeController.swift` as an actor conforming to `XcodeControlling`
    - Implement `isXcodeRunning()` using JXA to check if Xcode process exists
    - Implement `hasOpenProject()` using JXA to check for open workspace/project documents
    - Implement `executeJXA(_:timeout:)` that runs `osascript -l JavaScript` with the given script
    - Implement `build(scheme:)` generating JXA to trigger Xcode build action
    - Implement `test(scheme:testIdentifier:)` generating JXA to trigger Xcode test action
    - Implement `run(scheme:)` generating JXA to trigger Xcode run action
    - Implement `listSchemes()` generating JXA to query available schemes
    - Implement `getDiagnostics()` generating JXA to retrieve build diagnostics
    - Implement `clean(scheme:)` generating JXA to clean build folder
    - Apply 30-second timeout for non-build/test operations
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 4.1, 4.2, 5.1, 5.2, 6.1, 7.1, 8.1, 8.2, 10.1, 10.2, 10.3, 10.4_

  - [x] 3.3 Write property tests for JXA script generation (Properties 3, 4)
    - **Property 3: Scheme parameter propagation** — For any valid scheme name string, the generated JXA script contains that scheme name as the target
    - **Property 4: Test identifier propagation** — For any test identifier (class, method, or class/method), the generated JXA script targets only the specified test
    - **Validates: Requirements 3.1, 4.1, 4.2, 5.2, 8.2**

  - [x] 3.4 Write property test for process error propagation (Property 12)
    - **Property 12: Non-zero JXA exit propagates error** — For any JXA execution with non-zero exit code, the error contains the stderr output
    - **Validates: Requirements 10.3**

- [x] 4. Implement BuildMonitor
  - [x] 4.1 Implement BuildMonitor actor
    - Create `Monitor/BuildMonitor.swift` as an actor
    - Accept a `ProcessExecuting` dependency for testability
    - Implement `awaitCompletion(pollInterval:timeout:)` that polls at 2-second intervals
    - Implement `checkStatus()` executing a lightweight JXA script to query build state
    - Return `.succeeded` or `.failed` when terminal status detected
    - Return `.timedOut` when timeout (300 seconds) exceeded without terminal status
    - _Requirements: 3.3, 3.6, 10.5_
w
  - [x] 4.2 Write property test for BuildMonitor (Property 5)
    - **Property 5: Build monitor terminates with correct status** — For any sequence of poll responses (zero or more "running" followed by terminal status), monitor returns the terminal status; for sequences exceeding timeout, returns "timedOut"
    - **Validates: Requirements 3.3, 3.6**

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement ResultParser
  - [x] 6.1 Implement ResultParser
    - Create `Parser/ResultParser.swift`
    - Implement `findLatestXCResult(derivedDataPath:)` to locate most recent .xcresult bundle
    - Implement `parseTestResults(bundlePath:)` using `xcrun xcresulttool get --format json`
    - Implement `extractTestCases(from:)` to parse xcresulttool JSON into `[TestCaseResult]`
    - Aggregate results into `TestResults` with totalCount, passedCount, failedCount, and failures array
    - Return clear error if no .xcresult bundle found
    - _Requirements: 4.3, 4.4, 4.5, 4.6_

  - [x] 6.2 Write property tests for ResultParser (Properties 7, 8)
    - **Property 7: xcresulttool JSON parsing round-trip** — For any valid xcresulttool JSON output, parsing into TestResults and serializing back preserves counts and failure details
    - **Property 8: Test result aggregation correctness** — For any set of TestCaseResult objects, totalCount equals set size, passedCount equals passed count, failedCount equals failed count, failures array contains exactly the failed cases
    - **Validates: Requirements 4.4, 4.5**

  - [x] 6.3 Write property test for scheme list (Property 9)
    - **Property 9: Scheme list completeness** — For any list of scheme names returned by Xcode query, the response contains exactly those names with no additions or omissions
    - **Validates: Requirements 6.2, 6.3**

- [x] 7. Implement ToolRegistry and tool handlers
  - [x] 7.1 Implement ToolRegistry actor
    - Create `Registry/ToolRegistry.swift` as an actor
    - Register all 6 tools with name, description, and JSON Schema for input parameters
    - Implement `listTools()` returning all tool definitions
    - Implement `callTool(name:arguments:)` dispatching to appropriate handler
    - _Requirements: 9.5_

  - [x] 7.2 Implement xcode_build tool handler
    - Create `Handlers/BuildHandler.swift`
    - Validate optional `scheme` parameter
    - Call XcodeController availability checks before execution
    - Trigger build and await BuildMonitor completion
    - Return BuildResult with status, duration, and errors on failure
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 7.3 Implement xcode_test tool handler
    - Create `Handlers/TestHandler.swift`
    - Validate optional `scheme` and `testIdentifier` parameters
    - Call XcodeController availability checks before execution
    - Trigger test action and await BuildMonitor completion
    - Invoke ResultParser to extract test results from .xcresult bundle
    - Return TestResults with counts and failure details
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x] 7.4 Implement xcode_run, xcode_list_schemes, xcode_get_errors, xcode_clean handlers
    - Create `Handlers/RunHandler.swift` — triggers run action, returns launch status or build errors
    - Create `Handlers/SchemesHandler.swift` — queries schemes, returns array of scheme objects
    - Create `Handlers/ErrorsHandler.swift` — queries diagnostics, returns array of diagnostic objects
    - Create `Handlers/CleanHandler.swift` — triggers clean action, returns success status
    - All handlers perform availability checks before execution
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.3, 7.1, 7.2, 7.3, 8.1, 8.2, 8.3_

  - [x] 7.5 Write property test for diagnostics (Property 6)
    - **Property 6: Failed build response includes all diagnostics** — For any non-empty set of diagnostics, the build failure response includes every diagnostic with severity, message, file path, and line number preserved
    - **Validates: Requirements 3.5, 7.2**

- [x] 8. Implement MCP server initialization and main entry point
  - [x] 8.1 Implement MCP initialize/initialized handshake
    - Register `initialize` method handler returning server name ("xcode-power"), version, and capabilities (tools supported)
    - Register `initialized` notification handler transitioning server to ready state
    - Register `tools/list` method handler returning all tool definitions from ToolRegistry
    - Register `tools/call` method handler dispatching to ToolRegistry
    - _Requirements: 1.1, 1.2, 9.5_

  - [x] 8.2 Implement main entry point and run loop
    - Create `main.swift` as the executable entry point
    - Wire together StdioTransport, JSONRPCRouter, ToolRegistry, XcodeController, BuildMonitor, ResultParser
    - Start the message read loop, routing each message through the JSONRPCRouter
    - Write responses back via StdioTransport
    - Handle graceful shutdown on stdin EOF
    - _Requirements: 1.1, 1.2, 1.3_

  - [x] 8.3 Write unit tests for initialization handshake
    - Test initialize response contains correct server name, version, and capabilities
    - Test state transition from uninitialized to ready after initialized notification
    - Test tools/list returns all 6 tools with correct schemas
    - _Requirements: 1.1, 1.2, 9.5_

- [x] 9. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Power packaging and documentation
  - [x] 10.1 Create POWER.md documentation
    - Document power purpose: fast Xcode builds via warm cache
    - Document all 6 available tools with parameters and example usage
    - Document prerequisites: macOS with Xcode installed and running
    - Document setup requirements and any environment variables
    - Include usage examples showing typical workflows
    - _Requirements: 11.1, 11.4_

  - [x] 10.2 Create mcp.json configuration
    - Specify server command pointing to compiled Swift binary
    - Specify stdio transport type
    - Include any required environment variables
    - _Requirements: 11.2, 11.5_

  - [x] 10.3 Add build instructions for compiling the Swift binary
    - Add build script or Makefile target for `swift build -c release`
    - Document how to produce the compiled binary for distribution
    - Ensure binary is self-contained (statically linked where possible)
    - _Requirements: 11.3_

- [x] 11. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties using SwiftCheck
- Unit tests validate specific examples and edge cases
- The server uses Swift structured concurrency (actors, async/await) throughout
- Protocol-based dependency injection enables testing without real Xcode/process execution
