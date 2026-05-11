# Xcode Power

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![Xcode 15+](https://img.shields.io/badge/Xcode-15+-147EFB?style=flat&logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![MCP](https://img.shields.io/badge/MCP-Compatible-6366F1?style=flat)](https://modelcontextprotocol.io)
[![Kiro Power](https://img.shields.io/badge/Kiro-Power-FF6B00?style=flat)](https://kiro.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat)](LICENSE)
[![GitHub](https://img.shields.io/github/stars/rkroban/xcode-power?style=flat&logo=github)](https://github.com/rkroban/xcode-power)

A [Kiro](https://kiro.dev) Power that gives your AI assistant direct control over Xcode.app — triggering builds, running tests, launching apps, managing packages, targets, frameworks, and reading diagnostics — all through Xcode's warm build cache for near-instant feedback.

Instead of cold-starting `xcodebuild` from the command line, Xcode Power drives the running Xcode instance via JXA (JavaScript for Automation), so incremental builds take seconds, not minutes.

## Features

### Build & Run

| Tool | Description |
|------|-------------|
| `xcode_build` | Trigger an incremental build using Xcode's warm cache |
| `xcode_test` | Run all tests or a specific test class/method |
| `xcode_run` | Launch the app in the simulator or on device |
| `xcode_clean` | Clean the build folder |

### Diagnostics & Logs

| Tool | Description |
|------|-------------|
| `xcode_get_errors` | Retrieve current build diagnostics (errors & warnings) |
| `xcode_get_build_log` | Get the build log with optional filtering (tail/grep) |
| `xcode_get_test_log` | Get the test log with optional filtering (tail/grep) |

### Project Discovery

| Tool | Description |
|------|-------------|
| `xcode_list_schemes` | Discover available schemes in the workspace |
| `xcode_list_destinations` | List available run destinations (simulators, devices, My Mac) |
| `xcode_list_targets` | List all build targets with product type and bundle ID |

### Package Management (SPM)

| Tool | Description |
|------|-------------|
| `xcode_list_packages` | List all Swift Package Manager dependencies |
| `xcode_add_package` | Add an SPM dependency with version requirements |
| `xcode_remove_package` | Remove an SPM dependency and clean up linked products |

### Target Management

| Tool | Description |
|------|-------------|
| `xcode_add_target` | Create a new target (app, framework, library, test bundle) |
| `xcode_remove_target` | Remove a target and clean up scheme references |

### Framework Linkage

| Tool | Description |
|------|-------------|
| `xcode_list_frameworks` | List frameworks linked to a target |
| `xcode_add_framework` | Link a system framework, SPM product, or project framework |
| `xcode_remove_framework` | Unlink a framework from a target |

## Prerequisites

- **macOS 14.0+** (Xcode 15+ supported)
- **Xcode.app** installed and running with a project/workspace open
- **Swift 5.9+** toolchain (for building the server)

## Installation

### 1. Clone and build

```bash
git clone https://github.com/rkroban/xcode-power.git
cd xcode-power
make build
```

The compiled binary lands at `.build/release/XcodePower`.

Optionally install it to your PATH:

```bash
make install
# or a custom location:
make install INSTALL_DIR=~/.local/bin
```

### 2. Configure in Kiro

Add the MCP server to your Kiro configuration.

**Workspace-level** — create or edit `.kiro/settings/mcp.json` in your project:

```json
{
  "mcpServers": {
    "xcode-power": {
      "command": "/absolute/path/to/xcode-power/.build/release/XcodePower",
      "disabled": false,
      "autoApprove": [
        "xcode_build",
        "xcode_test",
        "xcode_run",
        "xcode_list_schemes",
        "xcode_list_destinations",
        "xcode_list_targets",
        "xcode_list_packages",
        "xcode_list_frameworks",
        "xcode_get_errors",
        "xcode_get_build_log",
        "xcode_get_test_log",
        "xcode_clean",
        "xcode_add_package",
        "xcode_remove_package",
        "xcode_add_target",
        "xcode_remove_target",
        "xcode_add_framework",
        "xcode_remove_framework"
      ]
    }
  }
}
```

**User-level** (available in all workspaces) — edit `~/.kiro/settings/mcp.json` with the same content.

> If you ran `make install`, you can use just `"command": "XcodePower"` instead of the full path.

### 3. Verify

After saving the config, the server should auto-connect. Check the MCP Server view in Kiro's feature panel or use the Command Palette → "MCP: List Servers" to confirm it's running.

## Usage

Once installed, Kiro's agent can use the tools automatically. You can also prompt it directly:

- *"Build my project"* → triggers `xcode_build`
- *"Run the tests for LoginTests"* → triggers `xcode_test`
- *"What build errors do I have?"* → triggers `xcode_get_errors`
- *"List my schemes"* → triggers `xcode_list_schemes`
- *"Add Alamofire to my project"* → triggers `xcode_add_package`
- *"What targets do I have?"* → triggers `xcode_list_targets`
- *"Link CoreData to MyApp"* → triggers `xcode_add_framework`
- *"Show me the test log"* → triggers `xcode_get_test_log`

See [POWER.md](POWER.md) for full tool documentation with parameter details and response formats.

## Workflows

### Iterative Development
1. Make code changes → `xcode_build` → `xcode_get_errors` → fix → repeat

### Test-Driven Development
1. Write tests → `xcode_test` → `xcode_get_test_log` → fix → repeat

### Dependency Management
1. `xcode_add_package` → `xcode_add_framework` (link to target) → `xcode_build`

### Project Scaffolding
1. `xcode_add_target` → `xcode_add_framework` (link dependencies) → `xcode_build`

## Architecture

```
Kiro ←→ stdio (JSON-RPC 2.0) ←→ XcodePower binary ←→ JXA/osascript ←→ Xcode.app
```

The MCP server reads JSON-RPC messages from stdin, translates tool calls into JXA scripts, executes them against the running Xcode instance, and returns structured results. Build and test operations poll for completion with a 300-second timeout; other operations time out after 30 seconds.

## Development

```bash
# Build release
make build

# Run tests
make test

# Clean build artifacts
make clean

# Build debug
swift build
```

The server uses Swift structured concurrency (actors, async/await) throughout, with protocol-based dependency injection for testability.

## License

MIT
