# Build Module API — `infinity_build.ps1`

`infinity_build.ps1` is the core module of Infinity Build, responsible for parsing source files, managing module dependencies, packaging resources, and generating the final executable script.

---

## Parameters

| Parameter | Type | Required | Description |
| - | - | - | - |
| `-ConfigPath` | `string` | Yes | JSON path to the build configuration file |
| `-ExtraConfig` | `hashtable` | No | Additional build step config, merged into config file steps |

```powershell
.\infinity_build.ps1 -ConfigPath ".\myproject.json"
.\infinity_build.ps1 -ConfigPath ".\base.json" -ExtraConfig @{ Boot = @{ EntryPoint = "CustomMain" } }
```

---

## Classes

### `InfinityModule`

Represents a parsed code module.

| Property | Type | Description |
| - | - | - |
| `Name` | `string` | Module name |
| `Requires` | `List[string]` | List of dependent module names |
| `Code` | `List[string]` | Module code lines |
| `SourceInfo` | `FileInfo` | Source file information |
| `LineMappings` | `Dictionary[int, int]` | Output line → source line mapping |

### `InfinityProgramSegment`

Represents a complete program segment (merged from multiple modules).

| Property | Type | Description |
| - | - | - |
| `Code` | `List[string]` | All merged code lines |
| `LineMappings` | `Dictionary[int, Tuple[string, int]]` | Output line → (source file path, source line) mapping |

### `ResourceFileInfo`

Resource file information.

| Property | Type | Description |
| - | - | - |
| `FileInfo` | `FileInfo` | File system info |
| `RelativePath` | `string` | Relative path within the resource package |

### `ResourceFileHash`

Resource file hash record.

| Property | Type | Description |
| - | - | - |
| `RelativePath` | `string` | Relative path within the resource package |
| `Hash256` | `string` | SHA256 hash of the file |

---

## Functions

### File Processing

#### `Find-Files`

Find files by glob patterns.

```powershell
Find-Files -Filters $Filters [-Path $Path]
```

| Parameter | Type | Required | Default | Description |
| - | - | - | - | - |
| `-Filters` | `string[]` | Yes | — | File filter array, e.g., `@("src/*.ps1", "lib/**/*.psm1")` |
| `-Path` | `string` | No | Working directory | Search root directory |

**Returns**: `string[]` — Array of full paths of matching files.

---

### Module Processing

#### `Get-InfinityModule`

Parse a single source file into an `InfinityModule` object. Automatically handles preprocessor directives (`#infb:` and `##`).

```powershell
Get-InfinityModule -Path $Path
```

| Parameter | Type | Required | Description |
| - | - | - | - |
| `-Path` | `string` | Yes | Source file path |

**Returns**: `InfinityModule` — Parsed module object.

**Preprocessor Directives:**

| Directive | Description |
| - | - |
| `## Module <name>` | Declare module name (overrides filename) |
| `## Import <module>` | Declare dependency on another module |
| `#infb: rm` | Remove this line during build |
| `#infb: debug` | Keep only in Debug mode |
| `#infb: release` | Keep only in Release mode |
| `#infb: replace <content>` | Replace entire line with specified content |

#### `Get-InfinityModuleOrdered`

Topologically sort a module list by dependency order, detecting circular dependencies.

```powershell
Get-InfinityModuleOrdered -Modules $Modules
```

| Parameter | Type | Required | Description |
| - | - | - | - |
| `-Modules` | `InfinityModule[]` | Yes | Module array to sort |

**Returns**: `InfinityModule[]` — Modules sorted by dependency order (dependencies first).

**Exception**: Throws on circular dependency detection.

#### `New-InfinityProgramSegment`

Merge ordered modules into a program segment.

```powershell
New-InfinityProgramSegment -Modules $Modules
```

**Returns**: `InfinityProgramSegment` — Merged program segment.

---

### Resource Processing

#### `Get-ResourceSnapshot`

Calculate SHA256 snapshot of resource files.

```powershell
Get-ResourceSnapshot -ResourceFiles $ResourceFiles
```

**Returns**: `ResourceFileHash[]` — Array of file hashes.

#### `Compare-ResourceSnapshot`

Compare two resource snapshots for equality.

```powershell
Compare-ResourceSnapshot -NewSnapshot $New -OldSnapshot $Old
```

**Returns**: `bool` — `$true` if identical, `$false` if changes detected.

#### `Write-ResourceSnapshot` / `Read-ResourceSnapshot`

Write/read resource snapshots to/from JSON files for incremental build caching.

```powershell
Write-ResourceSnapshot -Snapshot $Snapshot -Path $Path
Read-ResourceSnapshot -Path $Path
```

#### `Compress-ResourceFiles`

Compress resource files into a ZIP archive.

```powershell
Compress-ResourceFiles -ResourceFiles $Files -DestinationPath $Dest [-CompressionLevel $Level] [-Force]
```

| Parameter | Type | Default | Description |
| - | - | - | - |
| `-CompressionLevel` | `CompressionLevel` | `Optimal` | Compression level |
| `-Force` | `switch` | — | Overwrite existing ZIP file |

#### `Get-ResourceEmbedModule`

Convert a ZIP file into a Base64-embedded module (`Builtin.Resource`).

```powershell
Get-ResourceEmbedModule -ZipFilePath $ZipPath
```

**Returns**: `InfinityModule` — Module containing resource data, with `$BuiltinResourceZipHash` and `$BuiltinResourceZipContent` variables.

---

### Build Steps (Module Builders)

The build system is driven by a **module builder dictionary**, where each build step corresponds to a builder script block.

| Build Step | Description |
| - | - |
| `Source` | Parse source files into modules, topological sort |
| `Std` | Parse standard library (`std/` directory) modules |
| `Resource` | Collect and incrementally package resource files |
| `PreDefineds` | Generate predefined variable module |
| `Nuget` | Download and manage NuGet package dependencies |
| `Boot` | Generate the entry point module |

#### `Add-PreDefinedVariable`

Add a variable to the predefined variables module.

```powershell
Add-PreDefinedVariable -Module $Module -Name $Name -Value $Value
```

| Parameter | Type | Description |
| - | - | - |
| `-Value` | `string` / `int` / `bool` | Variable value, supports three basic types |

---

## Build Outputs

Two files are generated after a successful build:

| File | Description |
| - | - |
| `<Output>.ps1` | The final merged script (standalone executable) |
| `<Output>.debug.json` | Debug mapping file for `infinity_dbg.ps1` |

Debug mapping file format:

```json
[
    { "OutputLine": 1, "SourceFile": "C:\\src\\core.ps1", "SourceLineNum": 5 },
    { "OutputLine": 2, "SourceFile": "C:\\src\\core.ps1", "SourceLineNum": 6 }
]
```

---

## Complete Workflow Example

```powershell
# 1. Prepare configuration file myproject.json (see Build Configuration Guide)
# 2. Execute the build
.\infinity_build.ps1 -ConfigPath ".\myproject.json"

# 3. Run the built output
.\output.ps1

# 4. Or run with the debugger
.\infinity_dbg.ps1 -ScriptPath ".\output.ps1"
```
