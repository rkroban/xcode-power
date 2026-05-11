# Requirements Document

## Introduction

This feature adds project management capabilities to the Xcode Power MCP server. Since Xcode's JXA scripting dictionary does not expose APIs for managing packages, targets, or framework linkage, this feature uses the Tuist XcodeProj Swift library to programmatically read and write the `.pbxproj` file. The new tools enable listing, adding, and removing Swift Package Manager dependencies, build targets, and framework/library references in a target's link build phase.

## Glossary

- **Project_Manager**: The component responsible for reading and writing Xcode project files (`.pbxproj`) using the XcodeProj library
- **MCP_Server**: The Xcode Power MCP server that receives JSON-RPC tool call requests over stdio
- **Package_Dependency**: A Swift Package Manager remote package dependency defined by a repository URL and version requirement
- **Target**: A build target within an Xcode project (e.g., application, framework, unit test bundle)
- **Framework_Reference**: A framework or library linked in a target's "Link Binary With Libraries" build phase
- **Project_Path**: The absolute file system path to a `.xcodeproj` bundle
- **Version_Requirement**: A semantic versioning constraint for a package dependency (e.g., "from: 1.0.0", "exact: 2.3.1", "branch: main")
- **Link_Phase**: The "Frameworks and Libraries" build phase of a target that specifies which frameworks and libraries are linked

## Requirements

### Requirement 1: Discover Project Path

**User Story:** As a developer, I want the server to locate the active Xcode project file, so that project management tools can operate on the correct `.xcodeproj` bundle.

#### Acceptance Criteria

1. WHEN a project management tool is invoked without an explicit project path, THE Project_Manager SHALL resolve the project path by querying the file path of the frontmost Xcode workspace document via JXA
2. WHEN a project management tool is invoked with an explicit project path parameter, THE Project_Manager SHALL use the provided path without querying Xcode
3. IF the resolved or provided path does not exist on disk, THEN THE Project_Manager SHALL return an error message indicating the path does not exist, including the attempted path
4. IF the resolved or provided path exists but does not have a `.xcodeproj` extension or does not contain a `project.pbxproj` file, THEN THE Project_Manager SHALL return an error message indicating the path is not a valid Xcode project bundle
5. IF Xcode is not running or has no open workspace document when auto-resolving the project path, THEN THE Project_Manager SHALL return an error message indicating that no active Xcode project could be found and suggest providing an explicit path parameter
6. IF multiple workspace documents are open in Xcode during auto-resolution, THE Project_Manager SHALL use the frontmost workspace document

### Requirement 2: List Package Dependencies

**User Story:** As a developer, I want to list all SPM package dependencies in my Xcode project, so that I can see what packages are currently configured.

#### Acceptance Criteria

1. WHEN the list packages tool is invoked, THE Project_Manager SHALL return all remote Swift Package Manager dependencies defined in the project
2. THE Project_Manager SHALL include for each package: the package name, repository URL, version requirement type (from, exact, branch, or revision), and the corresponding version value
3. IF the project contains no package dependencies, THEN THE Project_Manager SHALL return an empty list
4. IF the project file cannot be parsed, THEN THE Project_Manager SHALL return an error message indicating the project file is invalid or corrupted

### Requirement 3: Add Package Dependency

**User Story:** As a developer, I want to add a new SPM package dependency to my Xcode project, so that I can incorporate third-party libraries without manually editing project settings.

#### Acceptance Criteria

1. WHEN the add package tool is invoked with a repository URL and version requirement, THE Project_Manager SHALL add the package dependency to the project file as an XCRemoteSwiftPackageReference entry
2. THE Project_Manager SHALL support version requirements of type: "from" (minimum version, valid semantic version string), "exact" (exact version, valid semantic version string), "branch" (branch name, non-empty string), and "revision" (commit hash, 40-character hexadecimal string)
3. IF a package with the same repository URL already exists in the project, THEN THE Project_Manager SHALL return an error indicating the package is already added
4. IF the repository URL is empty or does not conform to a valid URL format containing a scheme and host component, THEN THE Project_Manager SHALL return a validation error indicating the URL is invalid
5. WHEN the package is successfully added, THE Project_Manager SHALL persist the change to the `.pbxproj` file
6. IF the version requirement type is "from" or "exact" and the provided version string is not a valid semantic version, THEN THE Project_Manager SHALL return a validation error indicating the version format is invalid
7. WHEN the add package tool is invoked, THE Project_Manager SHALL derive the package name from the last path component of the repository URL with the `.git` suffix removed if present

### Requirement 4: Remove Package Dependency

**User Story:** As a developer, I want to remove an SPM package dependency from my Xcode project, so that I can clean up unused dependencies.

#### Acceptance Criteria

1. WHEN the remove package tool is invoked with a package identifier, THE Project_Manager SHALL match the identifier against both the repository URL (exact match) and the package name (case-insensitive match) of all project package dependencies, and remove the first matching package dependency from the project file
2. WHEN a package is removed, THE Project_Manager SHALL also remove all product references from every target that linked products of that package
3. IF no package matching the provided identifier exists, THEN THE Project_Manager SHALL return an error indicating the package was not found
4. IF the provided identifier is empty or contains only whitespace, THEN THE Project_Manager SHALL return a validation error indicating the identifier is required
5. IF the provided identifier matches more than one package dependency, THEN THE Project_Manager SHALL return an error listing the ambiguous matches and requesting a more specific identifier
6. WHEN the package is successfully removed, THE Project_Manager SHALL persist the change to the `.pbxproj` file

### Requirement 5: List Targets

**User Story:** As a developer, I want to list all targets in my Xcode project, so that I can see what build targets are available.

#### Acceptance Criteria

1. WHEN the list targets tool is invoked, THE Project_Manager SHALL return all native targets and aggregate targets defined in the project
2. THE Project_Manager SHALL include for each target: the target name, product type (e.g., application, framework, unitTestBundle), and bundle identifier; IF a target does not have a bundle identifier configured, THEN THE Project_Manager SHALL omit the bundle identifier field from that target's entry
3. IF the project contains no targets, THEN THE Project_Manager SHALL return an empty list
4. IF the project file cannot be parsed, THEN THE Project_Manager SHALL return an error message indicating the project file is malformed or unreadable

### Requirement 6: Add Target

**User Story:** As a developer, I want to add a new target to my Xcode project, so that I can create new build products without manually configuring project settings.

#### Acceptance Criteria

1. WHEN the add target tool is invoked with a name and product type, THE Project_Manager SHALL create a new target in the project file with a Sources build phase, a Frameworks build phase, and a Resources build phase
2. THE Project_Manager SHALL support product types: application, framework, staticLibrary, dynamicLibrary, unitTestBundle, and uiTestBundle
3. THE Project_Manager SHALL configure the new target with Xcode's default build settings for the specified product type, including the product name set to the target name, the bundle identifier derived from the organization identifier and target name, and the deployment target matching the project's existing deployment target
4. IF a target with the same name already exists in the project, THEN THE Project_Manager SHALL return an error indicating the name is taken
5. IF the provided product type is not supported, THEN THE Project_Manager SHALL return a validation error listing supported types
6. IF the provided target name is empty or contains only whitespace, THEN THE Project_Manager SHALL return a validation error indicating the target name is invalid
7. WHEN the target is successfully added, THE Project_Manager SHALL persist the change to the `.pbxproj` file
8. WHEN the target is created, THE Project_Manager SHALL add a build configuration list to the target containing one entry for each build configuration defined in the project (e.g., Debug and Release)

### Requirement 7: Remove Target

**User Story:** As a developer, I want to remove a target from my Xcode project, so that I can clean up targets that are no longer needed.

#### Acceptance Criteria

1. WHEN the remove target tool is invoked with a target name, THE Project_Manager SHALL perform a case-sensitive exact match against all target names in the project and remove the matching target, its associated build configurations, and its build phases from the project file
2. WHEN a target is removed, THE Project_Manager SHALL remove all references to that target from scheme build action entries and test action entries in every shared scheme within the project
3. WHEN a target is removed, THE Project_Manager SHALL remove any target dependency entries in other targets that reference the removed target
4. IF no target with a name exactly matching the provided name exists, THEN THE Project_Manager SHALL return an error indicating the target was not found
5. IF the provided target name is empty or contains only whitespace, THEN THE Project_Manager SHALL return a validation error indicating the target name is required
6. WHEN the target is successfully removed, THE Project_Manager SHALL persist the change to the `.pbxproj` file

### Requirement 8: List Frameworks and Libraries

**User Story:** As a developer, I want to list all frameworks and libraries linked to a specific target, so that I can see what dependencies a target has.

#### Acceptance Criteria

1. WHEN the list frameworks tool is invoked with a target name, THE Project_Manager SHALL return all frameworks and libraries in that target's Link_Phase
2. THE Project_Manager SHALL include for each entry: the framework name, whether it is required or optional, and the entry type classified as one of: system framework, SPM package product, or project-relative framework path
3. IF the specified target does not exist, THEN THE Project_Manager SHALL return an error indicating the target was not found
4. IF the target has no linked frameworks or has no Link_Phase build phase, THEN THE Project_Manager SHALL return an empty list

### Requirement 9: Add Framework or Library to Target

**User Story:** As a developer, I want to add a framework or library to a target's link phase, so that I can configure linking without manually editing build phases.

#### Acceptance Criteria

1. WHEN the add framework tool is invoked with a target name and framework name, THE Project_Manager SHALL add the framework to the target's Link_Phase with a default linking status of "required"
2. THE Project_Manager SHALL support adding: system frameworks (e.g., "UIKit.framework"), SPM package product references, and project-relative framework paths
3. WHEN adding an SPM package product, THE Project_Manager SHALL verify the package is already a dependency of the project
4. IF the add framework tool is invoked for an SPM package product whose package is not a dependency of the project, THEN THE Project_Manager SHALL return an error indicating the package dependency must be added first
5. IF the framework is already linked to the target, THEN THE Project_Manager SHALL return an error indicating it is already linked
6. IF the specified target does not exist, THEN THE Project_Manager SHALL return an error indicating the target was not found
7. IF a project-relative framework path is specified and no file exists at that path, THEN THE Project_Manager SHALL return an error indicating the framework file was not found
8. WHEN the framework is successfully added, THE Project_Manager SHALL persist the change to the `.pbxproj` file

### Requirement 10: Remove Framework or Library from Target

**User Story:** As a developer, I want to remove a framework or library from a target's link phase, so that I can clean up unnecessary linkage.

#### Acceptance Criteria

1. WHEN the remove framework tool is invoked with a target name and framework name, THE Project_Manager SHALL remove the entry whose name matches the provided framework name (case-sensitive, exact match) from the target's Link_Phase
2. THE Project_Manager SHALL support removing system frameworks, SPM package product references, and project-relative framework paths from the Link_Phase
3. IF the specified target does not exist, THEN THE Project_Manager SHALL return an error indicating the target was not found
4. IF the specified framework is not linked to the target, THEN THE Project_Manager SHALL return an error indicating the framework was not found in the link phase
5. WHEN the framework is successfully removed, THE Project_Manager SHALL persist the change to the `.pbxproj` file

### Requirement 11: XcodeProj Library Integration

**User Story:** As a developer of the MCP server, I want the project to depend on the Tuist XcodeProj library, so that the project management tools can read and write `.pbxproj` files reliably.

#### Acceptance Criteria

1. THE MCP_Server SHALL declare a dependency on the XcodeProj Swift package (from version 8.0.0 or later) in its Package.swift manifest and link it to the target containing the Project_Manager
2. THE Project_Manager SHALL use XcodeProj APIs to parse, modify, and serialize `.pbxproj` files
3. WHEN writing changes to the `.pbxproj` file, THE Project_Manager SHALL preserve all existing objects and settings not affected by the current operation such that only the intended additions or removals appear in a file diff
4. IF the Project_Manager fails to parse a `.pbxproj` file due to malformed content or an unsupported format, THEN THE Project_Manager SHALL return a descriptive error message indicating the parse failure without modifying the file

### Requirement 12: Tool Registration and MCP Integration

**User Story:** As a developer, I want the project management tools to be accessible as MCP tool calls, so that they integrate seamlessly with the existing server architecture.

#### Acceptance Criteria

1. THE MCP_Server SHALL register each project management tool (list packages, add package, remove package, list targets, add target, remove target, list frameworks, add framework, remove framework) as a ToolHandler in the ToolRegistry, each providing a ToolDefinition with a tool name, description, and inputSchema that declares all accepted parameters and which are required
2. WHEN a project management tool call is received, THE MCP_Server SHALL validate that all required input parameters are present and non-empty before invoking the Project_Manager
3. IF a required parameter is missing or empty in a project management tool call, THEN THE MCP_Server SHALL return a ToolResult with isError set to true and a text content entry indicating which parameter failed validation
4. THE MCP_Server SHALL return successful tool results as a ToolResult containing a single ToolContent entry of type "text" with a JSON-encoded payload, and isError set to nil for success or true for operation failures

### Requirement 13: Concurrent Access Safety

**User Story:** As a developer, I want project file modifications to be safe from concurrent access, so that simultaneous tool calls do not corrupt the project file.

#### Acceptance Criteria

1. WHILE a write operation is in progress on a project file, THE Project_Manager SHALL serialize the entire read-modify-write cycle of subsequent write operations to prevent concurrent modification, queuing them in the order received
2. THE Project_Manager SHALL read the project file from disk immediately before each write operation to incorporate any external changes made since the last read
3. IF a queued write operation has waited more than 30 seconds to acquire write access, THEN THE Project_Manager SHALL abandon the operation and return an error indicating a timeout due to concurrent access contention
4. IF a write operation fails after acquiring write access, THEN THE Project_Manager SHALL release the write lock and return an error indicating the write failure without leaving the project file in a partially written state
