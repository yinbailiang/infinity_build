# NuGet Management API — `infinity_nuget.ps1`

`infinity_nuget.ps1` provides complete NuGet package management capabilities, including package source resolution, package search, version management, download/installation, and local package library management.

---

## Classes

### `NugetSource`

Represents a NuGet package source, storing version and service endpoint information.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Version` | `string` | Protocol version of the package source |
| `ServiceEndpoints` | `hashtable` | Service endpoint dictionary, Key is service type, Value is endpoint URL |

Common service endpoint types:

| Key | Description |
|-----|-------------|
| `SearchQueryService` | Search service |
| `SearchQueryService/3.5.0` | Search service (with package type filtering) |
| `PackageBaseAddress/3.0.0` | Package download base address |
| `RegistrationsBaseUrl` | Package registration info |

### `NugetPackageLibraryManifest`

Represents a local package library manifest.

| Property | Type | Description |
|----------|------|-------------|
| `Packages` | `hashtable` | Package dictionary, Key is package ID (lowercase), Value is version info dictionary |

---

## Functions

### Package Source Management

#### `New-NugetSource`

Initialize a NuGet package source, retrieving service endpoints from an index URL.

```powershell
New-NugetSource -Url $Url
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Url` | `string` | Yes | NuGet source index URL, e.g., `https://api.nuget.org/v3/index.json` |

**Returns**: `NugetSource`

**Example**:

```powershell
$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
$source.Version                     # Output source version
$source.ServiceEndpoints.Keys       # List all available endpoints
```

---

### Package Search and Version Management

#### `Search-NugetPackage`

Search for NuGet packages in a specified source.

```powershell
Search-NugetPackage -Source $Source -Query $Query [-Take $Take] [-Skip $Skip] [-Prerelease] [-PackageType $Type]
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-Source` | `NugetSource` | Yes | — | Initialized package source |
| `-Query` | `string` | Yes | — | Search keyword, supports pipeline input |
| `-Take` | `int` | No | `20` | Number of results (1~1000) |
| `-Skip` | `int` | No | `0` | Pagination offset (0~3000) |
| `-Prerelease` | `switch` | No | — | Include prerelease versions |
| `-PackageType` | `string` | No | — | Package type filter (requires source 3.5.0 support) |

**Returns**: `hashtable[]` — Array of search results, each containing `id`, `version`, `description`, etc.

**Examples**:

```powershell
# Basic search
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 10

# Pipeline search
"Microsoft.Extensions.DependencyInjection" | Search-NugetPackage -Source $source

# Include prerelease
Search-NugetPackage -Source $source -Query "Serilog" -Prerelease
```

#### `ConvertTo-NuGetVersion`

Parse and normalize a NuGet version string, following the [official NuGet versioning specification](https://learn.microsoft.com/en-us/nuget/concepts/package-versioning).

```powershell
ConvertTo-NuGetVersion -VersionString $Version
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-VersionString` | `string` | Yes | Version string, supports pipeline input |

**Returns**: `hashtable` (ordered), containing:

| Key | Type | Description |
|-----|------|-------------|
| `OriginalVersion` | `string` | Original input version string |
| `NormalizedVersion` | `string` | NuGet normalized version |
| `Major` | `int` | Major version number |
| `Minor` | `int` | Minor version number |
| `Patch` | `int` | Patch version number |
| `Revision` | `int` | Revision number (0 if absent) |
| `CoreSegments` | `int[]` | Four core numeric segments |
| `PreRelease` | `string` | Prerelease label (`$null` if none) |
| `BuildMetadata` | `string` | Build metadata (`$null` if none) |

**Examples**:

```powershell
ConvertTo-NuGetVersion "v10.0.17763.1-preview"
# Output: NormalizedVersion = 10.0.17763.1-preview

ConvertTo-NuGetVersion "1.01.0-beta+git789"
# Output: NormalizedVersion = 1.1.0-beta+git789 (leading zeros removed)

ConvertTo-NuGetVersion "3.2.8-rc.2+20251226.git123"
# Output: PreRelease = rc.2, BuildMetadata = 20251226.git123
```

#### `Get-NugetPackageVersions`

Get all available versions of a specified package.

```powershell
Get-NugetPackageVersions -Source $Source -Id $Id [-Preview]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Source` | `NugetSource` | Yes | Initialized package source |
| `-Id` | `string` | Yes | Package ID |
| `-Preview` | `switch` | No | Include prerelease versions, default is stable only |

**Returns**: `hashtable[]` — Array of normalized version info.

**Examples**:

```powershell
# Get all stable versions
$versions = Get-NugetPackageVersions -Source $source -Id "Newtonsoft.Json"

# Include prerelease
$allVersions = Get-NugetPackageVersions -Source $source -Id "Microsoft.AspNetCore" -Preview
```

---

### Package Manifest and Content

#### `Get-NugetPackagManifest`

Get the manifest file (`.nuspec`) of a NuGet package, returning an XML document object.

```powershell
Get-NugetPackagManifest -Source $Source -Id $Id -Version $Version
```

**Returns**: `xml` — XML document object of the nuspec manifest.

**Example**:

```powershell
$manifest = Get-NugetPackagManifest -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
$manifest.package.metadata.id       # Package ID
$manifest.package.metadata.version   # Version

# View dependencies
$manifest | Select-Xml -XPath "//dependency" | Select-Object -ExpandProperty Node
```

#### `Get-NugetPackagContent`

Download the binary content of a NuGet package (`.nupkg` file).

```powershell
Get-NugetPackagContent -Source $Source -Id $Id -Version $Version
```

**Returns**: `byte[]` — Byte array of the package file.

**Example**:

```powershell
$bytes = Get-NugetPackagContent -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
[System.IO.File]::WriteAllBytes("Newtonsoft.Json.13.0.1.nupkg", $bytes)
```

---

### Package Library Management

#### `New-NugetPackageLibraryManifest`

Create a new local package library at the specified path.

```powershell
New-NugetPackageLibraryManifest -Path $Path
```

**Returns**: `string` — Full path of the created package library.

#### `Save-NugetPackageLibraryManifest` / `Read-NugetPackageLibraryManifest`

Save/read a package library manifest to/from a JSON file.

```powershell
Save-NugetPackageLibraryManifest -Path $Path -Manifest $Manifest
Read-NugetPackageLibraryManifest -Path $Path
```

#### `Install-NugetPackage`

Download and install a NuGet package into a local package library.

```powershell
Install-NugetPackage -Source $Source -Id $Id -Version $Version -LibraryPath $Path [-Force]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Source` | `NugetSource` | Yes | Package source object |
| `-Id` | `string` | Yes | Package ID |
| `-Version` | `string` | Yes | Package version |
| `-LibraryPath` | `string` | Yes | Local package library path |
| `-Force` | `switch` | No | Force reinstall (overwrite existing version) |

**Returns**: `string` — Installed package directory path.

**Library directory structure**:

```
<LibraryPath>/
├── infinity_nuget_library.json    # Library manifest
├── <package-id>/
│   └── <version>/
│       ├── <id>.<version>.nupkg   # Original package file
│       └── ...                    # Extracted package contents
```

#### `Uninstall-NugetPackage`

Uninstall a NuGet package from a local package library.

```powershell
# Uninstall specific version
Uninstall-NugetPackage -Id $Id -Version $Version -LibraryPath $Path

# Uninstall all versions
Uninstall-NugetPackage -Id $Id -LibraryPath $Path -AllVersions
```

**Returns**: `bool` — Whether the uninstall was successful.

#### `Update-NugetPackage`

Update a specified package to the latest version.

```powershell
Update-NugetPackage -Source $Source -Id $Id -LibraryPath $Path [-IncludePrerelease]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-IncludePrerelease` | `switch` | No | Include prerelease versions |

**Returns**: `string` — Updated package directory path.

---

## Complete Workflow Example

```powershell
. ./infinity_nuget.ps1

# 1. Connect to package source
$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"

# 2. Search for packages
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 5
$results | Format-Table id, version -AutoSize

# 3. View available versions
$versions = Get-NugetPackageVersions -Source $source -Id "Newtonsoft.Json"
$versions | Select-Object OriginalVersion, NormalizedVersion | Format-Table

# 4. Create local library and install
$libPath = New-NugetPackageLibraryManifest -Path ".\my_packages"
$pkgDir = Install-NugetPackage -Source $source -Id "Newtonsoft.Json" -Version "13.0.3" -LibraryPath $libPath

# 5. View package manifest
$manifest = Get-NugetPackagManifest -Source $source -Id "Newtonsoft.Json" -Version "13.0.3"

# 6. Update to latest version
$updatedDir = Update-NugetPackage -Source $source -Id "Newtonsoft.Json" -LibraryPath $libPath

# 7. Uninstall old version
Uninstall-NugetPackage -Id "Newtonsoft.Json" -Version "13.0.1" -LibraryPath $libPath
```
