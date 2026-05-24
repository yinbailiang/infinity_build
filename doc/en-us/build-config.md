# Build Configuration Guide

Infinity Build uses JSON configuration files to drive the entire build process. This document explains every configuration parameter in detail.

---

## Configuration File Structure

The configuration file is a top-level JSON object containing a `System` metadata section and several build steps. Each top-level key (except `System`) corresponds to a **build step**.

```json
{
    "System": { ... },
    "Source": { ... },
    "Resource": { ... },
    "PreDefineds": { ... },
    "Nuget": { ... },
    "Boot": { ... },
    "Output": "build/output.ps1"
}
```

---

## System Section (Project Metadata)

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `Name` | `string` | No | Config filename | Project name, affects output file naming and built-in variables |
| `Version` | `string` | No | — | Project version, accessible via `$BuildVersion` |
| `Mode` | `string` | No | `"Debug"` | Build mode: `"Debug"` (verbose logs), `"Release"` |
| `CacheDir` | `string` | No | `".infinity_build"` | Cache directory, relative to config file location |

```json
"System": {
    "Name": "MyProject",
    "Version": "1.0.0",
    "Mode": "Debug",
    "CacheDir": ".infinity_build"
}
```

---

## Source Build Step (Source Code Processing)

Parses specified PowerShell source files into modules and performs topological sorting.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Files` | `string[]` | Yes | Source file glob pattern list, e.g., `["src/**/*.ps1"]` |

```json
"Source": {
    "Files": [
        "src/core/*.ps1",
        "src/utils/*.ps1",
        "src/main.ps1"
    ]
}
```

### Preprocessor Directives in Source Code

Source code supports the following inline build tags `#infb:`:

| Directive | Description |
|-----------|-------------|
| `#infb: rm` | Remove this line from build output |
| `#infb: debug` | Keep this line only in Debug mode |
| `#infb: release` | Keep this line only in Release mode |
| `#infb: replace <content>` | Replace this line with specified content |

Source code also supports block-level preprocessing directives `##`:

| Directive | Description |
|-----------|-------------|
| `## Module <name>` | Declare the module name |
| `## Import <module>` | Declare a module dependency |

---

## Resource Build Step (Resource Handling)

Packages static resource files.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `Type` | `string` | No | `"Builtin"` | Resource type: `"Builtin"` (embed in script), `"External"` (output as ZIP) |
| `resources` | `hashtable[]` | Yes | — | Array of source-to-destination path mappings |
| `OutputDir` | `string` | No | Working directory | External resource output directory (only for `Type=External`) |
| `OutputName` | `string` | No | `<Name>-resources.zip` | External resource output filename |

**Builtin mode example:**

```json
"Resource": {
    "Type": "Builtin",
    "resources": [
        { "assets/images/": "images" },
        { "assets/config/": "config" }
    ]
}
```

**External mode example:**

```json
"Resource": {
    "Type": "External",
    "OutputDir": "build",
    "OutputName": "game-resources.zip",
    "resources": [
        { "assets/": "" }
    ]
}
```

---

## PreDefineds Build Step (Predefined Variables)

Injects predefined variables into the build output.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `Default` | `bool` | No | `false` | Inject default system variables (`$BuildName`, `$BuildVersion`, `$BuildMode`) |
| `Defineds` | `hashtable[]` | No | `[]` | Array of custom variable definitions, supports `string`, `int`, `bool` types |

```json
"PreDefineds": {
    "Default": true,
    "Defineds": [
        { "AppName": "My Application" },
        { "MaxRetries": 3 },
        { "EnableFeatureX": true }
    ]
}
```

---

## Nuget Build Step (NuGet Dependency Management)

Automatically downloads and manages NuGet package dependencies.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Sources` | `string[]` | Yes | NuGet package source URL list (uses the first source) |
| `Packs` | `hashtable[]` | Yes | List of packages to install. Each element is an object `{ "PackageId": "Version" }`. Use `"Latest"` as version to always get the newest version |
| `PackagesPath` | `string` | Yes | Local package library storage path |

```json
"Nuget": {
    "Sources": ["https://api.nuget.org/v3/index.json"],
    "Packs": [
        { "Newtonsoft.Json": "13.0.3" },
        { "Serilog": "Latest" }
    ],
    "PackagesPath": "packages"
}
```

---

## Boot Build Step (Entry Point)

Generates the program entry point, calling the specified function.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `EntryPoint` | `string` | Yes | Entry point function name |
| `Require` | `string` | No | Declare dependency on a module |

```json
"Boot": {
    "EntryPoint": "Main",
    "Require": "Core"
}
```

---

## Output

Specifies the build output file path. Relative paths are based on the config file directory.

| Type | Required | Description |
|------|----------|-------------|
| `string` | No | Output `.ps1` file path, defaults to `<Name>.ps1` |

```json
"Output": "build/myapp.ps1"
```

---

## ExtraConfig (Programmatic Extension)

Use the `-ExtraConfig` parameter to dynamically inject additional build step configurations when calling `infinity_build.ps1`:

```powershell
.\infinity_build.ps1 -ConfigPath ".\base.json" -ExtraConfig @{
    "Boot" = @{
        "EntryPoint" = "CustomMain"
    }
}
```

Keys in ExtraConfig override or append to the build steps in the configuration file.

---

## Complete Configuration Example

```json
{
    "System": {
        "Name": "MyTool",
        "Version": "2.0.0",
        "Mode": "Release",
        "CacheDir": ".build_cache"
    },
    "Source": {
        "Files": ["src/**/*.ps1"]
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "ToolName": "MyTool" },
            { "LogRetentionDays": 30 }
        ]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [
            { "config/": "config" },
            { "templates/": "templates" }
        ]
    },
    "Boot": {
        "EntryPoint": "Start-Tool",
        "Require": "Core"
    },
    "Output": "dist/MyTool.ps1"
}
```
