import Foundation

/// Information about an Xcode scheme.
struct SchemeInfo: Codable, Sendable {
    let name: String
}

/// The result of a run action.
struct RunResult: Codable, Sendable {
    let status: String
    let errors: [Diagnostic]?
}
