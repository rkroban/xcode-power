import Foundation

/// The result of an MCP initialize request.
struct InitializeResult: Codable, Sendable {
    let protocolVersion: String
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo
}

/// Server capabilities advertised during initialization.
struct ServerCapabilities: Codable, Sendable {
    let tools: ToolsCapability?
}

/// Capability descriptor for tools support.
struct ToolsCapability: Codable, Sendable {
    let listChanged: Bool?
}

/// Information about the MCP server.
struct ServerInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// Definition of a tool exposed by the MCP server.
struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let inputSchema: AnyCodable
}

/// Parameters for a tools/call request.
struct ToolCallParams: Codable, Sendable {
    let name: String
    let arguments: [String: AnyCodable]?
}

/// The result of a tool call.
struct ToolResult: Codable, Sendable {
    let content: [ToolContent]
    let isError: Bool?
}

/// A content item within a tool result.
struct ToolContent: Codable, Sendable {
    let type: String
    let text: String
}
