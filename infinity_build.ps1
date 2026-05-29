<#
.NOTES
    Name: infinity_log.ps1
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    Infinity Build 的日志库
.DESCRIPTION
    这个模块提供功能完善的日志系统，包含以下特性：
    1. 多级别日志输出：Debug, Info, Warning, Error
    2. 控制台彩色输出
    4. 时间戳和调用者信息
    5. 灵活的日志配置
    6. 结构化日志记录
#>
enum LogType {
    LogErr = 0      # 错误
    LogWarn = 1     # 警告
    LogInfo = 2     # 信息
    LogDebug = 3    # 调试
}
class LogServer {
    [LogType]$LogLevel
    [string]$AppName = $null
    [bool]$EnableColors = $true
    LogServer([LogType]$Level) {
        $this.LogLevel = $Level
    }
    LogServer([LogType]$Level, [string]$AppName) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
    }
    [string]FormatMessage([LogType]$Type, [string]$Text) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelName = switch ($Type) {
            ([LogType]::LogErr) { "ERROR" }
            ([LogType]::LogWarn) { "WARN-" }
            ([LogType]::LogInfo) { "INFO-" }
            ([LogType]::LogDebug) { "DEBUG" }
        }
        if ($this.AppName) {
            return "[$timestamp][$($this.AppName)][$levelName]$Text"
        }
        else {
            return "[$timestamp][$levelName]$Text"
        }
    }
    [void]Write([LogType]$Type, [string]$Text) {
        if ([int]$Type -gt [int]$this.LogLevel) {
            return
        }
        $message = $this.FormatMessage($Type, $Text)
        if ($this.EnableColors) {
            $this.WriteColored($Type, $message)
        }
        else {
            Write-Host $message
        }
    }
    hidden [void]WriteColored([LogType]$Type, [string]$Message) {
        $colorCode = switch ($Type) {
            ([LogType]::LogErr) { "91" }  # 亮红色
            ([LogType]::LogWarn) { "93" }  # 亮黄色
            ([LogType]::LogInfo) { "96" }  # 亮青色
            ([LogType]::LogDebug) { "94" }  # 亮蓝色
        }
        Write-Host "`u{001b}[${colorCode}m$Message`u{001b}[0m"
    }
}
class LogClient {
    [LogServer]$Server
    [System.Collections.Generic.Stack[string]]$Context = @()
    LogClient([LogServer]$Server) {
        $this.Server = $Server
    }
    LogClient([LogType]$Level) {
        $this.Server = [LogServer]::new($Level)
    }
    [object]Scope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
        try {
            $Result = & $ScriptBlock
            $this.Info("完成: $ScopeName")
            return $Result
        }
        catch {
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }
    [object]MeasureScope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $Result = & $ScriptBlock
            $Stopwatch.Stop()
            $this.Info("完成: $ScopeName")
            $this.Info("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            return $Result
        }
        catch {
            $Stopwatch.Stop()
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            $this.Warn("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }
    [void]StartScope([string]$ScopeName) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
    }
    [void]EndScope() {
        $this.Info("完成: $($this.Context.Pop())")
    }
    [void]Error([string]$Message) {
        $this.WriteInternal([LogType]::LogErr, $Message)
    }
    [void]Warn([string]$Message) {
        $this.WriteInternal([LogType]::LogWarn, $Message)
    }
    [void]Info([string]$Message) {
        $this.WriteInternal([LogType]::LogInfo, $Message)
    }
    [void]Debug([string]$Message) {
        $this.WriteInternal([LogType]::LogDebug, $Message)
    }
    hidden [void]WriteInternal([LogType]$Type, [string]$Message) {
        $ContextPrefix = $this.BuildContextPrefix()
        $Lines = $Message -split "\r?\n"
        foreach ($Line in $Lines) {
            $this.Server.Write($Type, "$ContextPrefix $Line")
        }
    }
    hidden [string]BuildContextPrefix() {
        if ($this.Context.Count -ne 0) {
            $ContextArray = $this.Context.ToArray()
            [array]::Reverse($ContextArray)
            return "[$($ContextArray -join '.')]"
        }
        return ""
    }
}
$Script:ResourceInitialized = $false
$Script:ResourceRoot = $null
$Script:ResourceHashFile = $null
$Script:ResourceMode = if (Test-Path variable:Script:BuiltinResourceZipContent) {
    'Builtin'
} elseif (Test-Path variable:Script:BuiltinResourceZipName) {
    'External'
} else {
    $null
}
function Find-ResourceZip {
    [CmdletBinding()]
    param()
    $searchDirs = @()
    if ($PSCommandPath) {
        $searchDirs += Split-Path $PSCommandPath -Parent
    }
    $searchDirs += $PWD.Path
    if ($PSCommandPath) {
        $searchDirs += Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    }
    foreach ($dir in $searchDirs | Select-Object -Unique) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir $BuiltinResourceZipName
        if (Test-Path $candidate -PathType Leaf) {
            $actualHash = (Get-FileHash -Path $candidate -Algorithm SHA256).Hash
            if ($actualHash -eq $BuiltinResourceZipHash) {
                return $candidate
            }
            Write-Warning "[Std.Resource] ZIP 文件哈希不匹配: $candidate (期望: $BuiltinResourceZipHash, 实际: $actualHash)"
        }
    }
    throw @"
[Std.Resource] 找不到外部资源 ZIP 文件 '$BuiltinResourceZipName'。
已搜索以下目录:
$($searchDirs -join "`n")
请确保资源 ZIP 文件与构建产物位于同一目录。
"@
}
<#
.SYNOPSIS
    解压资源文件到目标目录（自动识别 Builtin / External 模式）。
.DESCRIPTION
    Builtin 模式：从嵌入的 Base64 数据解压。
    External 模式：查找外部 ZIP 文件并校验哈希后解压。
    首次调用后缓存哈希，资源未变更则跳过解压。
.PARAMETER TargetDir
    资源解压目标目录。未指定时使用系统临时目录下的
    "<项目名>_resources" 子目录。
.PARAMETER Force
    强制重新解压，忽略已有缓存。
.EXAMPLE
    Initialize-Resource
.EXAMPLE
    Initialize-Resource -TargetDir ".\assets" -Force
#>
function Initialize-Resource {
    [CmdletBinding()]
    param(
        [string]$TargetDir,
        [switch]$Force
    )
    if ($Script:ResourceInitialized -and -not $Force) {
        return $Script:ResourceRoot
    }
    if (-not $Script:ResourceMode) {
        throw @"
[Std.Resource] 未找到资源数据。
请确认:
  1. 构建配置中包含 Resource 构建步骤
  2. 资源配置了至少一个 resources 映射
  3. 构建产物中 Std.Resource 模块排在 Builtin.Resource 模块之后
"@
    }
    if (-not $TargetDir) {
        $AppId = if (Test-Path variable:Script:BuildName) { $BuildName } else { "app" }
        $TargetDir = Join-Path ([System.IO.Path]::GetTempPath()) "${AppId}_resources"
    }
    else {
        $TargetDir = Join-Path $PWD $TargetDir
    }
    $hashFile = Join-Path $TargetDir ".resource_hash"
    if (-not $Force -and (Test-Path $hashFile) -and (Test-Path $TargetDir)) {
        $cachedHash = Get-Content $hashFile -Raw -ErrorAction SilentlyContinue
        if ($cachedHash -and (Test-Path variable:Script:BuiltinResourceZipHash)) {
            if ($cachedHash.Trim() -eq $BuiltinResourceZipHash) {
                $Script:ResourceInitialized = $true
                $Script:ResourceRoot = (Get-Item $TargetDir).FullName
                $Script:ResourceHashFile = $hashFile
                return $Script:ResourceRoot
            }
        }
    }
    if ($Force -and (Test-Path $TargetDir)) {
        Remove-Item $TargetDir -Recurse -Force -ErrorAction Stop
    }
    if (-not (Test-Path $TargetDir)) {
        $null = New-Item -Path $TargetDir -ItemType Directory -Force -ErrorAction Stop
    }
    try {
        if ($Script:ResourceMode -eq 'Builtin') {
            $zipBytes = $BuiltinResourceZipContent
            $zipStream = [System.IO.MemoryStream]::new($zipBytes)
        }
        else {
            $zipPath = Find-ResourceZip
            $zipBytes = [System.IO.File]::ReadAllBytes($zipPath)
            $zipStream = [System.IO.MemoryStream]::new($zipBytes)
        }
        $zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Read)
        $extractDir = (Get-Item $TargetDir).FullName
        foreach ($entry in $zipArchive.Entries) {
            $destPath = Join-Path $extractDir $entry.FullName
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                if (-not (Test-Path $destPath)) {
                    $null = New-Item -Path $destPath -ItemType Directory -Force
                }
                continue
            }
            $parentDir = Split-Path $destPath -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                $null = New-Item -Path $parentDir -ItemType Directory -Force
            }
            $entryStream = $entry.Open()
            $fileStream = [System.IO.File]::Open($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try {
                $entryStream.CopyTo($fileStream)
            }
            finally {
                $fileStream.Dispose()
                $entryStream.Dispose()
            }
        }
        $zipArchive.Dispose()
        $zipStream.Dispose()
    }
    catch {
        throw "[Std.Resource] 资源解压失败: $($_.Exception.Message)"
    }
    if (Test-Path variable:Script:BuiltinResourceZipHash) {
        $BuiltinResourceZipHash | Set-Content $hashFile -NoNewLine -ErrorAction SilentlyContinue
    }
    $Script:ResourceInitialized = $true
    $Script:ResourceRoot = $extractDir
    $Script:ResourceHashFile = $hashFile
    return $Script:ResourceRoot
}
<#
.SYNOPSIS
    获取已解压资源的完整文件路径。
.DESCRIPTION
    根据资源包内的相对路径，返回解压后的完整路径。
    首次调用时会自动触发资源初始化（若尚未初始化）。
.PARAMETER RelativePath
    资源在包内的相对路径，如 "images/logo.png"。
    支持 / 和 \ 作为路径分隔符。
.EXAMPLE
    $logoPath = Get-ResourcePath "images/logo.png"
    $logoPath = Get-ResourcePath "config\settings.json"
#>
function Get-ResourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$RelativePath
    )
    begin {
        if (-not $Script:ResourceInitialized) {
            $null = Initialize-Resource
        }
    }
    process {
        $normalized = $RelativePath -replace '[/\\]', [System.IO.Path]::DirectorySeparatorChar
        $fullPath = Join-Path $Script:ResourceRoot $normalized
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            throw "[Std.Resource] 资源文件不存在: $RelativePath"
        }
        return $fullPath
    }
}
<#
.SYNOPSIS
    读取资源文件为文本内容。
.DESCRIPTION
    以 UTF-8 编码读取资源文件全文。
    适用于 .json、.txt、.md、.csv 等文本文件。
.PARAMETER RelativePath
    资源在包内的相对路径。
.EXAMPLE
    $config = Get-ResourceText "config/app.json" | ConvertFrom-Json
    $readme  = Get-ResourceText "README.md"
#>
function Get-ResourceText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )
    $path = Get-ResourcePath $RelativePath
    return Get-Content -Path $path -Raw -Encoding UTF8
}
<#
.SYNOPSIS
    读取资源文件为字节数组。
.DESCRIPTION
    以二进制方式读取资源文件。
    适用于 .png、.dll、.zip 等二进制文件。
.PARAMETER RelativePath
    资源在包内的相对路径。
.EXAMPLE
    $imageBytes = Get-ResourceBytes "assets/logo.png"
    [System.IO.File]::WriteAllBytes("$env:TEMP\logo.png", $imageBytes)
#>
function Get-ResourceBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )
    $path = Get-ResourcePath $RelativePath
    return [System.IO.File]::ReadAllBytes($path)
}
<#
.SYNOPSIS
    清理已解压的资源文件。
.DESCRIPTION
    删除资源解压目录及其所有内容，重置模块内部状态。
    下次调用 Initialize-Resource 将重新解压。
.EXAMPLE
    Clear-Resource
#>
function Clear-Resource {
    [CmdletBinding()]
    param()
    if ($Script:ResourceRoot -and (Test-Path $Script:ResourceRoot)) {
        Remove-Item $Script:ResourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $Script:ResourceInitialized = $false
    $Script:ResourceRoot = $null
    $Script:ResourceHashFile = $null
}
class InfinityModule {
    [string]$Name
    [System.Collections.Generic.List[string]]$Requires
    [System.Collections.Generic.List[string]]$Code
    [System.IO.FileInfo]$SourceInfo
    [System.Collections.Generic.Dictionary[int, int]]$LineMappings
}
class InfinityProgramSegment {
    [System.Collections.Generic.List[string]]$Code
    [System.Collections.Generic.Dictionary[int, System.Tuple[string, int]]]$LineMappings
}
class ResourceFileInfo {
    [System.IO.FileInfo]$FileInfo
    [string]$RelativePath
}
class ResourceFileHash {
    [string]$RelativePath
    [string]$Hash256
}
$Script:ModuleBuilders = @{}
$BuildName = 'infinity_build'
$BuildVersion = '2.0.0'
$BuildMode = 'Debug'
$Script:BuildLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityBuild")
$Script:BuildLogger = [LogClient]::new($Script:BuildLoggerServer)
function Add-PreDefinedVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [InfinityModule]$Module,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $Value
    )
    if ($Value -is [string]) {
        $Module.Code.Add("`$$Name = '$($Value.Replace("'","''"))'")
    }
    elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        $Module.Code.Add("`$$Name = $($Value.ToString())")
    }
    elseif ($Value -is [bool]) {
        $Module.Code.Add("`$$Name = `$" + ($Value ? "true" : "false"))
    }
    else {
        $Script:BuildLogger.Error("不支持的预定义变量类型: $Name -> $($Value.GetType())")
        throw "不支持的预定义变量类型: $Name -> $($Value.GetType())"
    }
}
function Get-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileInfo[]]$ResourceFiles
    )
    $HashList = [System.Collections.Generic.List[ResourceFileHash]]::new()
    $Script:BuildLogger.Info("计算资源文件快照 ($($ResourceFiles.Count) 个文件)")
    foreach ($ResourceFile in $ResourceFiles) {
        try {
            if (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf) {
                $FileHash = Get-FileHash -Path $ResourceFile.FileInfo -Algorithm SHA256 -ErrorAction Stop
                [void]$HashList.Add([ResourceFileHash]@{
                        RelativePath = $ResourceFile.RelativePath
                        Hash256      = $FileHash.Hash
                    })
            }
            else {
                $Script:BuildLogger.Warn("文件不存在，跳过: $($ResourceFile.FileInfo)")
            }
        }
        catch {
            $Script:BuildLogger.Warn("计算文件哈希失败 '$($ResourceFile.FileInfo)': $($_.Exception.Message)")
        }
    }
    $Script:BuildLogger.Info("资源快照计算完成: $($HashList.Count) 个文件")
    return $HashList.ToArray()
}
function Compare-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$NewSnapshot,
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$OldSnapshot
    )
    $Script:BuildLogger.Debug("比较资源快照: 新 $($NewSnapshot.Count) 个文件, 旧 $($OldSnapshot.Count) 个文件")
    if ($NewSnapshot.Count -ne $OldSnapshot.Count) {
        $Script:BuildLogger.Info("快照文件数量不同: 新 $($NewSnapshot.Count) vs 旧 $($OldSnapshot.Count)")
    }
    $OldFileHashTable = @{}
    foreach ($Item in $OldSnapshot) {
        $OldFileHashTable[$Item.RelativePath] = $Item.Hash256
    }
    $IsSame = $true
    foreach ($Item in $NewSnapshot) {
        $Path = $Item.RelativePath
        if (-not $OldFileHashTable.ContainsKey($Path)) {
            $Script:BuildLogger.Info("新增文件: $Path")
            $IsSame = $false
            continue
        }
        if ($OldFileHashTable[$Path] -ne $Item.Hash256) {
            $Script:BuildLogger.Info("文件哈希变化: $Path")
            $IsSame = $false
        }
        [void]$OldFileHashTable.Remove($Path)
    }
    foreach ($Path in $OldFileHashTable.Keys) {
        $Script:BuildLogger.Info("文件被删除：$Path")
        $IsSame = $false
    }
    $Script:BuildLogger.Debug("资源快照比较结果: $($IsSame ? '相同' : '不同')")
    return $IsSame
}
function Write-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$Snapshot,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        $Snapshot | ForEach-Object {
            @{
                RelativePath = $_.RelativePath
                Hash256      = $_.Hash256
            }
        } | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 -NoNewLine
        $Script:BuildLogger.Info("资源快照已保存到: $Path ($($Snapshot.Count) 个文件)")
    }
    catch {
        $Script:BuildLogger.Error("保存资源快照失败: $($_.Exception.Message)")
        throw
    }
}
function Read-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $Script:BuildLogger.Warn("未找到资源快照: $Path")
            return $null
        }
        $SnapshotData = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $Snapshot = @()
        foreach ($Item in $SnapshotData) {
            $Snapshot += [ResourceFileHash]@{
                RelativePath = $Item.RelativePath
                Hash256      = $Item.Hash256
            }
        }
        $Script:BuildLogger.Info("已从 $Path 读取 $($Snapshot.Count) 个文件快照")
        return $Snapshot
    }
    catch {
        $Script:BuildLogger.Warn("无法读取资源快照: $($_.Exception.Message)")
        return $null
    }
}
function Compress-ResourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileInfo[]]$ResourceFiles,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $false)]
        [System.IO.Compression.CompressionLevel]$CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    try {
        $Script:BuildLogger.Info("开始压缩 $($ResourceFiles.Count) 个资源文件到: $DestinationPath")
        $ZipFileStream = if ($Force -or -not (Test-Path $DestinationPath)) {
            [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create)
        }
        else {
            $Script:BuildLogger.Error("目标位置被占用: $DestinationPath")
            throw "目标位置被占用: $DestinationPath"
        }
        $ZipArchive = [System.IO.Compression.ZipArchive]::new($ZipFileStream, [System.IO.Compression.ZipArchiveMode]::Create)
        $FileCount = 0
        foreach ($ResourceFile in $ResourceFiles) {
            if (-not (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf)) {
                $Script:BuildLogger.Warn("找不到文件：$($ResourceFile.FileInfo)")
                $Script:BuildLogger.Warn("已自动跳过")
                continue
            }
            try {
                $EntryName = $ResourceFile.RelativePath -replace '^\.\\', '' -replace '^\./', ''
                $ZipEntry = $ZipArchive.CreateEntry($EntryName, $CompressionLevel)
                $EntryStream = $ZipEntry.Open()
                $FileStream = [System.IO.File]::OpenRead($ResourceFile.FileInfo)
                $FileStream.CopyTo($EntryStream)
                $EntryStream.Close()
                $FileStream.Close()
                $FileCount++
                if ($FileCount % 10 -eq 0) {
                    $Script:BuildLogger.Debug("  已压缩 $FileCount 个文件...")
                }
            }
            catch {
                $Script:BuildLogger.Error("压缩文件失败 '$($ResourceFile.FileInfo.FullName)': $($_.Exception.Message)")
                throw
            }
        }
        $ZipArchive.Dispose()
        $ZipFileStream.Close()
        $Script:BuildLogger.Info("资源压缩完成，共 $FileCount 个文件")
        if (Test-Path -Path $DestinationPath -PathType Leaf) {
            $ZipInfo = Get-Item -Path $DestinationPath
            $Script:BuildLogger.Info("ZIP文件大小: $([math]::Round($ZipInfo.Length / 1KB, 2)) KB")
        }
    }
    catch {
        $Script:BuildLogger.Error("无法压缩资源文件：$($_.Exception.Message)")
        throw
    }
}
function Get-ResourceEmbedModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipFilePath,
        [Parameter(Mandatory = $false)]
        [switch]$External,
        [Parameter(Mandatory = $false)]
        [string]$ExternalOutputPath
    )
    if (-not (Test-Path -Path $ZipFilePath -PathType Leaf)) {
        $Script:BuildLogger.Error("ZIP文件不存在: $ZipFilePath")
        return $null
    }
    try {
        $Script:BuildLogger.Info("生成资源嵌入模块: $ZipFilePath")
        $ZipBytes = [System.IO.File]::ReadAllBytes($ZipFilePath)
        $ZipHash = Get-FileHash -InputStream ([System.IO.MemoryStream]::new($ZipBytes)) -Algorithm SHA256
        $ResourceCode = if ($External) {
            $ZipFileName = if ($ExternalOutputPath) {
                [System.IO.Path]::GetFileName($ExternalOutputPath)
            } else {
                [System.IO.Path]::GetFileName($ZipFilePath)
            }
            $Script:BuildLogger.Info("外部模式 - ZIP文件名: $ZipFileName, 哈希: $($ZipHash.Hash)")
            @(
                "`$BuiltinResourceZipHash = `"$($ZipHash.Hash)`"",
                "`$BuiltinResourceZipName = `"$($ZipFileName.Replace('"','""'))`""
            )
        } else {
            $Base64Data = [System.Convert]::ToBase64String($ZipBytes)
            @(
                "`$BuiltinResourceZipHash = `"$($ZipHash.Hash)`"",
                "`$BuiltinResourceZipContent = [System.Convert]::FromBase64String(`"$($Base64Data)`")"
            )
        }
        $ResourceEmbedModule = [InfinityModule]@{
            Name         = 'Builtin.Resource'
            Code         = $ResourceCode
            Requires     = [System.Collections.Generic.List[string]]::new()
            SourceInfo   = Get-Item -Path $PSCommandPath
            LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
        }
        $ModuleCodeSize = [math]::Round(($ResourceEmbedModule.Code | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum / 1KB, 2)
        $Script:BuildLogger.Info("资源嵌入模块生成完成 (模块大小: $ModuleCodeSize KB)")
        return $ResourceEmbedModule
    }
    catch {
        $Script:BuildLogger.Error("生成资源嵌入模块失败: $($_.Exception.Message)")
        throw
    }
}
$Script:ModuleBuilders["Nuget"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    if (-not (Get-Command "New-NugetSource" -ErrorAction SilentlyContinue)) {
        . (Join-Path -Path $PSScriptRoot 'infinity_nuget.ps1')
    }
    $Script:NugetLogger.Info("配置: $($Config | ConvertTo-Json -Depth 3)")
    $PackagesPath = $Config["PackagesPath"]
    if (-not [System.IO.Path]::IsPathRooted($PackagesPath)) {
        $PackagesPath = Join-Path (Get-Location) $PackagesPath
    }
    if (-not (Test-Path -Path $PackagesPath -PathType Container)) {
        $null = New-Item -Path $PackagesPath -ItemType Directory
        $LibraryPath = New-NugetPackageLibraryManifest -Path $PackagesPath
    }
    else {
        $LibraryPath = (Get-Item -Path $PackagesPath).FullName
    }
    $Source = New-NugetSource -Url $Config['Sources'][0]
    foreach($Pack in $Config['Packs']){
        $Id = $Pack.Keys[0]
        $Ver = $Pack[$Pack.Keys[0]]
        if ($Ver -eq "Latest"){
            $null = Update-NugetPackage -Source $Source -Id $Id -LibraryPath $LibraryPath
        }
        else{
            $null = Install-NugetPackage -Source $Source -Id $Id -Version $Ver -LibraryPath $LibraryPath
        }
    }
    return @([InfinityModule]@{
        Name         = 'Builtin.Nuget'
        Code         = [System.Collections.Generic.List[string]]::new()
        Requires     = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}
function Find-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Filters,
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location)
    )
    $Script:BuildLogger.Debug("查找文件: 路径=$Path, 过滤器=$($Filters -join ', ')")
    $FoundFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($Filter in $Filters) {
        $LastSep = [Math]::Max($Filter.LastIndexOf('/'), $Filter.LastIndexOf('\'))
        if ($LastSep -ge 0) {
            $SubDir = $Filter.Substring(0, $LastSep)
            $FileFilter = $Filter.Substring($LastSep + 1)
            $SearchPath = Join-Path $Path $SubDir
        }
        else {
            $FileFilter = $Filter
            $SearchPath = $Path
        }
        $Script:BuildLogger.Debug("  搜索路径: $SearchPath, 文件过滤器: $FileFilter")
        $Files = Get-ChildItem -Path $SearchPath -Filter $FileFilter -File -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            $FoundFiles.Add($File.FullName)
        }
    }
    $Script:BuildLogger.Debug("找到 $($FoundFiles.Count) 个文件")
    return $FoundFiles.ToArray()
}
function New-InfinityProgramSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )
    $Script:BuildLogger.Info("生成程序段，包含 $($Modules.Count) 个模块")
    $ProgramSegment = [InfinityProgramSegment]@{
        Code         = [System.Collections.Generic.List[string]]::new()
        LineMappings = [System.Collections.Generic.Dictionary[int, System.Tuple[string, int]]]::new()
    }
    foreach ($Module in $Modules) {
        $Script:BuildLogger.Info("添加模块: $($Module.Name) ($($Module.Code.Count) 行)")
        $ModuleLineNum = 0
        foreach ($Line in $Module.Code) {
            $ModuleLineNum++
            $ProgramSegment.Code.Add($Line)
            if ($Module.LineMappings.ContainsKey($ModuleLineNum)) {
                $ProgramSegment.LineMappings[$ProgramSegment.Code.Count] = [System.Tuple[string, int]]::new($Module.SourceInfo.FullName, $Module.LineMappings[$ModuleLineNum])
            }
        }
    }
    $Script:BuildLogger.Info("程序段生成完成: $($ProgramSegment.Code.Count) 行代码, $($ProgramSegment.LineMappings.Count) 个行号映射")
    return $ProgramSegment
}
function Get-InfinityModule {
    [CmdletBinding()]
    [OutputType([InfinityModule])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $Script:BuildLogger.Info("读取模块: $Path")
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        $Script:BuildLogger.Error("模块文件不存在: $Path")
        throw "模块文件不存在: $Path"
    }
    try {
        $FileContent = Get-Content -Path $Path -ReadCount 0 -Raw
    }
    catch {
        $Script:BuildLogger.Error("读取模块文件失败 '$Path': $($_.Exception.Message)")
        throw "读取模块文件失败 '$Path': $($_.Exception.Message)"
    }
    $SourceInfo = Get-Item -Path $Path
    $InfinityModule = [InfinityModule]@{
        Name         = $SourceInfo.BaseName
        Requires     = [System.Collections.Generic.List[string]]::new()
        Code         = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = $SourceInfo
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    }
    [string[]]$Lines = $FileContent -split "\r?\n"
    for ([int]$i = 0; $i -lt $Lines.Count; ++$i) {
        if ([string]::IsNullOrWhiteSpace($Lines[$i])) {
            continue
        }
        if ($Lines[$i].Trim().StartsWith('#')) {
            if ($Lines[$i].Trim().StartsWith('##')) {
                $DirectiveParts = $Lines[$i].Trim().Substring(2) -split '\s+', 2
                switch ($DirectiveParts[0]) {
                    'Module' {
                        $InfinityModule.Name = $DirectiveParts[1].Trim()
                        $Script:BuildLogger.Debug("  模块名: $($InfinityModule.Name)")
                    }
                    'Import' {
                        $InfinityModule.Requires.Add($DirectiveParts[1].Trim())
                        $Script:BuildLogger.Debug("  依赖模块: $($DirectiveParts[1].Trim())")
                    }
                    Default {
                        $Script:BuildLogger.Warn("未知的预处理指令: $($Lines[$i])")
                        $Script:BuildLogger.Warn("来自: $($Path): line $($i+1)")
                    }
                }
            }
            if ($Lines[$i].Trim().StartsWith('#>')) {
                $InfinityModule.Code.Add($Lines[$i].TrimEnd())
                $InfinityModule.LineMappings[$InfinityModule.Code.Count] = $i + 1
            }
            continue
        }
        $InfinityModule.Code.Add($Lines[$i].TrimEnd())
        $InfinityModule.LineMappings[$InfinityModule.Code.Count] = $i + 1
    }
    $Script:BuildLogger.Info("模块 '$($InfinityModule.Name)' 读取完成: $($InfinityModule.Code.Count) 行代码, $($InfinityModule.Requires.Count) 个依赖")
    return $InfinityModule
}
function Get-InfinityModuleOrdered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )
    $Script:BuildLogger.Info("对 $($Modules.Count) 个模块进行拓扑排序")
    $ModuleMap = [System.Collections.Generic.Dictionary[string, InfinityModule]]::new()
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    $InDegree = [System.Collections.Generic.Dictionary[string, int]]::new()
    $AdjacencyList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]::new()
    foreach ($Module in $Modules) {
        $InDegree[$Module.Name] = 0
        $AdjacencyList[$Module.Name] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($Module in $Modules) {
        foreach ($RequiredModuleName in $Module.Requires) {
            if (-not $ModuleMap.ContainsKey($RequiredModuleName)) {
                $Script:BuildLogger.Warn("模块 '$($Module.Name)' 依赖的模块 '$RequiredModuleName' 不在提供的模块列表中")
                continue
            }
            $AdjacencyList[$RequiredModuleName].Add($Module.Name)
            $InDegree[$Module.Name] += 1
        }
    }
    $SortedModules = [System.Collections.Generic.List[InfinityModule]]::new()
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($ModuleName in $InDegree.Keys) {
        if ($InDegree[$ModuleName] -eq 0) {
            $Queue.Enqueue($ModuleName)
        }
    }
    while ($Queue.Count -gt 0) {
        $CurrentModuleName = $Queue.Dequeue()
        $SortedModules.Add($ModuleMap[$CurrentModuleName])
        foreach ($DependentModuleName in $AdjacencyList[$CurrentModuleName]) {
            $InDegree[$DependentModuleName] -= 1
            if ($InDegree[$DependentModuleName] -eq 0) {
                $Queue.Enqueue($DependentModuleName)
            }
        }
    }
    if ($SortedModules.Count -ne $Modules.Count) {
        $RemainingModules = @()
        foreach ($ModuleName in $InDegree.Keys) {
            if ($InDegree[$ModuleName] -gt 0) {
                $RemainingModules += $ModuleName
            }
        }
        $Script:BuildLogger.Error("检测到循环依赖！受影响的模块: $($RemainingModules -join ', ')")
        throw "检测到循环依赖！受影响的模块: $($RemainingModules -join ', ')"
    }
    $Script:BuildLogger.Info("拓扑排序完成，顺序: $($SortedModules.Name -join ' -> ')")
    return $SortedModules
}
$Script:ModuleBuilders["Boot"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $EntryPoint = if ($Config.ContainsKey("EntryPoint")) {
        $Config["EntryPoint"]
    } else {
        $Script:BuildLogger.Warn("Boot 配置中缺少 'EntryPoint'，跳过启动模块生成")
        return @()
    }
    $RequireList = [System.Collections.Generic.List[string]]::new()
    if ($Config.ContainsKey("Require")) {
        $RequireList.Add($Config["Require"])
        $Script:BuildLogger.Info("启动模块依赖: $($Config['Require'])")
    }
    $Script:BuildLogger.Info("生成启动模块，入口函数: $EntryPoint")
    $BootCode = [System.Collections.Generic.List[string]]::new()
    $BootCode.Add("$EntryPoint @args")
    return @([InfinityModule]@{
        Name         = 'Builtin.Boot'
        Code         = $BootCode
        Requires     = $RequireList
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}
$Script:ModuleBuilders["PreDefineds"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $Script:BuildLogger.Info("生成预定义变量模块")
    $PreDefinedsModule = [InfinityModule]@{
        Name         = 'Builtin.PreDefineds'
        Requires     = [System.Collections.Generic.List[string]]::new()
        Code         = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    }
    $IncludeDefault = if ($Config.ContainsKey("Default")) { $Config["Default"] } else { $false }
    $DefinedsList = if ($Config.ContainsKey("Defineds") -and $Config["Defineds"] -is [array]) {
        $Config["Defineds"]
    } else { @() }
    if ($IncludeDefault) {
        if ($Script:BuildSystem.ContainsKey("Name")) {
            $PreDefinedsModule.Code.Add("`$BuildName = '$($Script:BuildSystem['Name'].Replace("'","''"))'")
        }
        if ($Script:BuildSystem.ContainsKey("Version")) {
            $PreDefinedsModule.Code.Add("`$BuildVersion = '$($Script:BuildSystem['Version'].Replace("'","''"))'")
        }
        if ($Script:BuildSystem.ContainsKey("Mode")) {
            $PreDefinedsModule.Code.Add("`$BuildMode = '$($Script:BuildSystem['Mode'].Replace("'","''"))'")
        }
        $Script:BuildLogger.Info("  已注入 $($PreDefinedsModule.Code.Count) 个默认系统变量")
    }
    foreach ($Item in $DefinedsList) {
        if ($Item -is [hashtable]) {
            foreach ($Name in $Item.Keys) {
                Add-PreDefinedVariable -Module $PreDefinedsModule -Name $Name -Value $Item[$Name]
            }
        }
    }
    $Script:BuildLogger.Info("预定义变量模块生成完成: $($PreDefinedsModule.Code.Count) 个变量")
    return @($PreDefinedsModule)
}
$Script:ModuleBuilders["Resource"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $ResourceZipPath = Join-Path $Script:CacheFolder "resource.zip"
    $ResourceSnapshotPath = Join-Path $Script:CacheFolder "resource_snapshot.json"
    $ResourceType = if ($Config.ContainsKey("Type")) { $Config["Type"] } else { "Builtin" }
    if ($ResourceType -notin @("Builtin", "External")) {
        $Script:BuildLogger.Error("不支持的资源类型: $ResourceType")
        throw "不支持的资源类型: $ResourceType"
    }
    $ResourceMappings = if ($Config.ContainsKey("resources") -and $Config["resources"] -is [array]) {
        $Config["resources"]
    } else { @() }
    if ($ResourceMappings.Count -eq 0) {
        $Script:BuildLogger.Warn("资源配置中没有资源映射，跳过资源构建")
        return @()
    }
    $AllResourceFiles = [System.Collections.Generic.List[ResourceFileInfo]]::new()
    foreach ($Mapping in $ResourceMappings) {
        if ($Mapping -isnot [hashtable] -or $Mapping.Count -eq 0) {
            $Script:BuildLogger.Warn("跳过无效的资源映射条目")
            continue
        }
        foreach ($SourceRel in $Mapping.Keys) {
            $DestPrefix = $Mapping[$SourceRel]
            $SourcePath = if ([System.IO.Path]::IsPathRooted($SourceRel)) {
                $SourceRel
            } else {
                Join-Path (Get-Location) $SourceRel
            }
            $DestPrefix = $DestPrefix -replace '^\.\\|^\./|\\$|/$', ''
            $DestPrefix = $DestPrefix -replace '\\', '/'
            $Script:BuildLogger.Info("资源映射: $SourceRel -> $DestPrefix/")
            if (-not (Test-Path $SourcePath -PathType Container)) {
                $Script:BuildLogger.Warn("资源源目录不存在: $SourcePath，跳过")
                continue
            }
            $Files = Get-ChildItem -Path $SourcePath -File -Recurse -ErrorAction SilentlyContinue
            foreach ($File in $Files) {
                try {
                    $FileRelativePath = Resolve-Path -Path $File -Relative -RelativeBasePath $SourcePath
                    $FileRelativePath = $FileRelativePath -replace '^\.\\|^\./', ''
                    $FileRelativePath = $FileRelativePath -replace '\\', '/'
                    $ZipEntryPath = if ($DestPrefix) {
                        "$DestPrefix/$FileRelativePath"
                    } else {
                        $FileRelativePath
                    }
                    $AllResourceFiles.Add([ResourceFileInfo]@{
                        FileInfo     = $File
                        RelativePath = $ZipEntryPath
                    })
                }
                catch {
                    $Script:BuildLogger.Warn("处理资源文件失败 '$($File.FullName)': $($_.Exception.Message)")
                }
            }
        }
    }
    if ($AllResourceFiles.Count -eq 0) {
        $Script:BuildLogger.Error("没有找到任何资源文件，无法构建资源模块")
        throw "没有找到任何资源文件，无法构建资源模块"
    }
    $ResourceFiles = $AllResourceFiles.ToArray()
    $Script:BuildLogger.Info("共收集 $($ResourceFiles.Count) 个资源文件（来自 $($ResourceMappings.Count) 个源）")
    $CurrentSnapshot = Get-ResourceSnapshot -ResourceFiles $ResourceFiles
    $PreviousSnapshot = Read-ResourceSnapshot -Path $ResourceSnapshotPath
    $IsChanged = if ($PreviousSnapshot) {
        -not (Compare-ResourceSnapshot -NewSnapshot $CurrentSnapshot -OldSnapshot $PreviousSnapshot)
    }
    else {
        $Script:BuildLogger.Info("未找到先前的资源快照文件: $ResourceSnapshotPath")
        $true
    }
    if ($IsChanged) {
        $Script:BuildLogger.Info("资源发生变化，开始压缩资源...")
        Compress-ResourceFiles -ResourceFiles $ResourceFiles -DestinationPath $ResourceZipPath -Force
        Write-ResourceSnapshot -Snapshot $CurrentSnapshot -Path $ResourceSnapshotPath
        $Script:BuildLogger.Info("资源压缩完成，已更新快照")
    }
    else {
        $Script:BuildLogger.Info("资源未发生变化，使用缓存的资源压缩包")
    }
    if ($ResourceType -eq "Builtin") {
        $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
        $Ret = if ($Module) { @($Module) } else { @() }
        return $Ret
    }
    elseif ($ResourceType -eq "External") {
        $ExternalOutputDir = if ($Config.ContainsKey("OutputDir")) {
            $OutDir = $Config["OutputDir"]
            if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
                Join-Path (Get-Location) $OutDir
            } else {
                $OutDir
            }
        } else {
            (Get-Location)
        }
        $ExternalOutputName = if ($Config.ContainsKey("OutputName")) {
            $Config["OutputName"]
        } else {
            "$Script:BuildName-resources.zip"
        }
        if ($ExternalOutputName -notmatch '\.zip$') {
            $ExternalOutputName += '.zip'
        }
        $ExternalOutputPath = Join-Path $ExternalOutputDir $ExternalOutputName
        if (-not (Test-Path $ExternalOutputDir -PathType Container)) {
            $null = New-Item -Path $ExternalOutputDir -ItemType Directory -Force
            $Script:BuildLogger.Info("创建外部资源输出目录: $ExternalOutputDir")
        }
        Copy-Item -Path $ResourceZipPath -Destination $ExternalOutputPath -Force
        $Script:BuildLogger.Info("资源包已复制到外部路径: $ExternalOutputPath")
        $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath -External -ExternalOutputPath $ExternalOutputPath
        $Ret = if ($Module) { @($Module) } else { @() }
        return $Ret
    }
}
$Script:ModuleBuilders["Source"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $SourceFiles = Find-Files -Filters $Config.Files
    $Script:BuildLogger.Info("找到 $($SourceFiles.Count) 个源文件")
    if ($SourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到任何源文件")
        return @()
    }
    $Modules = $SourceFiles | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}
$Script:ModuleBuilders["Std"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    if ($Config.ContainsKey("Enable")){
        if (-not $Config.Enable){
            return @()
        }
    }
    $StdLibPath = Join-Path $PSScriptRoot "std"
    $SourceFiles = Get-ChildItem $StdLibPath -Filter "*.psm1" -Recurse
    $Script:BuildLogger.Info("找到 $($SourceFiles.Count) 个标准库源文件")
    if ($SourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到标准库源文件")
        return @()
    }
    $Modules = $SourceFiles | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}
function Invoke-Main {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = 'psproject.json',
        [Parameter(Mandatory = $false)]
        [hashtable]$ExtraConfig
    )
    $Script:BuildLogger.Info("PowerShell 版本: $PSVersion")
    (Get-Location) = (Get-Item -Path $ConfigPath).Directory
    $Script:BuildLogger.Info("工作目录: $WorkFolder")
    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)){
        $Script:BuildLogger.Error("未找到配置文件: $ConfigPath")
        throw "未找到配置文件: $ConfigPath"
    }else{
        $Script:BuildLogger.Info("读取配置文件: $ConfigPath")
        $Script:BuildConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    }
    $Script:BuildSystem = if ($Script:BuildConfig.ContainsKey("System")) {
        $Script:BuildConfig["System"]
    } else { @{} }
    $Script:BuildName = if ($Script:BuildSystem.ContainsKey("Name")) {
        $Script:BuildSystem["Name"]
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    }
    $Script:CacheFolder = if ($Script:BuildSystem.ContainsKey("CacheDir")) {
        $CacheDir = $Script:BuildSystem["CacheDir"]
        if (-not [System.IO.Path]::IsPathRooted($CacheDir)) {
            Join-Path (Get-Location) $CacheDir
        } else {
            $CacheDir
        }
    } else {
        Join-Path (Get-Location) ".infinity_build"
    }
    $Script:BuildLogger.Info("缓存目录: $CacheFolder")
    if (-not (Test-Path -Path $CacheFolder -PathType Container)) {
        $Script:BuildLogger.Info("创建缓存目录: $CacheFolder")
        if (-not (New-Item -Path $CacheFolder -ItemType Directory -Force)) {
            $Script:BuildLogger.Error("无法创建缓存目录: $CacheFolder")
            throw "无法创建缓存目录: $CacheFolder"
        }
    }
    $Script:BuildLogger.Info("=== Infinity Build 开始 ===")
    $BuildSteps = @{}
    $MetaKeys = @("System", "Output")
    foreach ($Key in $Script:BuildConfig.Keys) {
        if ($Key -notin $MetaKeys) {
            $BuildSteps[$Key] = $Script:BuildConfig[$Key]
        }
    }
    if ($BuildSteps.Count -eq 0) {
        $Script:BuildLogger.Error("未找到任何构建步骤")
        throw "未找到任何构建步骤"
    }
    $Script:BuildLogger.Info("构建步骤: $($BuildSteps.Keys -join ', ')")
    if ($ExtraConfig) {
        $Script:BuildLogger.Info("应用额外配置: $($ExtraConfig.Keys -join ', ')")
        foreach ($Key in $ExtraConfig.Keys) {
            $BuildSteps[$Key] = $ExtraConfig[$Key]
        }
    }
    $AllModules = [System.Collections.Generic.List[InfinityModule]]::new()
    foreach ($StepName in $BuildSteps.Keys) {
        if (-not $Script:ModuleBuilders.ContainsKey($StepName)) {
            $Script:BuildLogger.Warn("未注册的构建步骤: $StepName，已跳过")
            continue
        }
        $StepConfig = $BuildSteps[$StepName]
        if ($StepName -eq "Nuget") {
            $Packs = if ($StepConfig.ContainsKey("Packs") -and $StepConfig["Packs"] -is [array]) {
                $StepConfig["Packs"]
            } else { @() }
            if ($Packs.Count -eq 0) {
                $Script:BuildLogger.Info("Nuget.Packs 为空，跳过 Nuget 步骤")
                continue
            }
        }
        $Script:BuildLogger.MeasureScope("构建步骤: $StepName", {
            $Result = & $Script:ModuleBuilders[$StepName] -Config $StepConfig
            if ($Result) {
                foreach ($Module in $Result) {
                    $AllModules.Add($Module)
                }
            }
        })
    }
    $Script:BuildLogger.Info("共生成 $($AllModules.Count) 个模块")
    if ($AllModules.Count -eq 0) {
        $Script:BuildLogger.Error("未生成任何模块，构建终止")
        throw "未生成任何模块，构建终止"
    }
    $Script:BuildLogger.Info("开始拓扑排序...")
    $SortedModules = Get-InfinityModuleOrdered -Modules $AllModules.ToArray()
    $ProgramSegment = New-InfinityProgramSegment -Modules $SortedModules
    $OutputPath = if ($Script:BuildConfig.ContainsKey("Output")) {
        $Script:BuildConfig["Output"]
    }
    elseif ($Script:BuildName) {
        "$($Script:BuildName).ps1"
    }
    else {
        "output.ps1"
    }
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location) $OutputPath
    }
    $OutputDir = Split-Path $OutputPath -Parent
    if ($OutputDir -and -not (Test-Path $OutputDir)) {
        $null = New-Item -Path $OutputDir -ItemType Directory -Force
        $Script:BuildLogger.Info("创建输出目录: $OutputDir")
    }
    $Script:BuildLogger.Info("写入输出脚本: $OutputPath")
    $ProgramSegment.Code | Set-Content -Path $OutputPath -Encoding UTF8
    $DebugInfoPath = [System.IO.Path]::ChangeExtension($OutputPath, ".debug.json")
    $Script:BuildLogger.Info("写入调试信息: $DebugInfoPath")
    $DebugInfoList = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($Key in ($ProgramSegment.LineMappings.Keys | Sort-Object)) {
        $Mapping = $ProgramSegment.LineMappings[$Key]
        $DebugInfoList.Add(@{
            OutputLine    = $Key
            SourceFile    = $Mapping.Item1
            SourceLineNum = $Mapping.Item2
        })
    }
    $DebugInfoList | ConvertTo-Json -Depth 2 -Compress | Set-Content -Path $DebugInfoPath -Encoding UTF8 -NoNewLine
    $OutputSize = (Get-Item $OutputPath).Length
    $Script:BuildLogger.Info("输出文件: $OutputPath ($([math]::Round($OutputSize / 1KB, 2)) KB)")
    $Script:BuildLogger.Info("调试文件: $DebugInfoPath")
}
Invoke-Main @args
