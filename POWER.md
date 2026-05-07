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

### Exploring a project

1. Use `xcode_list_schemes` to discover available targets
2. Use `xcode_build` or `xcode_test` with the desired scheme

### Clean build

1. Use `xcode_clean` to clear the build folder
2. Use `xcode_build` to perform a fresh build

## Error Handling

All tools check that Xcode is running and has a project open before executing. If either condition is not met, the tool returns a descriptive error message. Build and test operations have a 300-second timeout; other operations time out after 30 seconds.
