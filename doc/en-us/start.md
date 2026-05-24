# PowerShell Development Kit — Infinity Build

Infinity Build is a comprehensive script development and build toolkit designed for PowerShell 7.0 and above, aiming to enhance the development efficiency and engineering standards of PowerShell scripting.

---

## System Requirements

- **PowerShell Version**: 7.0+
- **Git** (for cloning the repository)

---

## Quick Start

### 1. Clone the Repository

Open PowerShell and run the following command to clone the project locally:

```powershell
git clone https://github.com/yinbailiang/infinity_build.git
```

### 2. Navigate to the Project Directory

```powershell
Set-Location infinity_build
```

---

## API Documentation

Infinity Build consists of four core modules, each providing an independent PowerShell API:

### Module Overview

| Module | File | Purpose |
|--------|------|---------|
| Logging | `infinity_log.ps1` | Multi-level colored log output, structured logging |
| Build System | `infinity_build.ps1` | Module parsing, topological sorting, resource packaging, program generation |
| NuGet Management | `infinity_nuget.ps1` | Package search, download, install, uninstall, update |
| Debug Tool | `infinity_dbg.ps1` | Error capturing and source line mapping |

> For detailed API documentation, see: [Logging API](api/log.md) | [Build Module API](api/build.md) | [NuGet Management API](api/nuget.md) | [Debug Tool API](api/dbg.md)

### Build Configuration

Infinity Build uses JSON configuration files to drive the build process. The configuration file structure is as follows:

```json
{
    "System": {
        "Name": "MyProject",
        "Mode": "Debug",
        "Version": "1.0.0",
        "CacheDir": ".infinity_build"
    },
    "Source": {
        "Files": ["src/**/*.ps1"]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [{ "assets/": "assets" }]
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [{ "AppName": "MyApp" }]
    },
    "Boot": {
        "EntryPoint": "Main",
        "Require": "Core"
    },
    "Output": "build/output.ps1"
}
```

> For complete configuration details, see: [Build Configuration Guide](build-config.md)

### Quick Examples

**Example 1: Using the Logging Library**

```powershell
# Import the logging library
. ./infinity_log.ps1

# Create log server and client
$server = [LogServer]::new([LogType]::LogDebug, "MyApp")
$logger = [LogClient]::new($server)

# Write logs
$logger.Info("Application started")
$logger.Debug("Debug information")
$logger.Warn("Warning message")
$logger.Error("Error message")

# Use scoping
$logger.Scope("Data Processing", {
    $logger.Info("Processing...")
})
```

**Example 2: Searching NuGet Packages**

```powershell
. ./infinity_nuget.ps1

$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 5
$results | Format-Table id, version
```

**Example 3: Running a Build**

```powershell
.\infinity_build.ps1 -ConfigPath ".\myproject.json"
```

**Example 4: Debugging Build Output**

```powershell
.\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1"
```

---

## Get Help

If you encounter any issues or have suggestions, please provide feedback via the project's [Issues page](https://github.com/yinbailiang/infinity_build/issues).

---

If you find this project helpful, feel free to give it a ⭐ for support!