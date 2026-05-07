# Requirements Document

## Introduction

The Xcode Power is a Kiro Power that provides fast Xcode build, test, and run capabilities through an MCP server written in Swift. It controls Xcode.app directly via AppleScript/JXA to leverage Xcode's warm build cache, avoiding the cold-start penalty of `xcodebuild` command-line invocations. The MCP server communicates over JSON-RPC via stdio and exposes tools for building, testing, running, listing schemes, retrieving errors, and cleaning projects.

## Glossary

- **MCP_Server**: The Swift-based Model Context Protocol server that receives JSON-RPC requests over stdio and dispatches Xcode automation commands
- **Xcode_Controller**: The component responsible for sending AppleScript/JXA commands to Xcode.app and interpreting responses
- **Build_Monitor**: The component that monitors Xcode build progress by polling build status after triggering a build via AppleScript
- **Result_Parser**: The component that extracts structured test results from .xcresult bundles using `xcrun xcresulttool`
- **Scheme**: An Xcode build configuration that defines a set of targets, build settings, and actions
- **Derived_Data**: Xcode's cached build artifacts that enable incremental (warm) builds
- **xcresult_Bundle**: A structured output bundle produced by Xcode containing build logs, test results, and code coverage data
- **JSON_RPC**: The JSON-based remote procedure call protocol used for communication between Kiro and the MCP server over stdio
- **JXA**: JavaScript for Automation, Apple's JavaScript-based scripting interface for macOS automation

## Requirements

### Requirement 1: MCP Server Initialization

**User Story:** As a Kiro user, I want the MCP server to start and establish communication over stdio, so that Kiro can send tool requests to control Xcode.

#### Acceptance Criteria

1. WHEN a JSON-RPC `initialize` request is received, THE MCP_Server SHALL respond with a valid `initialize` result containing the server name, version, and supported capabilities
2. WHEN a JSON-RPC `initialized` notification is received, THE MCP_Server SHALL transition to the ready state and begin accepting tool call requests
3. THE MCP_Server SHALL read JSON-RPC messages from stdin and write JSON-RPC responses to stdout
4. IF the MCP_Server receives a malformed JSON-RPC message, THEN THE MCP_Server SHALL respond with a JSON-RPC error containing error code -32700 (Parse error)
5. IF the MCP_Server receives a request with an unknown method, THEN THE MCP_Server SHALL respond with a JSON-RPC error containing error code -32601 (Method not found)

### Requirement 2: Xcode Availability Detection

**User Story:** As a Kiro user, I want the server to detect whether Xcode is running and has a project open, so that I receive clear error messages instead of cryptic failures.

#### Acceptance Criteria

1. WHEN a tool call is received, THE Xcode_Controller SHALL verify that Xcode.app is running before executing the command
2. IF Xcode.app is not running, THEN THE Xcode_Controller SHALL return an error with the message "Xcode is not running" and a suggestion to open Xcode
3. WHEN a build, test, or run tool call is received, THE Xcode_Controller SHALL verify that a workspace or project document is open in Xcode
4. IF no workspace or project document is open in Xcode, THEN THE Xcode_Controller SHALL return an error with the message "No project or workspace is open in Xcode"
5. IF Xcode becomes unresponsive during command execution, THEN THE Xcode_Controller SHALL return a timeout error after 30 seconds of no response

### Requirement 3: Build Project

**User Story:** As a developer, I want to trigger a build in Xcode through the MCP server, so that I get fast incremental builds using Xcode's warm cache.

#### Acceptance Criteria

1. WHEN an `xcode_build` tool call is received with a scheme parameter, THE Xcode_Controller SHALL instruct Xcode to build the specified scheme
2. WHEN an `xcode_build` tool call is received without a scheme parameter, THE Xcode_Controller SHALL instruct Xcode to build the active scheme
3. WHEN a build is triggered, THE Build_Monitor SHALL poll Xcode's build status until the build completes or a timeout of 300 seconds is reached
4. WHEN a build completes successfully, THE MCP_Server SHALL return a result containing the build status "succeeded" and the build duration
5. IF a build fails, THEN THE MCP_Server SHALL return a result containing the build status "failed" and an array of error messages with file paths and line numbers
6. IF a build times out after 300 seconds, THEN THE MCP_Server SHALL return an error indicating the build exceeded the maximum wait time

### Requirement 4: Run Tests

**User Story:** As a developer, I want to run tests through Xcode's test action, so that I get fast test execution with warm build cache and structured results.

#### Acceptance Criteria

1. WHEN an `xcode_test` tool call is received with a scheme parameter, THE Xcode_Controller SHALL instruct Xcode to run tests for the specified scheme
2. WHEN an `xcode_test` tool call is received with a test identifier parameter, THE Xcode_Controller SHALL instruct Xcode to run only the specified test class or method
3. WHEN tests complete, THE Result_Parser SHALL locate the most recent .xcresult bundle in the derived data directory
4. WHEN a .xcresult bundle is found, THE Result_Parser SHALL extract test results using `xcrun xcresulttool get --format json`
5. THE MCP_Server SHALL return test results containing: total test count, passed count, failed count, and for each failed test the test name, failure message, and source location
6. IF no .xcresult bundle is found after test execution, THEN THE Result_Parser SHALL return an error indicating test results could not be located

### Requirement 5: Run Application

**User Story:** As a developer, I want to launch my application through Xcode's run action, so that I can quickly iterate on my app using the warm build cache.

#### Acceptance Criteria

1. WHEN an `xcode_run` tool call is received, THE Xcode_Controller SHALL instruct Xcode to build and run the active scheme
2. WHEN an `xcode_run` tool call is received with a scheme parameter, THE Xcode_Controller SHALL instruct Xcode to build and run the specified scheme
3. WHEN the run action is triggered successfully, THE MCP_Server SHALL return a result indicating the application was launched
4. IF the build phase of the run action fails, THEN THE MCP_Server SHALL return the build errors following the same format as the `xcode_build` tool

### Requirement 6: List Schemes

**User Story:** As a developer, I want to list available schemes in the current Xcode workspace, so that I can choose which scheme to build or test.

#### Acceptance Criteria

1. WHEN an `xcode_list_schemes` tool call is received, THE Xcode_Controller SHALL query Xcode for all schemes in the active workspace or project
2. THE MCP_Server SHALL return an array of scheme objects, each containing the scheme name
3. IF no schemes are available, THEN THE MCP_Server SHALL return an empty array

### Requirement 7: Get Build Errors

**User Story:** As a developer, I want to retrieve the current build errors and warnings from Xcode, so that I can understand what needs to be fixed without triggering a new build.

#### Acceptance Criteria

1. WHEN an `xcode_get_errors` tool call is received, THE Xcode_Controller SHALL query Xcode for current build diagnostics
2. THE MCP_Server SHALL return an array of diagnostic objects, each containing: severity (error or warning), message text, file path, and line number
3. IF no diagnostics are present, THEN THE MCP_Server SHALL return an empty array

### Requirement 8: Clean Build

**User Story:** As a developer, I want to clean the build folder through Xcode, so that I can resolve stale cache issues when needed.

#### Acceptance Criteria

1. WHEN an `xcode_clean` tool call is received, THE Xcode_Controller SHALL instruct Xcode to clean the build folder for the active scheme
2. WHEN an `xcode_clean` tool call is received with a scheme parameter, THE Xcode_Controller SHALL instruct Xcode to clean the build folder for the specified scheme
3. WHEN the clean action completes, THE MCP_Server SHALL return a result indicating the clean succeeded

### Requirement 9: JSON-RPC Protocol Compliance

**User Story:** As a Kiro integration developer, I want the MCP server to fully comply with JSON-RPC 2.0 and the MCP specification, so that it integrates seamlessly with Kiro.

#### Acceptance Criteria

1. THE MCP_Server SHALL include `"jsonrpc": "2.0"` in every response message
2. THE MCP_Server SHALL match the `id` field from the request in the corresponding response
3. WHEN a notification (request without `id`) is received, THE MCP_Server SHALL not send a response
4. THE MCP_Server SHALL support Content-Length headers in the stdio transport framing
5. THE MCP_Server SHALL list all available tools in response to a `tools/list` request, with each tool including a name, description, and JSON Schema for its input parameters

### Requirement 10: AppleScript/JXA Execution

**User Story:** As a developer of the MCP server, I want a reliable mechanism to execute AppleScript/JXA commands against Xcode, so that the server can control Xcode programmatically.

#### Acceptance Criteria

1. THE Xcode_Controller SHALL execute JXA scripts using the `osascript` command with the `-l JavaScript` flag
2. WHEN a JXA script produces output, THE Xcode_Controller SHALL capture and parse the stdout result
3. IF a JXA script exits with a non-zero status code, THEN THE Xcode_Controller SHALL capture stderr and include the error description in the tool response
4. THE Xcode_Controller SHALL set a per-command execution timeout of 30 seconds for JXA scripts that are not build or test operations
5. WHILE a build or test operation is in progress, THE Build_Monitor SHALL use a separate polling JXA script to check completion status at 2-second intervals

### Requirement 11: Power Packaging

**User Story:** As a Kiro user, I want the power to be properly packaged with documentation and configuration, so that I can install and use it through Kiro's power management.

#### Acceptance Criteria

1. THE Power SHALL include a POWER.md file documenting the power's purpose, available tools, setup requirements, and usage examples
2. THE Power SHALL include an mcp.json file specifying the server command, arguments, and any required environment variables
3. THE Power SHALL include a compiled Swift binary as the MCP server executable
4. THE POWER.md SHALL document that macOS with Xcode installed is a prerequisite for using the power
5. THE mcp.json SHALL specify the stdio transport type for the MCP server connection
