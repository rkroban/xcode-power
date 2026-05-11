# Xcode Power

Control Xcode.app directly from Kiro using fast, incremental builds that leverage Xcode's warm build cache. Instead of cold-starting `xcodebuild` from the command line, this power drives the running Xcode instance via JXA (JavaScript for Automation), giving you near-instant feedback on builds, tests, and diagnostics.

## Prerequisites

- **macOS** (any version supporting Xcode 15+)
- **Xcode.app** installed and running with a project or workspace open
- **Swift 5.9+** toolchain (for building the server binary)

## Setup

1. Build the server binary:

   ```bash
   cd xcode-power
   swift build -c release
   ```

2. The compiled binary is located at `.build/release/XcodePower`.

3. Add the power to your Kiro configuration (see `mcp.json` in this directory for the ready-to-use config).

## Tools

### xcode_build

Triggers a build in Xcode using the warm build cache. Returns build status, duration, and any errors.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scheme` | string | No | The scheme to build. If omitted, builds the active scheme. |
| `destination` | string | No | The run destination to build for (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination. |

**Example usage:**

```json
{
  "name": "xcode_build",
  "arguments": {
    "scheme": "MyApp"
  }
}
```

**Success response:**
```json
{
  "status": "succeeded",
  "duration": 4.2
}
```

**Failure response:**
```json
{
  "status": "failed",
  "duration": 2.1,
  "errors": [
    {
      "severity": "error",
      "message": "Use of undeclared type 'Foo'",
      "filePath": "/path/to/File.swift",
      "lineNumber": 42
    }
  ]
}
```

---

### xcode_test

Runs tests in Xcode for the specified scheme and optional test identifier. Returns test counts and failure details.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scheme` | string | No | The scheme to test. If omitted, tests the active scheme. |
| `testIdentifier` | string | No | A specific test to run (e.g., `MyTestClass` or `MyTestClass/testMethod`). If omitted, runs all tests. |
| `destination` | string | No | The run destination to test on (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination. |

**Example usage:**

```json
{
  "name": "xcode_test",
  "arguments": {
    "scheme": "MyAppTests",
    "testIdentifier": "LoginTests/testValidCredentials"
  }
}
```

**Response:**
```json
{
  "totalCount": 1,
  "passedCount": 1,
  "failedCount": 0,
  "failures": []
}
```

---

### xcode_run

Runs the application in Xcode for the specified scheme. Returns launch status or build errors if the build fails.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scheme` | string | No | The scheme to run. If omitted, runs the active scheme. |
| `destination` | string | No | The run destination to run on (e.g., 'iPhone 16 Pro', 'My Mac'). If omitted, uses the active destination. |

**Example usage:**

```json
{
  "name": "xcode_run",
  "arguments": {
    "scheme": "MyApp"
  }
}
```

**Response:**
```json
{
  "status": "launched"
}
```

---

### xcode_list_schemes

Lists all available schemes in the active Xcode workspace or project.

*No parameters.*

**Example usage:**

```json
{
  "name": "xcode_list_schemes",
  "arguments": {}
}
```

**Response:**
```json
[
  { "name": "MyApp" },
  { "name": "MyAppTests" },
  { "name": "MyFramework" }
]
```

---

### xcode_list_destinations

Lists all available run destinations (simulators, devices, My Mac) in the active Xcode workspace or project.

*No parameters.*

**Example usage:**

```json
{
  "name": "xcode_list_destinations",
  "arguments": {}
}
```

**Response:**
```json
[
  { "name": "My Mac", "platform": "macOS", "architecture": "arm64" },
  { "name": "iPhone 16 Pro", "platform": "iOS Simulator", "architecture": "arm64" },
  { "name": "iPad Air", "platform": "iOS Simulator", "architecture": "arm64" }
]
```

---

### xcode_get_errors

Retrieves current build diagnostics (errors and warnings) from Xcode.

*No parameters.*

**Example usage:**

```json
{
  "name": "xcode_get_errors",
  "arguments": {}
}
```

**Response:**
```json
[
  {
    "severity": "error",
    "message": "Cannot find 'foo' in scope",
    "filePath": "/path/to/ViewController.swift",
    "lineNumber": 15
  },
  {
    "severity": "warning",
    "message": "Result of call to 'bar()' is unused",
    "filePath": "/path/to/Helper.swift",
    "lineNumber": 8
  }
]
```

---

### xcode_get_build_log

Retrieves the build log from the last build/test action. Supports filtering by line count (tail) and grep pattern.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `lines` | integer | No | Return only the last N lines of the build log. If omitted, returns the full log. |
| `grep` | string | No | Filter the build log to only lines containing this substring (case-insensitive). Applied before line truncation. |

**Example usage:**

```json
{
  "name": "xcode_get_build_log",
  "arguments": {
    "lines": 50,
    "grep": "error"
  }
}
```

---

### xcode_get_test_log

Retrieves the test log from the last test action. Supports filtering by line count (tail) and grep pattern. Useful for inspecting detailed test output, failures, and diagnostics.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `lines` | integer | No | Return only the last N lines of the test log. If omitted, returns the full log. |
| `grep` | string | No | Filter the test log to only lines containing this substring (case-insensitive). Applied before line truncation. |

**Example usage:**

```json
{
  "name": "xcode_get_test_log",
  "arguments": {
    "lines": 100,
    "grep": "failed"
  }
}
```

**Response (filtered):**
```
Test Case '-[MyAppTests.LoginTests testInvalidCredentials]' failed (0.003 seconds).
```

---

### xcode_clean

Cleans the build folder in Xcode for the specified scheme.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scheme` | string | No | The scheme to clean. If omitted, cleans the active scheme. |

**Example usage:**

```json
{
  "name": "xcode_clean",
  "arguments": {
    "scheme": "MyApp"
  }
}
```

**Response:**
```json
{
  "status": "cleaned"
}
```

---

### xcode_list_packages

Lists all Swift Package Manager dependencies in the Xcode project, including package name, repository URL, and version requirement.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_list_packages",
  "arguments": {}
}
```

**Response:**
```json
[
  {
    "name": "Alamofire",
    "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
    "versionType": "from",
    "versionValue": "5.0.0"
  }
]
```

---

### xcode_add_package

Adds a Swift Package Manager dependency to the Xcode project with the specified repository URL and version requirement.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `url` | string | Yes | The repository URL of the Swift package (e.g., `https://github.com/user/repo.git`). |
| `versionType` | string | Yes | The version requirement type: `"from"`, `"exact"`, `"branch"`, or `"revision"`. |
| `versionValue` | string | Yes | The version value: a semver string for from/exact, a branch name for branch, or a 40-char hex commit hash for revision. |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_add_package",
  "arguments": {
    "url": "https://github.com/Alamofire/Alamofire.git",
    "versionType": "from",
    "versionValue": "5.9.0"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Package 'Alamofire' added successfully.",
  "package": {
    "name": "Alamofire",
    "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
    "versionType": "from",
    "versionValue": "5.9.0"
  }
}
```

---

### xcode_remove_package

Removes a Swift Package Manager dependency from the Xcode project. Also removes all linked product references from targets.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `identifier` | string | Yes | The package identifier: full repository URL (exact match) or package name (case-insensitive match). |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_remove_package",
  "arguments": {
    "identifier": "Alamofire"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Package matching 'Alamofire' removed successfully."
}
```

---

### xcode_list_targets

Lists all build targets in the Xcode project, including target name, product type, and bundle identifier.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_list_targets",
  "arguments": {}
}
```

**Response:**
```json
[
  {
    "name": "MyApp",
    "productType": "com.apple.product-type.application",
    "bundleIdentifier": "com.example.MyApp"
  },
  {
    "name": "MyAppTests",
    "productType": "com.apple.product-type.bundle.unit-test",
    "bundleIdentifier": "com.example.MyAppTests"
  }
]
```

---

### xcode_add_target

Adds a new build target to the Xcode project with Sources, Frameworks, and Resources build phases and default build settings.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | The name of the new target to create. |
| `productType` | string | Yes | The product type: `"application"`, `"framework"`, `"staticLibrary"`, `"dynamicLibrary"`, `"unitTestBundle"`, or `"uiTestBundle"`. |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_add_target",
  "arguments": {
    "name": "MyFramework",
    "productType": "framework"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Target 'MyFramework' added successfully.",
  "target": {
    "name": "MyFramework",
    "productType": "framework",
    "bundleIdentifier": "com.example.MyFramework"
  }
}
```

---

### xcode_remove_target

Removes a build target from the Xcode project, including its build configurations, build phases, dependencies from other targets, and references from shared schemes.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | The exact name of the target to remove (case-sensitive). |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_remove_target",
  "arguments": {
    "name": "OldFramework"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Target 'OldFramework' removed successfully."
}
```

---

### xcode_list_frameworks

Lists all frameworks and libraries linked to a specific target, including framework name, type, and whether it is required or optional.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `target` | string | Yes | The name of the target to list frameworks for. |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_list_frameworks",
  "arguments": {
    "target": "MyApp"
  }
}
```

**Response:**
```json
[
  {
    "name": "UIKit.framework",
    "isRequired": true,
    "type": "system"
  },
  {
    "name": "Alamofire",
    "isRequired": true,
    "type": "spmProduct"
  }
]
```

---

### xcode_add_framework

Adds a framework or library to a target's link build phase. Supports system frameworks, SPM package products, and project-relative frameworks.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `target` | string | Yes | The name of the target to add the framework to. |
| `framework` | string | Yes | The framework name: a system framework (e.g., `"UIKit.framework"`), an SPM product name (e.g., `"Alamofire"`), or a project-relative framework path. |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_add_framework",
  "arguments": {
    "target": "MyApp",
    "framework": "CoreData.framework"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Framework 'CoreData.framework' added to target 'MyApp' successfully."
}
```

---

### xcode_remove_framework

Removes a framework or library from a target's link build phase. Matches by name using a case-sensitive exact match.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `target` | string | Yes | The name of the target to remove the framework from. |
| `framework` | string | Yes | The framework name to remove (case-sensitive exact match). |
| `projectPath` | string | No | Absolute path to the `.xcodeproj` bundle. If omitted, resolves from the active Xcode workspace. |

**Example usage:**

```json
{
  "name": "xcode_remove_framework",
  "arguments": {
    "target": "MyApp",
    "framework": "CoreData.framework"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Framework 'CoreData.framework' removed from target 'MyApp' successfully."
}
```

---

## Typical Workflows

### Iterative development

1. Make code changes in your editor
2. Use `xcode_build` to trigger an incremental build (fast, uses warm cache)
3. If errors, use `xcode_get_errors` to see diagnostics with file paths and line numbers
4. Fix issues and repeat

### Running tests

1. Use `xcode_test` with a specific test identifier for focused testing
2. Use `xcode_test` without a test identifier to run the full suite
3. Review failure details in the response
4. Use `xcode_get_test_log` to inspect detailed test output, console logs, and failure diagnostics

### Exploring a project

1. Use `xcode_list_schemes` to discover available targets
2. Use `xcode_build` or `xcode_test` with the desired scheme

### Clean build

1. Use `xcode_clean` to clear the build folder
2. Use `xcode_build` to perform a fresh build

### Managing package dependencies

1. Use `xcode_list_packages` to see current SPM dependencies
2. Use `xcode_add_package` to add a new dependency with a version requirement
3. Use `xcode_remove_package` to remove an unused dependency (also cleans up linked products from targets)

### Managing targets

1. Use `xcode_list_targets` to see all targets in the project
2. Use `xcode_add_target` to create a new target (e.g., a framework or test bundle)
3. Use `xcode_remove_target` to remove a target (also cleans up scheme references and dependencies)

### Managing framework linkage

1. Use `xcode_list_frameworks` to see what's linked to a target
2. Use `xcode_add_framework` to link a system framework, SPM product, or project-relative framework
3. Use `xcode_remove_framework` to unlink a framework from a target

### Project Management — full workflow

1. Add a package dependency: `xcode_add_package` with the repo URL and version
2. Link the package product to your target: `xcode_add_framework` with the product name
3. Build to verify: `xcode_build`
4. If you need a new target: `xcode_add_target` then link frameworks to it
5. To clean up: `xcode_remove_framework` → `xcode_remove_package`

## Error Handling

All tools check that Xcode is running and has a project open before executing. If either condition is not met, the tool returns a descriptive error message. Build and test operations have a 300-second timeout; other operations time out after 30 seconds.
