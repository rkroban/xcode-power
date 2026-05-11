import Foundation

/// Information about an Xcode scheme.
struct SchemeInfo: Codable, Sendable {
    let name: String
}

/// Information about an Xcode run destination (simulator, device, My Mac, etc.).
struct DestinationInfo: Codable, Sendable {
    let name: String
    let platform: String?
    let architecture: String?
}

/// The result of a run action.
struct RunResult: Codable, Sendable {
    let status: String
    let errors: [Diagnostic]?
}
