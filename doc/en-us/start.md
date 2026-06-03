# Quick Start

Infinity Build is a PowerShell development kit that compiles modular `.psm1` source files into a single executable script.

## Overview

Infinity Build uses a `psproject.json` configuration file to describe the build pipeline. It merges scattered PowerShell module source files in dependency order, strips comments, minifies whitespace, and produces a standalone `.ps1` output script.

### Key Features

- **Modular Build** — Source files declare module names and dependencies via `##Module` / `##Import` preprocessor directives
- **Topological Sort** — Automatically resolves module dependencies to ensure correct code concatenation order
- **Comment Stripping** — Removes comments and blank lines to reduce output size
- **Source Mapping** — Generates a `.debug.json` file mapping output line numbers back to source file locations
- **Multiple Builders** — Supports Source, Std, PreDefineds, Resource, NuGet, and Boot build steps
- **Line Removal Directive** — Supports `#infb: rm` directive to mark debug/test lines for removal

## Requirements

- **PowerShell 7.0+**
- OS: Windows / Linux / macOS

## Quick Start

### 1. Prepare Project Structure

```Text
my-project/
├── psproject.json          # Build configuration file
├── src/
│   ├── core/
│   │   ├── __init__.psm1
│   │   ├── utils.psm1
│   │   └── logger.psm1
│   ├── builders/
│   │   ├── __init__.psm1
│   │   └── mybuilder.psm1
│   └── main.psm1
└── res/                    # Optional: resource files
```

### 2. Write Build Config `psproject.json`

```json
{
    "System": {
        "Name": "my_project",
        "Version": "1.0.0",
        "Mode": "Release",
        "CacheDir": ".infinity_build"
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "APP_NAME": "my_project" },
            { "APP_VERSION": "1.0.0" }
        ]
    },
    "Source": {
        "Files": [
            "src/core/*.psm1",
            "src/builders/*.psm1",
            "src/main.psm1"
        ]
    },
    "Boot": {
        "EntryPoint": "Invoke-Main",
        "Require": "Main"
    }
}
```

### 3. Write Source Modules

Source modules use `##Module` for module name and `##Import` for dependencies:

```powershell
##Module Main
##Import Core.Utils
##Import Core.Logger

function Invoke-Main {
    param(
        [string]$Name = "World"
    )
    Write-Host "Hello, $Name!"
    #infb: rm
    Write-Host "DEBUG: This line is removed in release builds" #infb: rm
}
```

### 4. Run Build

```powershell
./infinity_build.ps1
```

After a successful build, the output files are in the project root:

- `my_project.ps1` — Merged standalone script
- `my_project.debug.json` — Line mapping debug file

## Documentation Navigation

- [Build Configuration Guide](build-config.md) — In-depth guide to `psproject.json` options
- [Document Center](../index.md) — Back to document home
