import Foundation

/// The status of a build operation.
enum BuildStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case timedOut
}

/// The result of a build operation.
struct BuildResult: Codable, Sendable {
    let status: BuildStatus
    let duration: Double?
    let errors: [Diagnostic]?
}

/// A build diagnostic (error or warning).
struct Diagnostic: Codable, Sendable {
    let severity: DiagnosticSeverity
    let message: String
    let filePath: String?
    let lineNumber: Int?
}

/// The severity level of a diagnostic.
enum DiagnosticSeverity: String, Codable, Sendable, CaseIterable {
    case error
    case warning
}
