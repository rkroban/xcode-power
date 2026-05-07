import XCTest
import SwiftCheck
@testable import XcodePower

/// Helper to run async code synchronously in tests.
func runAsync<T>(_ block: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: T!
    Task {
        result = await block()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

// MARK: - Generators

/// Generates byte sequences that are NOT valid JSON.
struct InvalidJSONGenerator: Arbitrary {
    let data: Data

    static var arbitrary: Gen<InvalidJSONGenerator> {
        return Gen<InvalidJSONGenerator>.one(of: [
            // Random strings that aren't valid JSON (prefixed with invalid chars)
            String.arbitrary.map { str in
                let invalid = "<<<\(str)>>>"
                return InvalidJSONGenerator(data: invalid.data(using: .utf8)!)
            },
            // Random alphanumeric strings that can't be valid JSON
            String.arbitrary.map { str in
                let invalid = "abc\(str)xyz"
                return InvalidJSONGenerator(data: invalid.data(using: .utf8)!)
            },
            // Truncated/malformed JSON structures
            String.arbitrary.map { str in
                return InvalidJSONGenerator(data: "{\"key\": \(str)".data(using: .utf8)!)
            },
            // Single characters that aren't valid JSON
            Gen.pure(InvalidJSONGenerator(data: "not json at all".data(using: .utf8)!)),
            Gen.pure(InvalidJSONGenerator(data: "{\"incomplete".data(using: .utf8)!)),
            Gen.pure(InvalidJSONGenerator(data: "[1, 2,".data(using: .utf8)!)),
        ])
    }
}

/// Generates method name strings that are NOT registered in the router.
struct UnregisteredMethodName: Arbitrary {
    let name: String

    static var arbitrary: Gen<UnregisteredMethodName> {
        return String.arbitrary
            .suchThat { !$0.isEmpty }
            .map { str in
                // Prefix with "unregistered_" to ensure it's never a registered method
                UnregisteredMethodName(name: "unregistered_\(str)")
            }
    }
}

/// Generates valid JSON-RPC IDs (int or string).
struct ArbitraryJSONRPCId: Arbitrary {
    let id: JSONRPCId

    static var arbitrary: Gen<ArbitraryJSONRPCId> {
        return Gen<ArbitraryJSONRPCId>.one(of: [
            Int.arbitrary.map { ArbitraryJSONRPCId(id: .int($0)) },
            String.arbitrary.suchThat { !$0.isEmpty }.map { ArbitraryJSONRPCId(id: .string($0)) }
        ])
    }
}

// MARK: - Property Tests

final class JSONRPCPropertyTests: XCTestCase {

    // MARK: - Property 1: Malformed JSON produces parse error

    /// Feature: xcode-power, Property 1: Malformed JSON produces parse error
    /// **Validates: Requirements 1.4**
    func testProperty1_MalformedJSONProducesParseError() {
        property("Feature: xcode-power, Property 1: Malformed JSON produces parse error") <- forAll(InvalidJSONGenerator.arbitrary) { (invalidJSON: InvalidJSONGenerator) in
            let router = JSONRPCRouter()
            let responseData = runAsync { await router.route(invalidJSON.data) }

            // Malformed JSON should always produce a response (not nil)
            guard let data = responseData else {
                return false
            }

            // Parse the response and check for error code -32700
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let error = json["error"] as? [String: Any],
                  let code = error["code"] as? Int else {
                return false
            }

            return code == -32700
        }
    }

    // MARK: - Property 2: Unknown methods produce method-not-found error

    /// Feature: xcode-power, Property 2: Unknown methods produce method-not-found error
    /// **Validates: Requirements 1.5**
    func testProperty2_UnknownMethodsProduceMethodNotFound() {
        property("Feature: xcode-power, Property 2: Unknown methods produce method-not-found error") <- forAll(UnregisteredMethodName.arbitrary, ArbitraryJSONRPCId.arbitrary) { (method: UnregisteredMethodName, arbId: ArbitraryJSONRPCId) in
            let router = JSONRPCRouter()

            // Build a valid JSON-RPC request with the unregistered method
            var requestDict: [String: Any] = [
                "jsonrpc": "2.0",
                "method": method.name
            ]

            // Set the id
            switch arbId.id {
            case .int(let intVal):
                requestDict["id"] = intVal
            case .string(let strVal):
                requestDict["id"] = strVal
            }

            guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
                return false
            }

            let responseData = runAsync { await router.route(requestData) }

            // Should produce a response (has an id)
            guard let data = responseData else {
                return false
            }

            // Parse the response and check for error code -32601
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let error = json["error"] as? [String: Any],
                  let code = error["code"] as? Int else {
                return false
            }

            return code == -32601
        }
    }

    // MARK: - Property 10: JSON-RPC response structure compliance

    /// Feature: xcode-power, Property 10: JSON-RPC response structure compliance
    /// **Validates: Requirements 9.1, 9.2**
    func testProperty10_ResponseStructureCompliance() {
        // Create router with a registered echo handler
        var router = JSONRPCRouter()
        router.registerMethod("echo") { request in
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: request.id!,
                result: AnyCodable("ok"),
                error: nil
            )
        }
        let configuredRouter = router

        property("Feature: xcode-power, Property 10: JSON-RPC response structure compliance") <- forAll(ArbitraryJSONRPCId.arbitrary) { (arbId: ArbitraryJSONRPCId) in
            // Build a valid JSON-RPC request
            var requestDict: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "echo"
            ]

            switch arbId.id {
            case .int(let intVal):
                requestDict["id"] = intVal
            case .string(let strVal):
                requestDict["id"] = strVal
            }

            guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
                return false
            }

            let responseData = runAsync { await configuredRouter.route(requestData) }

            guard let data = responseData else {
                return false
            }

            // Parse the response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            // Check jsonrpc field is "2.0"
            guard let jsonrpc = json["jsonrpc"] as? String, jsonrpc == "2.0" else {
                return false
            }

            // Check id matches the request id
            switch arbId.id {
            case .int(let expectedInt):
                guard let responseId = json["id"] as? Int, responseId == expectedInt else {
                    return false
                }
            case .string(let expectedStr):
                guard let responseId = json["id"] as? String, responseId == expectedStr else {
                    return false
                }
            }

            return true
        }
    }

    // MARK: - Property 11: Notifications produce no response

    /// Feature: xcode-power, Property 11: Notifications produce no response
    /// **Validates: Requirements 9.3**
    func testProperty11_NotificationsProduceNoResponse() {
        property("Feature: xcode-power, Property 11: Notifications produce no response") <- forAll(String.arbitrary.suchThat { !$0.isEmpty }) { (methodName: String) in
            var router = JSONRPCRouter()

            // Register a handler for the method (shouldn't matter for notifications)
            router.registerMethod(methodName) { request in
                return JSONRPCResponse(
                    jsonrpc: "2.0",
                    id: request.id ?? .int(0),
                    result: AnyCodable("ok"),
                    error: nil
                )
            }
            let configuredRouter = router

            // Build a valid JSON-RPC notification (no id field)
            let requestDict: [String: Any] = [
                "jsonrpc": "2.0",
                "method": methodName
            ]

            guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict) else {
                return false
            }

            let responseData = runAsync { await configuredRouter.route(requestData) }

            // Notifications should produce nil (no response)
            return responseData == nil
        }
    }
}
