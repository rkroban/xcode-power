import Foundation

/// Represents a JSON-RPC 2.0 request ID which can be either an integer or string.
enum JSONRPCId: Codable, Equatable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int or String for JSON-RPC id"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// A JSON-RPC 2.0 request message.
struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodable?
}

/// A JSON-RPC 2.0 response message.
struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId
    let result: AnyCodable?
    let error: JSONRPCError?
}

/// A JSON-RPC 2.0 error object.
struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?
}
