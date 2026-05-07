import Foundation

/// Routes incoming JSON-RPC messages to registered method handlers.
struct JSONRPCRouter {
    private var handlers: [String: @Sendable (JSONRPCRequest) async -> JSONRPCResponse] = [:]

    /// Registers a method handler for a given JSON-RPC method name.
    mutating func registerMethod(_ method: String, handler: @escaping @Sendable (JSONRPCRequest) async -> JSONRPCResponse) {
        handlers[method] = handler
    }

    /// Routes an incoming message to the appropriate handler.
    /// Returns nil for notifications (no id field).
    /// Returns error -32700 for malformed JSON.
    /// Returns error -32601 for unknown methods.
    func route(_ message: Data) async -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Attempt to parse the JSON
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: message)
        } catch {
            // Check if it's valid JSON at all
            let isValidJSON = (try? JSONSerialization.jsonObject(with: message)) != nil
            if !isValidJSON {
                // Malformed JSON: return parse error with null id
                let errorResponse = JSONRPCNullIdResponse(
                    jsonrpc: "2.0",
                    id: nil,
                    error: JSONRPCError(code: -32700, message: "Parse error", data: nil)
                )
                return try? encoder.encode(errorResponse)
            }
            // Valid JSON but not a valid JSON-RPC request structure: also parse error
            let errorResponse = JSONRPCNullIdResponse(
                jsonrpc: "2.0",
                id: nil,
                error: JSONRPCError(code: -32700, message: "Parse error", data: nil)
            )
            return try? encoder.encode(errorResponse)
        }

        // If there's no id, it's a notification — dispatch handler but return nil
        guard let requestId = request.id else {
            if let handler = handlers[request.method] {
                _ = await handler(request)
            }
            return nil
        }

        // Look up the handler for the method
        guard let handler = handlers[request.method] else {
            let errorResponse = JSONRPCResponse(
                jsonrpc: "2.0",
                id: requestId,
                result: nil,
                error: JSONRPCError(code: -32601, message: "Method not found", data: nil)
            )
            return try? encoder.encode(errorResponse)
        }

        // Dispatch to the handler
        let response = await handler(request)
        return try? encoder.encode(response)
    }
}

/// A response type that allows a null id field, used for parse error responses
/// where the request id cannot be determined.
private struct JSONRPCNullIdResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let error: JSONRPCError?
}
