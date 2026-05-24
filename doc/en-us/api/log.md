# Logging API — `infinity_log.ps1`

`infinity_log.ps1` is the logging subsystem of Infinity Build, providing multi-level, timestamped, and colorized structured logging.

---

## Enum

### `LogType`

Defines log levels. Higher numeric values include all lower-level messages (Debug level shows everything).

| Name | Value | Description |
|------|-------|-------------|
| `LogErr` | `0` | Error level |
| `LogWarn` | `1` | Warning level |
| `LogInfo` | `2` | Info level |
| `LogDebug` | `3` | Debug level (most verbose) |

---

## Classes

### `LogServer`

Log server responsible for formatting and outputting log messages. Controls log level, application name, and color output.

#### Constructors

```powershell
[LogServer]::new([LogType]$Level)
[LogServer]::new([LogType]$Level, [string]$AppName)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `$Level` | `LogType` | Log level threshold; messages higher than this are ignored |
| `$AppName` | `string` | Optional, application name displayed in log prefix |

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `LogLevel` | `LogType` | Specified in constructor | Current log level |
| `AppName` | `string` | `$null` | Application name |
| `EnableColors` | `bool` | `$true` | Enable colored output |

#### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `FormatMessage([LogType]$Type, [string]$Text)` | `string` | Format a log message |
| `Write([LogType]$Type, [string]$Text)` | `void` | Write a log entry (auto-filtered by level) |

#### Log Output Colors

| Level | Color |
|-------|-------|
| `LogErr` | Bright Red |
| `LogWarn` | Bright Yellow |
| `LogInfo` | Bright Cyan |
| `LogDebug` | Bright Blue |

---

### `LogClient`

Log client providing convenient logging methods with **scoped context** support.

#### Constructors

```powershell
[LogClient]::new([LogServer]$Server)
[LogClient]::new([LogType]$Level)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `$Server` | `LogServer` | Associated log server instance |
| `$Level` | `LogType` | Create a built-in LogServer with the specified level |

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Server` | `LogServer` | Associated log server |
| `Context` | `Stack[string]` | Current scope stack (LIFO) |

#### Methods

##### Log Writing Methods

| Method | Description |
|--------|-------------|
| `Error([string]$Message)` | Write an error log |
| `Warn([string]$Message)` | Write a warning log |
| `Info([string]$Message)` | Write an info log |
| `Debug([string]$Message)` | Write a debug log |

##### Scoping Methods

```powershell
# Execute a script block within an auto-scope (with error handling)
[object] Scope([string]$ScopeName, [scriptblock]$ScriptBlock)

# Execute a script block within an auto-scope (with elapsed time)
[object] MeasureScope([string]$ScopeName, [scriptblock]$ScriptBlock)

# Manually start a scope
[void] StartScope([string]$ScopeName)

# Manually end the most recent scope
[void] EndScope()
```

> `Scope` and `MeasureScope` automatically print "begin" and "end" logs before and after execution.
> `MeasureScope` additionally outputs elapsed time (accurate to milliseconds).
> If the `ScriptBlock` throws an exception, it is automatically captured and re-thrown with error logging.

---

## Output Format

```
[2026-05-24 10:30:45][AppName][INFO-] Application started
[2026-05-24 10:30:45][AppName][INFO-] [Data.Load] Begin: Load Config
[2026-05-24 10:30:45][AppName][INFO-] [Data.Load] End: Load Config
[2026-05-24 10:30:45][AppName][ERROR] [Data.Load] Config file not found
```

- Timestamp format: `yyyy-MM-dd HH:mm:ss`
- Scope prefix: `[Scope1.Scope2...]`

---

## Usage Examples

### Basic Usage

```powershell
. ./infinity_log.ps1

$server = [LogServer]::new([LogType]::LogDebug, "MyApp")
$log = [LogClient]::new($server)

$log.Info("Service starting...")
$log.Debug("Config value: port=8080")
$log.Warn("Disk space low")
$log.Error("Failed to connect to database")
```

### Scoping Usage

```powershell
$log.Scope("Initialization", {
    $log.Info("Loading modules...")
    # ... initialization code ...
})

# With elapsed time measurement
$result = $log.MeasureScope("Data Processing", {
    Start-Sleep -Seconds 2
    return "Processing complete"
})
# Output: End: Data Processing
# Output: Elapsed: 2.015s

# Manual scoping
$log.StartScope("Phase One")
$log.Info("Executing...")
$log.EndScope()
```

### Show Only Errors and Warnings

```powershell
$server = [LogServer]::new([LogType]::LogWarn, "Monitor")
$log = [LogClient]::new($server)

$log.Info("This won't print")   # Level higher than LogWarn, filtered
$log.Warn("This will print")    # Level equals LogWarn, passes
$log.Error("This also prints")  # Level lower than LogWarn, passes
```

### Disable Color Output

```powershell
$server = [LogServer]::new([LogType]::LogDebug, "CI")
$server.EnableColors = $false
$log = [LogClient]::new($server)
```

---

## Module Load Protection

`infinity_log.ps1` uses the `$Script:LogLoaded` variable to prevent duplicate loading. When referenced by other modules (such as `infinity_build.ps1`, `infinity_nuget.ps1`), type redefinitions are automatically skipped to avoid errors.

```powershell
# Safe reference in other scripts
if (-not $Script:LogLoaded) {
    . (Join-Path $PSScriptRoot 'infinity_log.ps1')
}
```
