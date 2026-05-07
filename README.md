# Xcode Power

A [Kiro](https://kiro.dev) Power that gives your AI assistant direct control over Xcode.app — triggering builds, running tests, launching apps, and reading diagnostics — all through Xcode's warm build cache for near-instant feedback.

Instead of cold-starting `xcodebuild` from the command line, Xcode Power drives the running Xcode instance via JXA (JavaScript for Automation), so incremental builds take seconds, not minutes.

## Features

| Tool | Description |
|------|-------------|
| `xcode_build` | Trigger an incremental build using Xcode's warm cache |
| `xcode_test` | Run all tests or a specific test class/method |
| `xcode_run` | Launch the app in the simulator or on device |
| `xcode_list_schemes` | Discover available schemes in the workspace |
| `xcode_get_errors` | Retrieve current build diagnostics (errors & warnings) |
| `xcode_clean` | Clean the build folder |

## Prerequisites

- **macOS** (Xcode 15+ supported)
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
        "xcode_get_errors",
        "xcode_clean"
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
- *"Run the tests for LoginTests"* → triggers `xcode_test` with a test identifier
- *"What build errors do I have?"* → triggers `xcode_get_errors`
- *"List my schemes"* → triggers `xcode_list_schemes`

See [POWER.md](POWER.md) for full tool documentation with parameter details and response formats.

## Development

```bash
# Run tests
make test

# Clean build artifacts
make clean

# Build debug
swift build
```

The server uses Swift structured concurrency (actors, async/await) throughout, with protocol-based dependency injection for testability.

## How It Works

```
Kiro ←→ stdio (JSON-RPC 2.0) ←→ XcodePower binary ←→ JXA/osascript ←→ Xcode.app
```

The MCP server reads JSON-RPC messages from stdin, translates tool calls into JXA scripts, executes them against the running Xcode instance, and returns structured results. Build and test operations poll for completion with a 300-second timeout; other operations time out after 30 seconds.

## License

MIT
