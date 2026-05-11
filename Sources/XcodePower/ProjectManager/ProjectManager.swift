import Foundation
import PathKit
import XcodeProj

/// Errors specific to project management operations.
enum ProjectManagerError: Error, Sendable {
    /// The specified project path does not exist on disk.
    case pathNotFound(path: String)

    /// The path exists but is not a valid `.xcodeproj` bundle (missing extension or `project.pbxproj`).
    case invalidProjectBundle(path: String)

    /// Xcode is not running or has no open workspace, so the project path cannot be auto-resolved.
    case cannotResolveProjectPath(reason: String)

    /// A write operation timed out waiting for access (30-second limit).
    case writeTimeout

    /// Failed to parse the project file.
    case projectParseError(path: String, reason: String)

    /// A write operation failed after acquiring the lock.
    case writeFailed(reason: String)

    /// The specified target was not found in the project.
    case targetNotFound(name: String)

    /// The provided URL is invalid (missing scheme or host).
    case invalidURL(url: String)

    /// The provided version string is not valid for the given version type.
    case invalidVersion(versionType: String, value: String)

    /// A package with the same repository URL already exists in the project.
    case duplicatePackage(url: String)

    /// A target with the same name already exists in the project.
    case duplicateTarget(name: String)

    /// The provided product type is not supported.
    case unsupportedProductType(productType: String, supported: [String])

    /// The provided target name is empty or invalid.
    case invalidTargetName(name: String)

    /// No package matching the provided identifier was found.
    case packageNotFound(identifier: String)

    /// The provided identifier matches more than one package dependency.
    case ambiguousPackageMatch(identifier: String, matches: [String])

    /// The provided package identifier is empty or contains only whitespace.
    case invalidPackageIdentifier

    /// The framework is already linked to the target.
    case frameworkAlreadyLinked(framework: String, target: String)

    /// An SPM package product requires the package to be added as a dependency first.
    case packageDependencyRequired(product: String)

    /// A project-relative framework file was not found at the expected path.
    case frameworkFileNotFound(path: String)

    /// The specified framework was not found in the target's link phase.
    case frameworkNotFound(framework: String, target: String)
}

/// Actor responsible for reading and writing Xcode project files (`.pbxproj`) using XcodeProj.
/// Provides actor isolation for concurrent access safety and serializes write operations
/// with a 30-second timeout to prevent concurrent modifications.
actor ProjectManager {

    /// The Xcode controller used for JXA scripting (project path resolution).
    private let controller: XcodeController

    /// Semaphore to serialize write operations. Only one write can proceed at a time.
    private let writeSemaphore = WriteSemaphore()

    /// Creates a ProjectManager with the given Xcode controller.
    /// - Parameter controller: The Xcode controller for JXA-based project path resolution.
    init(controller: XcodeController) {
        self.controller = controller
    }

    // MARK: - Project Path Resolution

    /// Resolves the project path, either from an explicit parameter or by querying Xcode.
    ///
    /// - Parameter explicit: An explicit project path provided by the user. If `nil`, the path
    ///   is resolved by querying the frontmost Xcode workspace document via JXA.
    /// - Returns: The validated absolute path to the `.xcodeproj` bundle.
    /// - Throws: `ProjectManagerError` if the path cannot be resolved or is invalid.
    func resolveProjectPath(explicit: String?) async throws -> String {
        let path: String

        if let explicit = explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            path = explicit
        } else {
            path = try await resolveFromXcode()
        }

        try validateProjectPath(path)
        return path
    }

    // MARK: - List Packages

    /// Lists all remote Swift Package Manager dependencies in the project.
    ///
    /// - Parameter projectPath: The validated absolute path to the `.xcodeproj` bundle.
    /// - Returns: An array of `PackageInfo` representing each remote package dependency.
    /// - Throws: `ProjectManagerError.projectParseError` if the project file cannot be parsed.
    func listPackages(projectPath: String) async throws -> [PackageInfo] {
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        let packages = rootObject.remotePackages
        return packages.map { package in
            let url = package.repositoryURL ?? ""
            let name = package.name ?? url
            let (versionType, versionValue) = extractVersionInfo(from: package.versionRequirement)
            return PackageInfo(
                name: name,
                repositoryURL: url,
                versionType: versionType,
                versionValue: versionValue
            )
        }
    }

    // MARK: - Add Package

    /// Adds a remote Swift Package Manager dependency to the project.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - url: The repository URL for the package.
    ///   - versionType: The version requirement type ("from", "exact", "branch", or "revision").
    ///   - versionValue: The version value corresponding to the version type.
    /// - Throws: `ProjectManagerError` if validation fails, the package is a duplicate, or the write fails.
    func addPackage(projectPath: String, url: String, versionType: String, versionValue: String) async throws {
        // Validate URL format
        try validatePackageURL(url)

        // Validate version requirement
        try validateVersionRequirement(versionType: versionType, versionValue: versionValue)

        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Check for duplicate by repository URL
        let existingPackages = rootObject.remotePackages
        if existingPackages.contains(where: { $0.repositoryURL == url }) {
            throw ProjectManagerError.duplicatePackage(url: url)
        }

        // Create version requirement
        let versionRequirement = makeVersionRequirement(versionType: versionType, versionValue: versionValue)

        // Create the package reference
        let packageReference = XCRemoteSwiftPackageReference(
            repositoryURL: url,
            versionRequirement: versionRequirement
        )

        // Add to project objects and root object's package references
        project.pbxproj.add(object: packageReference)
        var updatedPackages = rootObject.remotePackages
        updatedPackages.append(packageReference)
        rootObject.remotePackages = updatedPackages

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Remove Package

    /// Removes a Swift Package Manager dependency from the project.
    /// Matches the identifier against repository URL (exact) and package name (case-insensitive).
    /// Also removes all XCSwiftPackageProductDependency references from all targets.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - identifier: The package identifier (repository URL or package name).
    /// - Throws: `ProjectManagerError` if the identifier is invalid, not found, ambiguous, or the write fails.
    func removePackage(projectPath: String, identifier: String) async throws {
        // Validate identifier is not empty
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            throw ProjectManagerError.invalidPackageIdentifier
        }

        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Find matching packages by repository URL (exact) or package name (case-insensitive)
        let packages = rootObject.remotePackages
        var matchingPackages: [XCRemoteSwiftPackageReference] = []

        for package in packages {
            let repositoryURL = package.repositoryURL ?? ""

            // Exact match against repository URL
            if repositoryURL == trimmedIdentifier {
                matchingPackages.append(package)
                continue
            }

            // Case-insensitive match against package name derived from URL
            let packageName = derivePackageName(from: repositoryURL)
            if packageName.lowercased() == trimmedIdentifier.lowercased() {
                matchingPackages.append(package)
            }
        }

        // Handle no matches
        guard !matchingPackages.isEmpty else {
            throw ProjectManagerError.packageNotFound(identifier: trimmedIdentifier)
        }

        // Handle ambiguous matches
        if matchingPackages.count > 1 {
            let matchDescriptions = matchingPackages.map { package -> String in
                let url = package.repositoryURL ?? ""
                let name = derivePackageName(from: url)
                return "\(name) (\(url))"
            }
            throw ProjectManagerError.ambiguousPackageMatch(
                identifier: trimmedIdentifier,
                matches: matchDescriptions
            )
        }

        // Remove the single matching package
        let packageToRemove = matchingPackages[0]

        // Remove all XCSwiftPackageProductDependency references from all targets
        let nativeTargets = rootObject.targets.compactMap { $0 as? PBXNativeTarget }
        for target in nativeTargets {
            // Remove package product dependencies that belong to this package
            target.packageProductDependencies = (target.packageProductDependencies ?? []).filter { productDep in
                productDep.package !== packageToRemove
            }

            // Also remove build files from frameworks phase that reference products of this package
            if let frameworksPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) as? PBXFrameworksBuildPhase,
               let files = frameworksPhase.files {
                let filesToRemove = files.filter { buildFile in
                    if let product = buildFile.product {
                        return product.package === packageToRemove
                    }
                    return false
                }
                for buildFile in filesToRemove {
                    frameworksPhase.files?.removeAll { $0 === buildFile }
                    project.pbxproj.delete(object: buildFile)
                }
            }
        }

        // Remove the XCRemoteSwiftPackageReference from the project
        rootObject.remotePackages = rootObject.remotePackages.filter { $0 !== packageToRemove }
        project.pbxproj.delete(object: packageToRemove)

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    /// Derives the package name from a repository URL by taking the last path component
    /// and removing the `.git` suffix if present.
    private func derivePackageName(from url: String) -> String {
        let lastComponent = url.split(separator: "/").last.map(String.init) ?? url
        if lastComponent.hasSuffix(".git") {
            return String(lastComponent.dropLast(4))
        }
        return lastComponent
    }

    // MARK: - Package Validation Helpers

    /// Validates that the URL has a scheme and host component.
    private func validatePackageURL(_ url: String) throws {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else {
            throw ProjectManagerError.invalidURL(url: url)
        }
    }

    /// Validates the version requirement based on the version type.
    private func validateVersionRequirement(versionType: String, versionValue: String) throws {
        switch versionType {
        case "from", "exact":
            guard isValidSemver(versionValue) else {
                throw ProjectManagerError.invalidVersion(versionType: versionType, value: versionValue)
            }
        case "branch":
            guard !versionValue.isEmpty else {
                throw ProjectManagerError.invalidVersion(versionType: versionType, value: versionValue)
            }
        case "revision":
            guard isValidRevision(versionValue) else {
                throw ProjectManagerError.invalidVersion(versionType: versionType, value: versionValue)
            }
        default:
            throw ProjectManagerError.invalidVersion(versionType: versionType, value: versionValue)
        }
    }

    /// Checks if a string is a valid semantic version (major.minor.patch).
    private func isValidSemver(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isNumber }
        }
    }

    /// Checks if a string is a valid 40-character hexadecimal revision hash.
    private func isValidRevision(_ revision: String) -> Bool {
        guard revision.count == 40 else { return false }
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return revision.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }

    /// Creates a VersionRequirement from the validated type and value.
    private func makeVersionRequirement(
        versionType: String,
        versionValue: String
    ) -> XCRemoteSwiftPackageReference.VersionRequirement {
        switch versionType {
        case "from":
            return .upToNextMajorVersion(versionValue)
        case "exact":
            return .exact(versionValue)
        case "branch":
            return .branch(versionValue)
        case "revision":
            return .revision(versionValue)
        default:
            // This should never be reached due to prior validation
            return .upToNextMajorVersion(versionValue)
        }
    }

    // MARK: - List Targets

    /// Lists all native targets and aggregate targets in the project.
    ///
    /// - Parameter projectPath: The validated absolute path to the `.xcodeproj` bundle.
    /// - Returns: An array of `TargetInfo` representing each target in the project.
    /// - Throws: `ProjectManagerError.projectParseError` if the project file cannot be parsed.
    func listTargets(projectPath: String) async throws -> [TargetInfo] {
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        let targets = rootObject.targets
        return targets.map { target in
            let name = target.name
            let productType: String
            if let nativeTarget = target as? PBXNativeTarget {
                productType = nativeTarget.productType?.rawValue ?? "unknown"
            } else if target is PBXAggregateTarget {
                productType = "aggregate"
            } else {
                productType = "unknown"
            }

            // Extract bundle identifier from build settings
            let bundleIdentifier = extractBundleIdentifier(from: target)

            return TargetInfo(
                name: name,
                productType: productType,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    // MARK: - Private Target Helpers

    /// Extracts the PRODUCT_BUNDLE_IDENTIFIER from a target's build configuration list.
    /// Checks all build configurations and returns the first non-nil value found.
    private func extractBundleIdentifier(from target: PBXTarget) -> String? {
        guard let configList = target.buildConfigurationList else { return nil }
        for config in configList.buildConfigurations {
            if let bundleId = config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String,
               !bundleId.isEmpty {
                return bundleId
            }
        }
        return nil
    }

    // MARK: - List Frameworks

    /// Lists all frameworks and libraries linked to a specific target.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - targetName: The name of the target to inspect.
    /// - Returns: An array of `FrameworkInfo` representing each linked framework or library.
    /// - Throws: `ProjectManagerError` if the project cannot be parsed or the target is not found.
    func listFrameworks(projectPath: String, targetName: String) async throws -> [FrameworkInfo] {
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Find the target by name
        guard let target = rootObject.targets.first(where: { $0.name == targetName }) else {
            throw ProjectManagerError.targetNotFound(name: targetName)
        }

        // Find the PBXFrameworksBuildPhase in the target's build phases
        guard let frameworksPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) as? PBXFrameworksBuildPhase else {
            // No frameworks build phase means no linked frameworks
            return []
        }

        guard let files = frameworksPhase.files else {
            return []
        }

        var frameworks: [FrameworkInfo] = []

        for buildFile in files {
            let name: String
            let frameworkType: FrameworkType

            // Check if this is an SPM product dependency
            if let product = buildFile.product {
                name = product.productName
                frameworkType = .spmProduct
            } else if let fileRef = buildFile.file {
                // Determine name from the file reference
                name = fileRef.name ?? fileRef.path ?? "Unknown"

                // Determine type based on source tree and path
                if fileRef.sourceTree == .sdkRoot || fileRef.sourceTree == .developerDir ||
                   (fileRef.path?.contains("System/Library") ?? false) {
                    frameworkType = .system
                } else {
                    frameworkType = .projectRelative
                }
            } else {
                continue
            }

            // Determine required/optional status
            // A framework is optional (weak) if its build file settings contain "Weak" in ATTRIBUTES
            let isRequired: Bool
            if let settings = buildFile.settings,
               let attributes = settings["ATTRIBUTES"] as? [String],
               attributes.contains("Weak") {
                isRequired = false
            } else {
                isRequired = true
            }

            frameworks.append(FrameworkInfo(name: name, isRequired: isRequired, type: frameworkType))
        }

        return frameworks
    }

    // MARK: - Add Framework

    /// Adds a framework or library to a target's link build phase.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - targetName: The name of the target to add the framework to.
    ///   - frameworkName: The framework name (e.g., "UIKit.framework", "Alamofire", "MyLib.framework").
    /// - Throws: `ProjectManagerError` if the target is not found, the framework is already linked,
    ///   or the write fails.
    func addFramework(projectPath: String, targetName: String, frameworkName: String) async throws {
        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Find target by name
        guard let target = rootObject.targets.first(where: { $0.name == targetName }) as? PBXNativeTarget else {
            throw ProjectManagerError.targetNotFound(name: targetName)
        }

        // Find or create the frameworks build phase
        let frameworksPhase: PBXFrameworksBuildPhase
        if let existingPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) as? PBXFrameworksBuildPhase {
            frameworksPhase = existingPhase
        } else {
            let newPhase = PBXFrameworksBuildPhase()
            project.pbxproj.add(object: newPhase)
            target.buildPhases.append(newPhase)
            frameworksPhase = newPhase
        }

        // Check for duplicates in the frameworks build phase
        if let existingFiles = frameworksPhase.files {
            for buildFile in existingFiles {
                if let product = buildFile.product, product.productName == frameworkName {
                    throw ProjectManagerError.frameworkAlreadyLinked(framework: frameworkName, target: targetName)
                }
                if let fileRef = buildFile.file {
                    let existingName = fileRef.name ?? fileRef.path?.split(separator: "/").last.map(String.init) ?? ""
                    if existingName == frameworkName {
                        throw ProjectManagerError.frameworkAlreadyLinked(framework: frameworkName, target: targetName)
                    }
                }
            }
        }

        // Determine framework type from name
        if frameworkName.hasSuffix(".framework") {
            // Could be system framework or project-relative framework
            // Check if it's a known system framework (we treat .framework suffix as system by default)
            // For project-relative: verify the file exists relative to the project
            let projectDir = (projectPath as NSString).deletingLastPathComponent
            let relativeFrameworkPath = (projectDir as NSString).appendingPathComponent(frameworkName)

            if FileManager.default.fileExists(atPath: relativeFrameworkPath) {
                // Project-relative framework
                try addProjectRelativeFramework(
                    project: project,
                    rootObject: rootObject,
                    frameworksPhase: frameworksPhase,
                    frameworkName: frameworkName,
                    projectPath: projectPath
                )
            } else {
                // System framework
                try addSystemFramework(
                    project: project,
                    rootObject: rootObject,
                    frameworksPhase: frameworksPhase,
                    frameworkName: frameworkName
                )
            }
        } else {
            // SPM package product
            try addSPMProductFramework(
                project: project,
                rootObject: rootObject,
                target: target,
                frameworksPhase: frameworksPhase,
                productName: frameworkName
            )
        }

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Add Framework Helpers

    /// Adds a system framework to the link phase.
    private func addSystemFramework(
        project: XcodeProj,
        rootObject: PBXProject,
        frameworksPhase: PBXFrameworksBuildPhase,
        frameworkName: String
    ) throws {
        // Create PBXFileReference for the system framework
        let fileReference = PBXFileReference(
            sourceTree: .sdkRoot,
            name: frameworkName,
            lastKnownFileType: "wrapper.framework",
            path: "System/Library/Frameworks/\(frameworkName)"
        )
        project.pbxproj.add(object: fileReference)

        // Add to Frameworks group (find or create)
        let frameworksGroup = findOrCreateFrameworksGroup(project: project, rootObject: rootObject)
        frameworksGroup.children.append(fileReference)

        // Create build file and add to link phase
        let buildFile = PBXBuildFile(file: fileReference)
        project.pbxproj.add(object: buildFile)
        frameworksPhase.files?.append(buildFile)
    }

    /// Adds an SPM package product to the link phase.
    private func addSPMProductFramework(
        project: XcodeProj,
        rootObject: PBXProject,
        target: PBXNativeTarget,
        frameworksPhase: PBXFrameworksBuildPhase,
        productName: String
    ) throws {
        // Verify the package is already a dependency of the project
        let remotePackages = rootObject.remotePackages
        guard !remotePackages.isEmpty else {
            throw ProjectManagerError.packageDependencyRequired(product: productName)
        }

        // Find the package that provides this product
        // We check if any package could provide this product by looking at existing package product dependencies
        // or by matching the product name against package names
        var matchingPackage: XCRemoteSwiftPackageReference?
        for package in remotePackages {
            let packageName = package.name ?? package.repositoryURL?
                .split(separator: "/").last
                .map(String.init)?
                .replacingOccurrences(of: ".git", with: "") ?? ""
            if packageName.lowercased() == productName.lowercased() || packageName == productName {
                matchingPackage = package
                break
            }
        }

        // If no exact match, check if any package exists (the user is responsible for knowing which package provides the product)
        // Per requirement R9.3: just verify a package dependency exists
        if matchingPackage == nil {
            // Check if any package could potentially provide this product
            // We'll accept it if there are any remote packages at all, since the user knows what they're linking
            // Actually, per R9.4: "SHALL return an error indicating the package dependency must be added first"
            // We need to verify the package exists. Let's be more lenient and check all packages.
            let allPackageNames = remotePackages.compactMap { pkg -> String? in
                pkg.name ?? pkg.repositoryURL?
                    .split(separator: "/").last
                    .map(String.init)?
                    .replacingOccurrences(of: ".git", with: "")
            }

            // Check if the product name could be from any known package
            // Since SPM packages can expose multiple products with different names,
            // we'll trust the user if at least one package exists
            let found = allPackageNames.contains { name in
                name.lowercased() == productName.lowercased() ||
                productName.lowercased().contains(name.lowercased()) ||
                name.lowercased().contains(productName.lowercased())
            }

            if !found {
                throw ProjectManagerError.packageDependencyRequired(product: productName)
            }
        }

        // Create XCSwiftPackageProductDependency
        let productDependency = XCSwiftPackageProductDependency(
            productName: productName,
            package: matchingPackage
        )
        project.pbxproj.add(object: productDependency)

        // Add to target's package product dependencies
        if target.packageProductDependencies != nil {
            target.packageProductDependencies?.append(productDependency)
        } else {
            target.packageProductDependencies = [productDependency]
        }

        // Create build file with the product dependency and add to link phase
        let buildFile = PBXBuildFile(product: productDependency)
        project.pbxproj.add(object: buildFile)
        frameworksPhase.files?.append(buildFile)
    }

    /// Adds a project-relative framework to the link phase.
    private func addProjectRelativeFramework(
        project: XcodeProj,
        rootObject: PBXProject,
        frameworksPhase: PBXFrameworksBuildPhase,
        frameworkName: String,
        projectPath: String
    ) throws {
        // Verify the framework file exists relative to the project directory
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        let frameworkPath = (projectDir as NSString).appendingPathComponent(frameworkName)

        guard FileManager.default.fileExists(atPath: frameworkPath) else {
            throw ProjectManagerError.frameworkFileNotFound(path: frameworkPath)
        }

        // Create PBXFileReference for the project-relative framework
        let fileReference = PBXFileReference(
            sourceTree: .group,
            name: frameworkName,
            lastKnownFileType: "wrapper.framework",
            path: frameworkName
        )
        project.pbxproj.add(object: fileReference)

        // Add to Frameworks group
        let frameworksGroup = findOrCreateFrameworksGroup(project: project, rootObject: rootObject)
        frameworksGroup.children.append(fileReference)

        // Create build file and add to link phase
        let buildFile = PBXBuildFile(file: fileReference)
        project.pbxproj.add(object: buildFile)
        frameworksPhase.files?.append(buildFile)
    }

    /// Finds or creates the "Frameworks" group in the project.
    private func findOrCreateFrameworksGroup(project: XcodeProj, rootObject: PBXProject) -> PBXGroup {
        // Look for existing Frameworks group in the main group
        if let mainGroup = rootObject.mainGroup {
            if let frameworksGroup = mainGroup.children.compactMap({ $0 as? PBXGroup }).first(where: { $0.name == "Frameworks" || $0.path == "Frameworks" }) {
                return frameworksGroup
            }

            // Create a new Frameworks group
            let newGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
            project.pbxproj.add(object: newGroup)
            mainGroup.children.append(newGroup)
            return newGroup
        }

        // Fallback: create a standalone group (shouldn't happen in practice)
        let newGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
        project.pbxproj.add(object: newGroup)
        return newGroup
    }

    // MARK: - Remove Framework

    /// Removes a framework or library from a target's link build phase.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - targetName: The name of the target to remove the framework from.
    ///   - frameworkName: The framework name to match (case-sensitive exact match).
    /// - Throws: `ProjectManagerError` if the target is not found, the framework is not linked, or the write fails.
    func removeFramework(projectPath: String, targetName: String, frameworkName: String) async throws {
        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Find target by name (case-sensitive)
        guard let target = rootObject.targets.first(where: { $0.name == targetName }) else {
            throw ProjectManagerError.targetNotFound(name: targetName)
        }

        // Find the PBXFrameworksBuildPhase in the target's build phases
        guard let frameworksPhase = target.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase }) as? PBXFrameworksBuildPhase,
              let files = frameworksPhase.files else {
            throw ProjectManagerError.frameworkNotFound(framework: frameworkName, target: targetName)
        }

        // Find the matching build file by name (case-sensitive exact match)
        var matchingBuildFile: PBXBuildFile?
        for buildFile in files {
            // Check SPM product name
            if let product = buildFile.product, product.productName == frameworkName {
                matchingBuildFile = buildFile
                break
            }
            // Check file reference name or path
            if let fileRef = buildFile.file {
                let refName = fileRef.name ?? fileRef.path?.split(separator: "/").last.map(String.init) ?? ""
                if refName == frameworkName {
                    matchingBuildFile = buildFile
                    break
                }
            }
        }

        guard let buildFileToRemove = matchingBuildFile else {
            throw ProjectManagerError.frameworkNotFound(framework: frameworkName, target: targetName)
        }

        // Remove the build file from the phase
        frameworksPhase.files?.removeAll { $0 === buildFileToRemove }
        project.pbxproj.delete(object: buildFileToRemove)

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Add Target

    /// Supported product types for the add target operation.
    private static let supportedProductTypes: [String: PBXProductType] = [
        "application": .application,
        "framework": .framework,
        "staticLibrary": .staticLibrary,
        "dynamicLibrary": .dynamicLibrary,
        "unitTestBundle": .unitTestBundle,
        "uiTestBundle": .uiTestBundle,
    ]

    /// Adds a new target to the Xcode project.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - name: The name of the new target.
    ///   - productType: The product type string (e.g., "application", "framework").
    /// - Throws: `ProjectManagerError` if validation fails, the target name is taken, or the write fails.
    func addTarget(projectPath: String, name: String, productType: String) async throws {
        // Validate target name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectManagerError.invalidTargetName(name: name)
        }

        // Validate product type
        guard let pbxProductType = Self.supportedProductTypes[productType] else {
            throw ProjectManagerError.unsupportedProductType(
                productType: productType,
                supported: Array(Self.supportedProductTypes.keys).sorted()
            )
        }

        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Check for duplicate target name
        if rootObject.targets.contains(where: { $0.name == trimmedName }) {
            throw ProjectManagerError.duplicateTarget(name: trimmedName)
        }

        // Create build phases
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        let frameworksBuildPhase = PBXFrameworksBuildPhase()
        let resourcesBuildPhase = PBXResourcesBuildPhase()

        project.pbxproj.add(object: sourcesBuildPhase)
        project.pbxproj.add(object: frameworksBuildPhase)
        project.pbxproj.add(object: resourcesBuildPhase)

        // Create build configuration list matching project's configurations
        let projectConfigList = rootObject.buildConfigurationList
        let projectConfigs = projectConfigList?.buildConfigurations ?? []

        // Extract deployment target from project settings
        let deploymentTarget = extractDeploymentTarget(from: projectConfigs)

        var targetConfigs: [XCBuildConfiguration] = []
        for projectConfig in projectConfigs {
            let buildSettings: [String: Any] = buildDefaultSettings(
                targetName: trimmedName,
                productType: productType,
                deploymentTarget: deploymentTarget
            )
            let config = XCBuildConfiguration(
                name: projectConfig.name,
                buildSettings: buildSettings
            )
            project.pbxproj.add(object: config)
            targetConfigs.append(config)
        }

        // If no project configs exist, create default Debug and Release
        if targetConfigs.isEmpty {
            let debugConfig = XCBuildConfiguration(
                name: "Debug",
                buildSettings: buildDefaultSettings(
                    targetName: trimmedName,
                    productType: productType,
                    deploymentTarget: deploymentTarget
                )
            )
            let releaseConfig = XCBuildConfiguration(
                name: "Release",
                buildSettings: buildDefaultSettings(
                    targetName: trimmedName,
                    productType: productType,
                    deploymentTarget: deploymentTarget
                )
            )
            project.pbxproj.add(object: debugConfig)
            project.pbxproj.add(object: releaseConfig)
            targetConfigs = [debugConfig, releaseConfig]
        }

        let configList = XCConfigurationList(
            buildConfigurations: targetConfigs,
            defaultConfigurationName: "Release"
        )
        project.pbxproj.add(object: configList)

        // Create the native target
        let nativeTarget = PBXNativeTarget(
            name: trimmedName,
            buildConfigurationList: configList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productName: trimmedName,
            productType: pbxProductType
        )
        project.pbxproj.add(object: nativeTarget)

        // Add target to project
        var updatedTargets = rootObject.targets
        updatedTargets.append(nativeTarget)
        rootObject.targets = updatedTargets

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Add Target Helpers

    /// Extracts the deployment target from the project's build configurations.
    /// Checks for IPHONEOS_DEPLOYMENT_TARGET, MACOSX_DEPLOYMENT_TARGET, etc.
    private func extractDeploymentTarget(from configs: [XCBuildConfiguration]) -> [String: String] {
        var deploymentTargets: [String: String] = [:]
        let deploymentTargetKeys = [
            "IPHONEOS_DEPLOYMENT_TARGET",
            "MACOSX_DEPLOYMENT_TARGET",
            "TVOS_DEPLOYMENT_TARGET",
            "WATCHOS_DEPLOYMENT_TARGET",
        ]

        for config in configs {
            for key in deploymentTargetKeys {
                if let value = config.buildSettings[key] as? String, !value.isEmpty {
                    deploymentTargets[key] = value
                }
            }
            // Once we find deployment targets, stop looking
            if !deploymentTargets.isEmpty {
                break
            }
        }

        return deploymentTargets
    }

    /// Builds the default build settings for a new target.
    private func buildDefaultSettings(
        targetName: String,
        productType: String,
        deploymentTarget: [String: String]
    ) -> [String: Any] {
        var settings: [String: Any] = [
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.example.\(targetName)",
        ]

        // Add deployment targets from project
        for (key, value) in deploymentTarget {
            settings[key] = value
        }

        // Add product-type-specific settings
        switch productType {
        case "application":
            settings["INFOPLIST_FILE"] = "\(targetName)/Info.plist"
            settings["CODE_SIGN_STYLE"] = "Automatic"
        case "framework":
            settings["DEFINES_MODULE"] = "YES"
            settings["DYLIB_COMPATIBILITY_VERSION"] = "1"
            settings["DYLIB_CURRENT_VERSION"] = "1"
            settings["DYLIB_INSTALL_NAME_BASE"] = "@rpath"
            settings["INSTALL_PATH"] = "$(LOCAL_LIBRARY_DIR)/Frameworks"
            settings["SKIP_INSTALL"] = "YES"
        case "staticLibrary":
            settings["SKIP_INSTALL"] = "YES"
        case "dynamicLibrary":
            settings["DYLIB_COMPATIBILITY_VERSION"] = "1"
            settings["DYLIB_CURRENT_VERSION"] = "1"
            settings["DYLIB_INSTALL_NAME_BASE"] = "@rpath"
        case "unitTestBundle", "uiTestBundle":
            settings["CODE_SIGN_STYLE"] = "Automatic"
            settings["INFOPLIST_FILE"] = "\(targetName)/Info.plist"
        default:
            break
        }

        return settings
    }

    // MARK: - Remove Target

    /// Removes a target from the project, including its build configuration list, build phases,
    /// target dependency entries from other targets, and references from shared schemes.
    ///
    /// - Parameters:
    ///   - projectPath: The validated absolute path to the `.xcodeproj` bundle.
    ///   - name: The exact name of the target to remove (case-sensitive).
    /// - Throws: `ProjectManagerError` if the target is not found, or the write fails.
    func removeTarget(projectPath: String, name: String) async throws {
        // Acquire write lock
        try await acquireWriteLock()
        defer { Task { await releaseWriteLock() } }

        // Read project from disk (fresh read per R13 requirement)
        let project: XcodeProj
        do {
            project = try XcodeProj(pathString: projectPath)
        } catch {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: error.localizedDescription
            )
        }

        guard let rootObject = project.pbxproj.rootObject else {
            throw ProjectManagerError.projectParseError(
                path: projectPath,
                reason: "Project file has no root object"
            )
        }

        // Find target by exact name match (case-sensitive)
        guard let target = rootObject.targets.first(where: { $0.name == name }) else {
            throw ProjectManagerError.targetNotFound(name: name)
        }

        // Remove target's build configuration list and its configurations
        if let configList = target.buildConfigurationList {
            for config in configList.buildConfigurations {
                project.pbxproj.delete(object: config)
            }
            project.pbxproj.delete(object: configList)
        }

        // Remove all build phases and their build files
        for buildPhase in target.buildPhases {
            if let files = buildPhase.files {
                for buildFile in files {
                    project.pbxproj.delete(object: buildFile)
                }
            }
            project.pbxproj.delete(object: buildPhase)
        }

        // Remove target dependency entries from other targets that reference this target
        for otherTarget in rootObject.targets where otherTarget !== target {
            let depsToRemove = otherTarget.dependencies.filter { dep in
                dep.target === target || dep.name == name
            }
            for dep in depsToRemove {
                // Remove the proxy if it exists
                if let proxy = dep.targetProxy {
                    project.pbxproj.delete(object: proxy)
                }
                project.pbxproj.delete(object: dep)
            }
            // Update the target's dependencies list
            otherTarget.dependencies = otherTarget.dependencies.filter { dep in
                dep.target !== target && dep.name != name
            }
        }

        // Remove target references from shared schemes
        if let sharedData = project.sharedData {
            for scheme in sharedData.schemes {
                // Remove from build action entries
                if let buildAction = scheme.buildAction {
                    buildAction.buildActionEntries.removeAll { entry in
                        entry.buildableReference.blueprintName == name
                    }
                }

                // Remove from test action testables
                if let testAction = scheme.testAction {
                    testAction.testables.removeAll { testable in
                        testable.buildableReference.blueprintName == name
                    }
                }
            }
        }

        // Remove the target's product reference if it exists
        if let product = target.product {
            project.pbxproj.delete(object: product)
        }

        // Remove target from project
        rootObject.targets = rootObject.targets.filter { $0 !== target }
        project.pbxproj.delete(object: target)

        // Write project to disk
        do {
            try project.write(path: Path(projectPath), override: true)
        } catch {
            throw ProjectManagerError.writeFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Private Version Helpers

    /// Extracts the version type and value from an XCRemoteSwiftPackageReference.VersionRequirement.
    private func extractVersionInfo(
        from requirement: XCRemoteSwiftPackageReference.VersionRequirement?
    ) -> (type: String, value: String) {
        guard let requirement = requirement else {
            return ("unknown", "")
        }
        switch requirement {
        case .upToNextMajorVersion(let version):
            return ("from", version)
        case .upToNextMinorVersion(let version):
            return ("upToNextMinor", version)
        case .range(let from, let to):
            return ("range", "\(from)..<\(to)")
        case .exact(let version):
            return ("exact", version)
        case .branch(let branch):
            return ("branch", branch)
        case .revision(let revision):
            return ("revision", revision)
        }
    }

    // MARK: - Write Serialization

    /// Acquires the write lock with a 30-second timeout.
    /// Call `releaseWriteLock()` when the write operation completes.
    /// - Throws: `ProjectManagerError.writeTimeout` if the lock cannot be acquired within 30 seconds.
    func acquireWriteLock() async throws {
        let acquired = await writeSemaphore.acquire(timeout: .seconds(30))
        guard acquired else {
            throw ProjectManagerError.writeTimeout
        }
    }

    /// Releases the write lock, allowing the next queued write operation to proceed.
    func releaseWriteLock() async {
        await writeSemaphore.release()
    }

    // MARK: - Private Helpers

    /// Resolves the project path by querying Xcode's frontmost workspace document via JXA.
    /// - Returns: The file path of the frontmost workspace document.
    /// - Throws: `ProjectManagerError.cannotResolveProjectPath` if Xcode is not running or has no open workspace.
    private func resolveFromXcode() async throws -> String {
        // Check if Xcode is running
        let isRunning: Bool
        do {
            isRunning = try await controller.isXcodeRunning()
        } catch {
            throw ProjectManagerError.cannotResolveProjectPath(
                reason: "Failed to check if Xcode is running: \(error.localizedDescription). Please provide an explicit projectPath parameter."
            )
        }

        guard isRunning else {
            throw ProjectManagerError.cannotResolveProjectPath(
                reason: "Xcode is not running. Please open Xcode with a project or provide an explicit projectPath parameter."
            )
        }

        // Query the frontmost workspace document path
        let script = XcodeController.jxaGetProjectPath()
        let output: String
        do {
            output = try await controller.executeJXA(script, timeout: XcodeController.defaultTimeout)
        } catch {
            throw ProjectManagerError.cannotResolveProjectPath(
                reason: "Failed to query Xcode for the active project path: \(error.localizedDescription). Please provide an explicit projectPath parameter."
            )
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed != "null", trimmed != "undefined" else {
            throw ProjectManagerError.cannotResolveProjectPath(
                reason: "No active Xcode project could be found. Xcode may have no open workspace documents. Please provide an explicit projectPath parameter."
            )
        }

        return trimmed
    }

    /// Validates that the given path exists, has a `.xcodeproj` extension, and contains `project.pbxproj`.
    /// - Parameter path: The path to validate.
    /// - Throws: `ProjectManagerError.pathNotFound` or `ProjectManagerError.invalidProjectBundle`.
    private func validateProjectPath(_ path: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check existence
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ProjectManagerError.pathNotFound(path: path)
        }

        // Check .xcodeproj extension
        guard path.hasSuffix(".xcodeproj") else {
            throw ProjectManagerError.invalidProjectBundle(
                path: path
            )
        }

        // Check it's a directory (bundle)
        guard isDirectory.boolValue else {
            throw ProjectManagerError.invalidProjectBundle(
                path: path
            )
        }

        // Check project.pbxproj exists inside
        let pbxprojPath = (path as NSString).appendingPathComponent("project.pbxproj")
        guard fileManager.fileExists(atPath: pbxprojPath) else {
            throw ProjectManagerError.invalidProjectBundle(
                path: path
            )
        }
    }
}

// MARK: - WriteSemaphore

/// An actor-based semaphore that serializes write operations with timeout support.
/// Only one write operation can proceed at a time; others queue in FIFO order.
actor WriteSemaphore {

    /// A waiter entry that pairs an ID with a continuation for identification.
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// Whether the semaphore is currently held by a write operation.
    private var isLocked = false

    /// Queue of continuations waiting to acquire the lock.
    private var waiters: [Waiter] = []

    /// Attempts to acquire the write lock within the given timeout.
    /// - Parameter timeout: The maximum duration to wait.
    /// - Returns: `true` if the lock was acquired, `false` if the timeout expired.
    func acquire(timeout: Duration) async -> Bool {
        if !isLocked {
            isLocked = true
            return true
        }

        // Need to wait — use a continuation with timeout
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            let waiter = Waiter(id: waiterID, continuation: continuation)
            waiters.append(waiter)

            // Schedule timeout
            Task { [waiterID] in
                try? await Task.sleep(for: timeout)
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    /// Releases the write lock and resumes the next waiting operation if any.
    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            // Lock stays held, transfer to next waiter
            next.continuation.resume(returning: true)
        } else {
            isLocked = false
        }
    }

    /// Cancels a waiting continuation if it's still in the queue (timeout expired).
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
        // If not found, it was already resumed by release() — do nothing
    }
}
