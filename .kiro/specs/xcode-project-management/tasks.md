# Tasks

## Task 1: Add XcodeProj dependency to Package.swift
- [x] Add `.package(url: "https://github.com/tuist/XcodeProj.git", from: "8.0.0")` to the dependencies array in Package.swift
- [x] Add `"XcodeProj"` to the `XcodePower` executable target's dependencies
- [x] Run `swift package resolve` to verify the dependency resolves correctly
- [x] Run `swift build` to confirm the project compiles with the new dependency

**Requirements:** R11

---

## Task 2: Create ProjectManager actor with project path resolution
- [x] Create `Sources/XcodePower/ProjectManager/ProjectManager.swift` with an actor that imports XcodeProj
- [x] Implement `resolveProjectPath(explicit: String?) async throws -> String` that either uses the explicit path or queries Xcode via JXA for the frontmost workspace document's file path
- [x] Add JXA script `jxaGetProjectPath()` to XcodeController that returns the project file path from the active workspace
- [x] Validate the resolved path exists, has `.xcodeproj` extension, and contains `project.pbxproj`
- [x] Return descriptive errors for: path not found, not a valid bundle, Xcode not running
- [x] Add a write serialization mechanism using an `AsyncSemaphore` or actor isolation to prevent concurrent writes with a 30-second timeout

**Requirements:** R1, R13

---

## Task 3: Create project management models
- [x] Create `Sources/XcodePower/Models/ProjectModels.swift`
- [x] Define `PackageInfo: Codable, Sendable` with fields: name (String), repositoryURL (String), versionType (String), versionValue (String)
- [x] Define `TargetInfo: Codable, Sendable` with fields: name (String), productType (String), bundleIdentifier (String?)
- [x] Define `FrameworkInfo: Codable, Sendable` with fields: name (String), isRequired (Bool), type (String: "system", "spmProduct", "projectRelative")
- [x] Run `swift build` to verify models compile

**Requirements:** R2, R5, R8, R12

---

## Task 4: Implement list packages functionality
- [x] Add `listPackages(projectPath: String) async throws -> [PackageInfo]` to ProjectManager
- [x] Use XcodeProj to open the project, iterate `pbxproj.rootObject.packages` (XCRemoteSwiftPackageReference objects)
- [x] Extract name (from URL last path component minus .git), repositoryURL, and version requirement (kind + value)
- [x] Create `Sources/XcodePower/Handlers/ListPackagesHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_list_packages` with optional `projectPath` parameter
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R2, R12

---

## Task 5: Implement add package functionality
- [x] Add `addPackage(projectPath: String, url: String, versionType: String, versionValue: String) async throws` to ProjectManager
- [x] Validate URL format (must have scheme and host)
- [x] Validate version: "from"/"exact" require valid semver, "branch" requires non-empty, "revision" requires 40-char hex
- [x] Check for duplicate by repository URL
- [x] Create XCRemoteSwiftPackageReference with appropriate version requirement and add to project
- [x] Write project to disk
- [x] Create `Sources/XcodePower/Handlers/AddPackageHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_add_package` with required `url`, `versionType`, `versionValue` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R3, R12

---

## Task 6: Implement remove package functionality
- [x] Add `removePackage(projectPath: String, identifier: String) async throws` to ProjectManager
- [x] Match identifier against repository URL (exact) and package name (case-insensitive)
- [x] Handle ambiguous matches (error with list)
- [x] Remove the XCRemoteSwiftPackageReference from the project
- [x] Remove all XCSwiftPackageProductDependency references from all targets that linked products of that package
- [x] Write project to disk
- [x] Create `Sources/XcodePower/Handlers/RemovePackageHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_remove_package` with required `identifier` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R4, R12

---

## Task 7: Implement list targets functionality
- [x] Add `listTargets(projectPath: String) async throws -> [TargetInfo]` to ProjectManager
- [x] Use XcodeProj to open the project, iterate all native targets and aggregate targets
- [x] Extract name, product type string, and bundle identifier from build settings (PRODUCT_BUNDLE_IDENTIFIER)
- [x] Create `Sources/XcodePower/Handlers/ListTargetsHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_list_targets` with optional `projectPath` parameter
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R5, R12

---

## Task 8: Implement add target functionality
- [x] Add `addTarget(projectPath: String, name: String, productType: String) async throws` to ProjectManager
- [x] Validate product type against supported set: application, framework, staticLibrary, dynamicLibrary, unitTestBundle, uiTestBundle
- [x] Check for duplicate target name
- [x] Create PBXNativeTarget with Sources, Frameworks, and Resources build phases
- [x] Create build configuration list matching project's configurations (Debug, Release, etc.)
- [x] Set default build settings: PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER, deployment target
- [x] Add target to project and write to disk
- [x] Create `Sources/XcodePower/Handlers/AddTargetHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_add_target` with required `name`, `productType` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R6, R12

---

## Task 9: Implement remove target functionality
- [x] Add `removeTarget(projectPath: String, name: String) async throws` to ProjectManager
- [x] Find target by exact name match (case-sensitive)
- [x] Remove target's build configuration list and all build phases
- [x] Remove target dependency entries from other targets that reference it
- [x] Remove target references from shared schemes (build action entries, test action entries)
- [x] Remove target from project and write to disk
- [x] Create `Sources/XcodePower/Handlers/RemoveTargetHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_remove_target` with required `name` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R7, R12

---

## Task 10: Implement list frameworks functionality
- [x] Add `listFrameworks(projectPath: String, targetName: String) async throws -> [FrameworkInfo]` to ProjectManager
- [x] Find target by name, return error if not found
- [x] Find the PBXFrameworksBuildPhase in the target's build phases
- [x] For each file in the phase, determine type (system framework, SPM product, project-relative) and required/optional status
- [x] Create `Sources/XcodePower/Handlers/ListFrameworksHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_list_frameworks` with required `target` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R8, R12

---

## Task 11: Implement add framework functionality
- [x] Add `addFramework(projectPath: String, targetName: String, frameworkName: String) async throws` to ProjectManager
- [x] Find target by name, return error if not found
- [x] Determine framework type from name: `.framework` suffix → system or project-relative; otherwise → SPM product
- [x] For system frameworks: create PBXFileReference in Frameworks group, add to link phase
- [x] For SPM products: verify package exists as dependency, create XCSwiftPackageProductDependency, add to link phase
- [x] For project-relative: verify file exists, create PBXFileReference, add to link phase
- [x] Check for duplicates before adding
- [x] Write project to disk
- [x] Create `Sources/XcodePower/Handlers/AddFrameworkHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_add_framework` with required `target`, `framework` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R9, R12

---

## Task 12: Implement remove framework functionality
- [x] Add `removeFramework(projectPath: String, targetName: String, frameworkName: String) async throws` to ProjectManager
- [x] Find target by name, return error if not found
- [x] Find the framework in the target's PBXFrameworksBuildPhase by name (case-sensitive exact match)
- [x] Remove the build file from the phase
- [x] Write project to disk
- [x] Create `Sources/XcodePower/Handlers/RemoveFrameworkHandler.swift` implementing ToolHandler
- [x] Define tool as `xcode_remove_framework` with required `target`, `framework` and optional `projectPath`
- [x] Register handler in `main.swift`
- [x] Run `swift build` to verify

**Requirements:** R10, R12

---

## Task 13: Update mcp.json and POWER.md documentation
- [x] Add all 9 new tools to the `autoApprove` array in `mcp.json`
- [x] Add documentation for each new tool in `POWER.md` with parameter tables and example usage
- [x] Add a "Project Management" workflow section to POWER.md describing typical usage patterns
- [x] Run `swift build -c release` to produce the final binary

**Requirements:** R12


---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2", "3"] },
    { "id": 2, "tasks": ["4", "7", "10"] },
    { "id": 3, "tasks": ["5", "8", "11"] },
    { "id": 4, "tasks": ["6", "9", "12"] },
    { "id": 5, "tasks": ["13"] }
  ]
}
```

### Explanation

- **Wave 0**: Task 1 (add XcodeProj dependency) — no dependencies, everything else needs this
- **Wave 1**: Tasks 2 & 3 (ProjectManager actor + models) — both depend only on Task 1, can run in parallel
- **Wave 2**: Tasks 4, 7, 10 (list packages, list targets, list frameworks) — read-only operations, depend on Tasks 2 & 3, can run in parallel
- **Wave 3**: Tasks 5, 8, 11 (add package, add target, add framework) — write operations, depend on their respective list tasks for shared code patterns, can run in parallel
- **Wave 4**: Tasks 6, 9, 12 (remove package, remove target, remove framework) — removal operations depend on their respective add tasks (shared lookup logic), can run in parallel
- **Wave 5**: Task 13 (documentation & release build) — depends on all implementation tasks being complete
