import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Generators

/// Generates an arbitrary list of unique scheme names.
struct ArbitrarySchemeList: Arbitrary {
    let names: [String]

    static var arbitrary: Gen<ArbitrarySchemeList> {
        // Pool of realistic scheme name components
        let prefixes = ["My", "App", "Core", "UI", "Test", "Dev", "Prod", "Staging", "Debug", "Release"]
        let suffixes = ["App", "Framework", "Tests", "UITests", "Kit", "Module", "Service", "Widget"]

        let schemeNameGen = Gen<String>.compose { composer in
            let prefix = composer.generate(using: Gen<String>.fromElements(of: prefixes))
            let suffix = composer.generate(using: Gen<String>.fromElements(of: suffixes))
            let useHyphen = composer.generate(using: Gen<Bool>.pure(true))
            return useHyphen ? "\(prefix)-\(suffix)" : "\(prefix)\(suffix)"
        }

        // Generate 0-10 unique scheme names
        let countGen = Gen<Int>.fromElements(in: 0...10)

        return Gen<ArbitrarySchemeList>.compose { composer in
            let count = composer.generate(using: countGen)
            var names: Set<String> = []
            // Generate unique names by appending index if needed
            for i in 0..<count {
                var name = composer.generate(using: schemeNameGen)
                if names.contains(name) {
                    name = "\(name)\(i)"
                }
                names.insert(name)
            }
            return ArbitrarySchemeList(names: Array(names))
        }
    }
}

// MARK: - Async Helper

/// Helper to run async code synchronously in tests.
private func runAsync<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task {
        do {
            let value = try await block()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}

// MARK: - Property Tests

final class SchemeListPropertyTests: XCTestCase {

    // MARK: - Property 9: Scheme list completeness

    /// Feature: xcode-power, Property 9: Scheme list completeness
    /// For any list of scheme names returned by Xcode query, the response contains exactly
    /// those names with no additions or omissions.
    /// **Validates: Requirements 6.2, 6.3**
    func testProperty9_SchemeListCompleteness() {
        property("Feature: xcode-power, Property 9: Scheme list contains exactly the queried names") <- forAll(ArbitrarySchemeList.arbitrary) { (schemeList: ArbitrarySchemeList) in
            // The XcodeController uses the mock executor to simulate JXA output.
            // We test that listSchemes correctly round-trips the scheme names through
            // the JXA execution and JSON parsing pipeline.
            let controller = XcodeController(processExecutor: MockSchemeListAlwaysReadyExecutor(schemeNames: schemeList.names))

            do {
                let schemes = try runAsync {
                    try await controller.listSchemes()
                }

                // Verify: exact same names, no additions, no omissions
                let returnedNames = Set(schemes.map { $0.name })
                let expectedNames = Set(schemeList.names)

                // Same count (no duplicates added)
                guard schemes.count == schemeList.names.count else { return false }
                // Same set of names
                guard returnedNames == expectedNames else { return false }

                return true
            } catch {
                return false
            }
        }
    }

    /// Feature: xcode-power, Property 9: Empty scheme list returns empty array
    /// When Xcode reports no schemes, the response is an empty array.
    /// **Validates: Requirements 6.3**
    func testProperty9_EmptySchemeListReturnsEmptyArray() {
        let mockExecutor = MockSchemeListAlwaysReadyExecutor(schemeNames: [])

        let controller = XcodeController(processExecutor: mockExecutor)

        do {
            let schemes = try runAsync {
                try await controller.listSchemes()
            }
            XCTAssertEqual(schemes.count, 0, "Empty scheme list should return empty array")
        } catch {
            XCTFail("Should not throw for empty scheme list: \(error)")
        }
    }
}

// MARK: - Mock Executor that handles both availability checks and scheme listing

/// A mock executor that responds to Xcode availability checks (always ready)
/// and returns scheme names for the list schemes JXA script.
private struct MockSchemeListAlwaysReadyExecutor: ProcessExecuting {
    let schemeNames: [String]

    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        // Detect which JXA script is being run based on the script content
        guard arguments.count >= 3 else {
            return ProcessOutput(stdout: "true\n", stderr: "", exitCode: 0)
        }

        let script = arguments.last ?? ""

        if script.contains("System Events") || script.contains("processes.whose") {
            // isXcodeRunning check
            return ProcessOutput(stdout: "true\n", stderr: "", exitCode: 0)
        } else if script.contains("workspaceDocuments().length") {
            // hasOpenProject check — not needed for listSchemes (requireProject: false)
            return ProcessOutput(stdout: "true\n", stderr: "", exitCode: 0)
        } else if script.contains("schemes()") || script.contains("JSON.stringify(names)") {
            // listSchemes JXA script
            let jsonData = try! JSONSerialization.data(withJSONObject: schemeNames)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            return ProcessOutput(stdout: jsonString + "\n", stderr: "", exitCode: 0)
        } else {
            // Default: return true for any other check
            return ProcessOutput(stdout: "true\n", stderr: "", exitCode: 0)
        }
    }
}
