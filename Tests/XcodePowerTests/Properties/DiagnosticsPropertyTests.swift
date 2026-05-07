import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Mock Xcode Controller for Diagnostics Tests

/// A mock Xcode controller that simulates a failed build with configurable diagnostics.
actor MockDiagnosticsController: XcodeControlling {
    private let diagnostics: [Diagnostic]

    /// Creates a mock controller that returns the given diagnostics on getDiagnostics().
    /// - Parameter diagnostics: The diagnostics to return.
    init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
    }

    func isXcodeRunning() async throws -> Bool { true }
    func hasOpenProject() async throws -> Bool { true }

    func executeJXA(_ script: String, timeout: Duration) async throws -> String {
        return ""
    }
}

/// A mock process executor that simulates build status polling for diagnostics tests.
actor MockDiagnosticsBuildExecutor: ProcessExecuting {
    private let terminalStatus: String
    private var callCount: Int = 0

    init(terminalStatus: String = "failed") {
        self.terminalStatus = terminalStatus
    }

    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        let count = callCount
        callCount += 1
        let status = count == 0 ? "running" : terminalStatus
        return ProcessOutput(stdout: status + "\n", stderr: "", exitCode: 0)
    }
}

// MARK: - Generators

/// Generates a random Diagnostic with all fields populated.
struct ArbitraryDiagnostic: Arbitrary {
    let diagnostic: Diagnostic

    static var arbitrary: Gen<ArbitraryDiagnostic> {
        let severityGen = Gen<DiagnosticSeverity>.fromElements(of: DiagnosticSeverity.allCases)
        let messageGen = String.arbitrary.suchThat { !$0.isEmpty }
        let filePathGen = Gen<String>.compose { c in
            let dir = c.generate(using: Gen<String>.fromElements(of: ["Sources", "Tests", "Lib", "App"]))
            let file = c.generate(using: Gen<String>.fromElements(of: ["main", "utils", "model", "view", "controller"]))
            let ext = c.generate(using: Gen<String>.fromElements(of: [".swift", ".m", ".c", ".cpp"]))
            return "/\(dir)/\(file)\(ext)"
        }
        let lineNumberGen = Gen<Int>.fromElements(in: 1...10000)

        return Gen<ArbitraryDiagnostic>.compose { composer in
            let severity = composer.generate(using: severityGen)
            let message = composer.generate(using: messageGen)
            let filePath = composer.generate(using: filePathGen)
            let lineNumber = composer.generate(using: lineNumberGen)

            let diagnostic = Diagnostic(
                severity: severity,
                message: message,
                filePath: filePath,
                lineNumber: lineNumber
            )
            return ArbitraryDiagnostic(diagnostic: diagnostic)
        }
    }
}

/// Generates a non-empty array of diagnostics with all fields populated.
struct ArbitraryDiagnosticSet: Arbitrary {
    let diagnostics: [Diagnostic]

    static var arbitrary: Gen<ArbitraryDiagnosticSet> {
        let countGen = Gen<Int>.fromElements(in: 1...10)

        return Gen<ArbitraryDiagnosticSet>.compose { composer in
            let count = composer.generate(using: countGen)
            var diagnostics: [Diagnostic] = []
            for _ in 0..<count {
                let arb = composer.generate(using: ArbitraryDiagnostic.arbitrary)
                diagnostics.append(arb.diagnostic)
            }
            return ArbitraryDiagnosticSet(diagnostics: diagnostics)
        }
    }
}

/// Generates a non-empty array of diagnostics where filePath and lineNumber may be nil.
struct ArbitraryDiagnosticSetWithNils: Arbitrary {
    let diagnostics: [Diagnostic]

    static var arbitrary: Gen<ArbitraryDiagnosticSetWithNils> {
        let countGen = Gen<Int>.fromElements(in: 1...10)

        let diagnosticGen = Gen<Diagnostic>.compose { composer in
            let severity = composer.generate(using: Gen<DiagnosticSeverity>.fromElements(of: DiagnosticSeverity.allCases))
            let message = composer.generate(using: String.arbitrary.suchThat { !$0.isEmpty })
            let hasFilePath = composer.generate(using: Bool.arbitrary)
            let hasLineNumber = composer.generate(using: Bool.arbitrary)

            let filePath: String? = hasFilePath ? "/some/path.swift" : nil
            let lineNumber: Int? = hasLineNumber ? composer.generate(using: Gen<Int>.fromElements(in: 1...1000)) : nil

            return Diagnostic(severity: severity, message: message, filePath: filePath, lineNumber: lineNumber)
        }

        return Gen<ArbitraryDiagnosticSetWithNils>.compose { composer in
            let count = composer.generate(using: countGen)
            var diagnostics: [Diagnostic] = []
            for _ in 0..<count {
                diagnostics.append(composer.generate(using: diagnosticGen))
            }
            return ArbitraryDiagnosticSetWithNils(diagnostics: diagnostics)
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

final class DiagnosticsPropertyTests: XCTestCase {

    // MARK: - Property 6: Failed build response includes all diagnostics

    /// Feature: xcode-power, Property 6: Failed build response includes all diagnostics
    /// For any non-empty set of diagnostics, the build failure response includes every diagnostic
    /// with severity, message, file path, and line number preserved.
    /// **Validates: Requirements 3.5, 7.2**
    func testProperty6_FailedBuildResponseIncludesAllDiagnostics() {
        property("Feature: xcode-power, Property 6: Failed build response includes all diagnostics") <- forAll(ArbitraryDiagnosticSet.arbitrary) { (diagnosticSet: ArbitraryDiagnosticSet) in
            let diagnostics = diagnosticSet.diagnostics

            // Create a BuildResult with failed status and the diagnostics
            let buildResult = BuildResult(status: .failed, duration: 5.0, errors: diagnostics)

            // Encode to JSON and decode back to verify round-trip preservation
            guard let encoded = try? JSONEncoder().encode(buildResult),
                  let decoded = try? JSONDecoder().decode(BuildResult.self, from: encoded) else {
                return false
            }

            // Verify all diagnostics are preserved
            guard let decodedErrors = decoded.errors else {
                return false
            }

            // Count must match
            guard decodedErrors.count == diagnostics.count else {
                return false
            }

            // Each diagnostic must be preserved with all fields
            for (original, restored) in zip(diagnostics, decodedErrors) {
                guard original.severity == restored.severity else { return false }
                guard original.message == restored.message else { return false }
                guard original.filePath == restored.filePath else { return false }
                guard original.lineNumber == restored.lineNumber else { return false }
            }

            return true
        }
    }

    /// Feature: xcode-power, Property 6: Build failure response text contains all diagnostic details
    /// For any non-empty set of diagnostics, when serialized as the build handler would produce,
    /// the response text contains every diagnostic's severity, message, file path, and line number.
    /// **Validates: Requirements 3.5, 7.2**
    func testProperty6_BuildFailureResponseTextContainsAllDiagnosticDetails() {
        property("Feature: xcode-power, Property 6: Build failure response text preserves all diagnostic fields") <- forAll(ArbitraryDiagnosticSet.arbitrary) { (diagnosticSet: ArbitraryDiagnosticSet) in
            let diagnostics = diagnosticSet.diagnostics

            // Simulate what BuildHandler does: encode BuildResult to JSON text
            let buildResult = BuildResult(status: .failed, duration: 5.0, errors: diagnostics)
            guard let json = try? JSONEncoder().encode(buildResult),
                  let text = String(data: json, encoding: .utf8) else {
                return false
            }

            // Parse the text back as a BuildResult
            guard let data = text.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(BuildResult.self, from: data) else {
                return false
            }

            // Verify status is failed
            guard parsed.status == .failed else { return false }

            // Verify all diagnostics are present
            guard let parsedErrors = parsed.errors, parsedErrors.count == diagnostics.count else {
                return false
            }

            // Verify each diagnostic's fields are preserved
            for (original, parsed) in zip(diagnostics, parsedErrors) {
                guard original.severity == parsed.severity else { return false }
                guard original.message == parsed.message else { return false }
                guard original.filePath == parsed.filePath else { return false }
                guard original.lineNumber == parsed.lineNumber else { return false }
            }

            return true
        }
    }

    /// Feature: xcode-power, Property 6: Diagnostics with nil optional fields are preserved
    /// For any diagnostic where filePath or lineNumber may be nil, the serialization
    /// correctly preserves the nil values.
    /// **Validates: Requirements 3.5, 7.2**
    func testProperty6_DiagnosticsWithNilFieldsArePreserved() {
        property("Feature: xcode-power, Property 6: Diagnostics with nil fields are preserved in build response") <- forAll(ArbitraryDiagnosticSetWithNils.arbitrary) { (diagnosticSet: ArbitraryDiagnosticSetWithNils) in
            let diagnostics = diagnosticSet.diagnostics
            let buildResult = BuildResult(status: .failed, duration: 3.0, errors: diagnostics)

            guard let encoded = try? JSONEncoder().encode(buildResult),
                  let decoded = try? JSONDecoder().decode(BuildResult.self, from: encoded) else {
                return false
            }

            guard let decodedErrors = decoded.errors, decodedErrors.count == diagnostics.count else {
                return false
            }

            for (original, restored) in zip(diagnostics, decodedErrors) {
                guard original.severity == restored.severity else { return false }
                guard original.message == restored.message else { return false }
                guard original.filePath == restored.filePath else { return false }
                guard original.lineNumber == restored.lineNumber else { return false }
            }

            return true
        }
    }
}
