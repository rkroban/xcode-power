import XCTest
import SwiftCheck
@testable import XcodePower

// MARK: - Generators

/// Generates valid scheme name strings (non-empty, alphanumeric with spaces/hyphens/underscores).
struct ValidSchemeName: Arbitrary {
    let name: String

    static var arbitrary: Gen<ValidSchemeName> {
        let allowedChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_")
        return Gen<Character>.fromElements(of: allowedChars)
            .proliferateNonEmpty
            .map { chars in ValidSchemeName(name: String(chars)) }
    }
}

/// Generates test identifier strings in formats like "ClassName", "ClassName/testMethodName", "testMethodName".
struct ValidTestIdentifier: Arbitrary {
    let identifier: String

    static var arbitrary: Gen<ValidTestIdentifier> {
        let alphaChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let alphanumChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

        // Generate a valid identifier segment (starts with letter, followed by alphanumeric/underscore)
        let segment: Gen<String> = Gen<Character>.fromElements(of: alphaChars).flatMap { first in
            Gen<Character>.fromElements(of: alphanumChars)
                .proliferate
                .map { rest in String(first) + String(rest) }
        }

        return Gen<ValidTestIdentifier>.one(of: [
            // ClassName only
            segment.map { ValidTestIdentifier(identifier: $0) },
            // ClassName/testMethodName
            segment.flatMap { className in
                segment.map { methodName in
                    ValidTestIdentifier(identifier: "\(className)/\(methodName)")
                }
            },
            // testMethodName only (prefixed with "test")
            segment.map { ValidTestIdentifier(identifier: "test\($0)") }
        ])
    }
}

// MARK: - Property Tests

final class JXAGenerationPropertyTests: XCTestCase {

    // MARK: - Property 3: Scheme parameter propagation

    /// Feature: xcode-power, Property 3: Scheme parameter propagation
    /// **Validates: Requirements 3.1, 5.2, 8.2**
    func testProperty3_SchemeParameterPropagation() {
        property("Feature: xcode-power, Property 3: Scheme parameter propagation") <- forAll(ValidSchemeName.arbitrary) { (scheme: ValidSchemeName) in
            let escapedName = XcodeController.escapeJXAString(scheme.name)

            // jxaBuild contains the escaped scheme name
            let buildScript = XcodeController.jxaBuild(scheme: scheme.name)
            guard buildScript.contains(escapedName) else { return false }

            // jxaTest with nil testIdentifier contains the escaped scheme name
            let testScript = XcodeController.jxaTest(scheme: scheme.name, testIdentifier: nil)
            guard testScript.contains(escapedName) else { return false }

            // jxaRun contains the escaped scheme name
            let runScript = XcodeController.jxaRun(scheme: scheme.name)
            guard runScript.contains(escapedName) else { return false }

            // jxaClean contains the escaped scheme name
            let cleanScript = XcodeController.jxaClean(scheme: scheme.name)
            guard cleanScript.contains(escapedName) else { return false }

            return true
        }
    }

    // MARK: - Property 4: Test identifier propagation

    /// Feature: xcode-power, Property 4: Test identifier propagation
    /// **Validates: Requirements 4.1, 4.2**
    func testProperty4_TestIdentifierPropagation() {
        property("Feature: xcode-power, Property 4: Test identifier propagation") <- forAll(ValidTestIdentifier.arbitrary) { (testId: ValidTestIdentifier) in
            let escapedId = XcodeController.escapeJXAString(testId.identifier)

            // jxaTest with nil scheme contains the escaped test identifier
            let scriptNoScheme = XcodeController.jxaTest(scheme: nil, testIdentifier: testId.identifier)
            guard scriptNoScheme.contains(escapedId) else { return false }

            // jxaTest with a scheme also contains the escaped test identifier
            let scriptWithScheme = XcodeController.jxaTest(scheme: "SomeScheme", testIdentifier: testId.identifier)
            guard scriptWithScheme.contains(escapedId) else { return false }

            return true
        }
    }
}
