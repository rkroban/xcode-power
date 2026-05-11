# Design Document

## Overview

This feature adds Xcode project management tools to the MCP server using the Tuist XcodeProj library to read/write `.pbxproj` files. The design follows the existing handler-based architecture, introducing a new `ProjectManager` actor as the core component for project file operations, and 9 new `ToolHandler` implementations.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   MCP Server                         │
│  ┌───────────────────────────────────────────────┐  │
│  │              ToolRegistry                      │  │
│  │  ┌─────────────────┐  ┌────────────────────┐  │  │
│  │  │ Existing Tools   │  │ Project Mgmt Tools │  │  │
│  │  │ (Build, Test...) │  │ (Packages, Targets │  │  │
│  │  │                  │  │  Frameworks)       │  │  │
│  │  └────────┬─────────┘  └────────┬───────────┘  │  │
│  └───────────┼──────────────────────┼──────────────┘  │
│              │                      │                  │
│              ▼                      ▼                  │
│  ┌──────────────────┐   ┌──────────────────────┐     │
│  │ XcodeController  │   │   ProjectManager     │     │
│  │ (JXA scripting)  │   │ (XcodeProj library)  │     │
│  └──────────────────┘   └──────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

## Key Components

### ProjectManager (Actor)
- Serializes all write operations via Swift actor isolation
- Uses XcodeProj to parse/modify/write `.pbxproj` files
- Resolves project path from Xcode (via XcodeController JXA) or explicit parameter
- Provides methods: listPackages, addPackage, removePackage, listTargets, addTarget, removeTarget, listFrameworks, addFramework, removeFramework

### New Handlers (9 total)
- `ListPackagesHandler` → `xcode_list_packages`
- `AddPackageHandler` → `xcode_add_package`
- `RemovePackageHandler` → `xcode_remove_package`
- `ListTargetsHandler` → `xcode_list_targets`
- `AddTargetHandler` → `xcode_add_target`
- `RemoveTargetHandler` → `xcode_remove_target`
- `ListFrameworksHandler` → `xcode_list_frameworks`
- `AddFrameworkHandler` → `xcode_add_framework`
- `RemoveFrameworkHandler` → `xcode_remove_framework`

### New Models
- `PackageInfo`: name, repositoryURL, versionRequirement (type + value)
- `TargetInfo`: name, productType, bundleIdentifier?
- `FrameworkInfo`: name, isRequired, type (system/spmProduct/projectRelative)

## Dependency
- XcodeProj (Tuist): `https://github.com/tuist/XcodeProj.git`, from: "8.0.0"
