import Foundation

/// Information about a Swift Package Manager dependency in the project.
struct PackageInfo: Codable, Sendable {
    let name: String
    let repositoryURL: String
    let versionType: String
    let versionValue: String
}

/// Information about a build target in the project.
struct TargetInfo: Codable, Sendable {
    let name: String
    let productType: String
    let bundleIdentifier: String?
}

/// The type of a linked framework or library.
enum FrameworkType: String, Codable, Sendable {
    case system
    case spmProduct
    case projectRelative
}

/// Information about a framework or library linked to a target.
struct FrameworkInfo: Codable, Sendable {
    let name: String
    let isRequired: Bool
    let type: FrameworkType
}
