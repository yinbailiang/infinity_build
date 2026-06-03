# Build Configuration Guide

This document provides detailed reference for all options in the `psproject.json` build configuration file.

## Configuration Structure

`psproject.json` is a JSON configuration file. The top level contains system configuration (`System`) and multiple build steps. Each build step corresponds to a Builder and executes in the order they appear in the JSON file.

```json
{
    "System": { ... },
    "PreDefineds": { ... },
    "Source": { ... },
    "Std": { ... },
    "Resource": { ... },
    "Nuget": { ... },
    "Boot": { ... }
}
```

---

## System — System Configuration

Defines project metadata and build behavior.

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `Name` | string | No | Config filename (without extension) | Project name, also used as default output filename |
| `Version` | string | No | — | Project version number |
| `Mode` | string | No | `"Debug"` | Build mode: `Debug` or `Release` |
| `CacheDir` | string | No | `".infinity_build"` | Cache directory path (relative paths are based on project root) |

### Example

```json
"System": {
    "Name": "my_tool",
    "Version": "2.1.0",
    "Mode": "Release",
    "CacheDir": ".build_cache"
}
```

---

## Output — Output Configuration

Controls the output file path.

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| (string value) | string | No | `"{Name}.ps1"` | Path to the output script |

### Example

```json
"Output": "bin/my_tool.ps1"
```

---

## Source — Source File Builder

Collects and parses source module files.

| Field | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `Files` | string[] | Yes | Source file path array, format as `directory/filePattern`, e.g. `src/core/*.psm1` (single-level directory only) |

### Example

```json
"Source": {
    "Files": [
        "src/core/*.psm1",
        "src/builders/*.psm1",
        "src/main.psm1"
    ]
}
```

### Source File Preprocessor Directives

Source files declare module information via comment-form preprocessor directives:

| Directive | Format | Description |
| --------- | ------ | ----------- |
| `##Module` | `##Module <Name>` | Declares the module name, overriding the filename |
| `##Import` | `##Import <ModuleName>` | Declares a dependency, ensuring prior ordering |
| `#infb: rm` | `#infb: rm` | End-of-line removal directive; the entire line is stripped during build |

```powershell
##Module Core.Logger

function Write-Log {
    param([string]$Message)
    Write-Host "[LOG] $Message"
    #infb: rm
    Write-Host "DEBUG: verbose log" #infb: rm
}
```

---

## Std — Standard Library Builder

Includes Infinity Build's built-in standard library modules.

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `Enable` | bool | No | `false` | Whether to enable the standard library |

The standard library provides NuGet framework resolution, NuGet version management, and other foundational utilities. The `std/std.json` configuration file controls which standard library modules are included.

### Example

```json
"Std": {
    "Enable": true
}
```

---

## PreDefineds — Predefined Variables Builder

Injects compile-time constants, generating the `Builtin.PreDefineds` module.

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `Default` | bool | No | `false` | Whether to inject default system variables (`$BuildName` / `$BuildVersion` / `$BuildMode`) |
| `Defineds` | object[] | No | `[]` | Custom predefined variables array, each item as `{ "key": "value" }` |

### Default System Variables

When `Default` is `true`, the following variables are automatically injected from `System` config:

| Variable | Type | Source | Description |
| -------- | ---- | ------ | ----------- |
| `$BuildName` | string | `System.Name` | Project name |
| `$BuildVersion` | string | `System.Version` | Project version number |
| `$BuildMode` | string | `System.Mode` | Build mode (`Debug` or `Release`) |

### Example

```json
"PreDefineds": {
    "Default": true,
    "Defineds": [
        { "APP_NAME": "my_tool" },
        { "BUILD_TIME": "2026-01-01" }
    ]
}
```

---

## Resource — Resource Builder

Embeds external resource files (icons, config files, etc.) into the output script.

| Field | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `Type` | string | No | `"Builtin"` | Resource type: `Builtin` (embedded in script) or `External` (output as standalone zip file) |
| `resources` | object[] | No | `[]` | Resource mapping array, each item as `{ "sourceDir": "targetPrefix" }` |
| `OutputDir` | string | No | Current directory | [External only] External resource output directory |
| `OutputName` | string | No | `"{Name}-resources.zip"` | [External only] External resource output filename |

### Example

```json
"Resource": {
    "Type": "Builtin",
    "resources": [
        { "res/icon.png": "assets/icon.png" },
        { "res/config.json": "config/default.json" }
    ]
}
```

---

## Nuget — NuGet Package Builder

Manages NuGet package dependencies, automatically downloading and referencing packages.

| Field | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `PackagesPath` | string | Yes | NuGet package library directory path |
| `Sources` | string[] | Yes | NuGet source URL array (uses the first entry), e.g. `["https://api.nuget.org/v3/index.json"]` |
| `Packs` | object[] | No | NuGet package list, each item as `{ "PackageId": "Version" }` |

### Example

```json
"Nuget": {
    "PackagesPath": ".packages",
    "Sources": ["https://api.nuget.org/v3/index.json"],
    "Packs": [
        { "Newtonsoft.Json": "13.0.3" }
    ]
}
```

---

## Boot — Boot Builder

Generates the program entry point, calling the specified entry function.

| Field | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `EntryPoint` | string | Yes | Entry function name |
| `Require` | string | No | Module name containing the entry function. When specified, unreachable modules are automatically pruned |

### Example

```json
"Boot": {
    "EntryPoint": "Invoke-Main",
    "Require": "Main"
}
```

The generated boot code is roughly:

```powershell
# ... all module code ...

# Execute entry point (forwards all command-line arguments)
Invoke-Main @args
```

---

## Full Configuration Example

```json
{
    "System": {
        "Name": "my_app",
        "Version": "1.0.0",
        "Mode": "Release",
        "CacheDir": ".infinity_build"
    },
    "Output": "bin/my_app.ps1",
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "APP_NAME": "my_app" }
        ]
    },
    "Std": {
        "Enable": true
    },
    "Source": {
        "Files": [
            "src/core/*.psm1",
            "src/builders/*.psm1",
            "src/main.psm1"
        ]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [
            { "res/icon.png": "assets/icon.png" }
        ]
    },
    "Boot": {
        "EntryPoint": "Invoke-Main",
        "Require": "Main"
    }
}
```

---

## Documentation Navigation

- [Quick Start](start.md) — Five-minute getting started guide
- [Document Center](../index.md) — Back to document home
