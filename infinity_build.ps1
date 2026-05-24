<#
.NOTES
    Name: infinity_build
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    Infinity Build 的核心模块, 用以进行项目的构建
.DESCRIPTION
    这个工具提供以下功能：
    1. 管理项目
    2. 打包项目
    3. 打包资源
#>

#region 参数
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [hashtable]$ExtraConfig
)
#endregion

#region 检查
$PSVersion = $PSVersionTable.PSVersion
if ($PSVersion.Major -lt 7) {
    Write-Error "需要 PowerShell 7.0 或更高版本，当前版本: $PSVersion"
    Exit 1
}
if (-not (Test-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'infinity_log.ps1') -PathType Leaf)){
    Write-Error "未找到依赖 infinity_log.ps1 文件，无法继续"
    Exit 2
}
#endregion

#region 日志初始化
. (Join-Path $PSScriptRoot 'infinity_log.ps1')
$Script:BuildLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityBuild")
$Script:BuildLogger = [LogClient]::new($Script:BuildLoggerServer)
#endregion

#region 初始化
$Script:BuildLogger.Info("PowerShell 版本: $PSVersion")

$Script:WorkFolder = (Get-Item -Path $ConfigPath).Directory
$Script:BuildLogger.Info("工作目录: $WorkFolder")

if (-not (Test-Path -Path $ConfigPath -PathType Leaf)){
    $Script:BuildLogger.Error("未找到配置文件: $ConfigPath")
    throw "未找到配置文件: $ConfigPath"
}else{
    $Script:BuildLogger.Info("读取配置文件: $ConfigPath")
    $Script:BuildConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
}

# 从 System 节读取项目元信息
$Script:BuildSystem = if ($Script:BuildConfig.ContainsKey("System")) {
    $Script:BuildConfig["System"]
} else { @{} }

$Script:BuildName = if ($Script:BuildSystem.ContainsKey("Name")) {
    $Script:BuildSystem["Name"]
} else {
    [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
}

# 根据 System.Mode 调整日志级别
if ($Script:BuildSystem.ContainsKey("Mode")) {
    switch ($Script:BuildSystem["Mode"]) {
        "Debug" {
            $Script:BuildLoggerServer.LogLevel = [LogType]::LogDebug
            $Script:BuildLogger.Info("构建模式: Debug（详细日志）")
        }
        "Release" {
            $Script:BuildLoggerServer.LogLevel = [LogType]::LogInfo
            $Script:BuildLogger.Info("构建模式: Release")
        }
        Default {
            $Script:BuildLogger.Warn("未知的构建模式: $($Script:BuildSystem['Mode'])，使用 Debug")
        }
    }
}

# 确定缓存目录（优先使用 System.CacheDir）
$Script:CacheFolder = if ($Script:BuildSystem.ContainsKey("CacheDir")) {
    $CacheDir = $Script:BuildSystem["CacheDir"]
    if (-not [System.IO.Path]::IsPathRooted($CacheDir)) {
        Join-Path $Script:WorkFolder $CacheDir
    } else {
        $CacheDir
    }
} else {
    Join-Path $Script:WorkFolder ".infinity_build"
}
$Script:BuildLogger.Info("缓存目录: $CacheFolder")

# 确保缓存目录存在
if (-not (Test-Path -Path $CacheFolder -PathType Container)) {
    $Script:BuildLogger.Info("创建缓存目录: $CacheFolder")
    if (-not (New-Item -Path $CacheFolder -ItemType Directory -Force)) {
        $Script:BuildLogger.Error("无法创建缓存目录: $CacheFolder")
        throw "无法创建缓存目录: $CacheFolder"
    }
}
#endregion

#region 文件处理
function Find-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Filters,
        
        [Parameter(Mandatory = $false)]
        [string]$Path = $Script:WorkFolder
    )
    
    $Script:BuildLogger.Debug("查找文件: 路径=$Path, 过滤器=$($Filters -join ', ')")
    $FoundFiles = [System.Collections.Generic.List[string]]::new()
    
    foreach ($Filter in $Filters) {
        # 解析路径模式：将 "src/*.psm1" 拆分为目录 "src" 和文件过滤器 "*.psm1"
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
#endregion

#region 模块处理
class InfinityModule {
    [string]$Name
    [System.Collections.Generic.List[string]]$Requires
    [System.Collections.Generic.List[string]]$Code
    [System.IO.FileInfo]$SourceInfo
    [System.Collections.Generic.Dictionary[int, int]]$LineMappings
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
    
    # 创建模块名称到模块对象的映射
    $ModuleMap = [System.Collections.Generic.Dictionary[string, InfinityModule]]::new()
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    
    # 计算每个模块的入度（依赖数）
    $InDegree = [System.Collections.Generic.Dictionary[string, int]]::new()
    $AdjacencyList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]::new()
    
    foreach ($Module in $Modules) {
        $InDegree[$Module.Name] = 0
        $AdjacencyList[$Module.Name] = [System.Collections.Generic.List[string]]::new()
    }
    
    # 构建邻接表和计算入度
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
    
    # 拓扑排序
    $SortedModules = [System.Collections.Generic.List[InfinityModule]]::new()
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    
    # 将所有入度为0的模块加入队列
    foreach ($ModuleName in $InDegree.Keys) {
        if ($InDegree[$ModuleName] -eq 0) {
            $Queue.Enqueue($ModuleName)
        }
    }
    
    # 处理队列
    while ($Queue.Count -gt 0) {
        $CurrentModuleName = $Queue.Dequeue()
        $SortedModules.Add($ModuleMap[$CurrentModuleName])
        
        # 减少所有依赖当前模块的模块的入度
        foreach ($DependentModuleName in $AdjacencyList[$CurrentModuleName]) {
            $InDegree[$DependentModuleName] -= 1
            if ($InDegree[$DependentModuleName] -eq 0) {
                $Queue.Enqueue($DependentModuleName)
            }
        }
    }
    
    # 检查是否有环
    if ($SortedModules.Count -ne $Modules.Count) {
        # 找出所有有剩余入度的模块（形成环的模块）
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

class InfinityProgramSegment {
    [System.Collections.Generic.List[string]]$Code
    [System.Collections.Generic.Dictionary[int, System.Tuple[string, int]]]$LineMappings
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
#endregion

#region 资源处理
class ResourceFileInfo {
    [System.IO.FileInfo]$FileInfo
    [string]$RelativePath
}

class ResourceFileHash {
    [string]$RelativePath
    [string]$Hash256
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
            # 检查文件是否存在
            if (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf) {
                # 以SHA256算法获取文件哈希
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

    # 把老快照转换为 RelativePath -> Hash 的 Map 方便后续计算
    $OldFileHashTable = @{}
    foreach ($Item in $OldSnapshot) {
        $OldFileHashTable[$Item.RelativePath] = $Item.Hash256
    }
    
    $IsSame = $true
    foreach ($Item in $NewSnapshot) {
        $Path = $Item.RelativePath
        # 检查该文件是否为新增
        if (-not $OldFileHashTable.ContainsKey($Path)) {
            $Script:BuildLogger.Info("新增文件: $Path")
            $IsSame = $false
            # 新增文件在老快照中没有对应 Hash 直接跳过
            continue
        }
        # 检查哈希
        if ($OldFileHashTable[$Path] -ne $Item.Hash256) {
            $Script:BuildLogger.Info("文件哈希变化: $Path")
            $IsSame = $false
        }
        # 从老快照的 Map 中删除
        [void]$OldFileHashTable.Remove($Path)
    }

    # 如果老快照中还有剩余的项目，说明新快照中删除了部分文件
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
        [string]$ZipFilePath
    )
    
    if (-not (Test-Path -Path $ZipFilePath -PathType Leaf)) {
        $Script:BuildLogger.Error("ZIP文件不存在: $ZipFilePath")
        return $null
    }
    
    try {
        $Script:BuildLogger.Info("生成资源嵌入模块: $ZipFilePath")
        $ZipBytes = [System.IO.File]::ReadAllBytes($ZipFilePath)
        $ZipHash = Get-FileHash -InputStream ([System.IO.MemoryStream]::new($ZipBytes)) -Algorithm SHA256
        $Base64Data = [System.Convert]::ToBase64String($ZipBytes)

        $ResourceCode = @(
            "`$BuiltinResourceZipHash = `"$($ZipHash.Hash)`"",
            "`$BuiltinResourceZipContent = [System.Convert]::FromBase64String(`"$($Base64Data)`")"
        )

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
#endregion

#region 构建器模块
$Script:ModuleBuilders = @{}

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
    return @(Get-InfinityModuleOrdered -Modules $Modules)
}

# ---- Resource 构建器 ----
$Script:ModuleBuilders["Resource"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $ResourceZipPath = Join-Path $Script:CacheFolder "resource.zip"
    $ResourceSnapshotPath = Join-Path $Script:CacheFolder "resource_snapshot.json"
    
    # 配置格式: { "Type": "Builtin", "resources": [ {source: dest}, ... ] }
    $ResourceType = if ($Config.ContainsKey("Type")) { $Config["Type"] } else { "Builtin" }
    if ($ResourceType -ne "Builtin") {
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
    
    # 收集所有资源文件
    $AllResourceFiles = [System.Collections.Generic.List[ResourceFileInfo]]::new()
    
    foreach ($Mapping in $ResourceMappings) {
        if ($Mapping -isnot [hashtable] -or $Mapping.Count -eq 0) {
            $Script:BuildLogger.Warn("跳过无效的资源映射条目")
            continue
        }
        
        foreach ($SourceRel in $Mapping.Keys) {
            $DestPrefix = $Mapping[$SourceRel]
            
            # 解析源路径（相对于工作目录）
            $SourcePath = if ([System.IO.Path]::IsPathRooted($SourceRel)) {
                $SourceRel
            } else {
                Join-Path $Script:WorkFolder $SourceRel
            }
            
            # 清理目标前缀
            $DestPrefix = $DestPrefix -replace '^\.\\|^\./|\\$|/$', ''
            $DestPrefix = $DestPrefix -replace '\\', '/'
            
            $Script:BuildLogger.Info("资源映射: $SourceRel -> $DestPrefix/")
            
            if (-not (Test-Path $SourcePath -PathType Container)) {
                $Script:BuildLogger.Warn("资源源目录不存在: $SourcePath，跳过")
                continue
            }
            
            # 查找源目录下所有文件
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

    $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
    return if ($Module) { @($Module) } else { @() }
}

# ---- PreDefineds 构建器 ----
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

    # 配置格式: { "Default": true, "Defineds": [ {key: value}, ... ] }
    $IncludeDefault = if ($Config.ContainsKey("Default")) { $Config["Default"] } else { $false }
    $DefinedsList = if ($Config.ContainsKey("Defineds") -and $Config["Defineds"] -is [array]) {
        $Config["Defineds"]
    } else { @() }
    
    # 注入默认系统变量
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
    
    # 处理自定义变量列表
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

# ---- Nuget 构建器 ----
$Script:ModuleBuilders["Nuget"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    # 避免重复加载 nuget 模块（其中包含 infinity_log.ps1 的类型定义）
    if (-not (Get-Command "New-NugetSource" -ErrorAction SilentlyContinue)) {
        . (Join-Path -Path $PSScriptRoot 'infinity_nuget.ps1')
    }
    
    $Script:NugetLogger.Info("配置: $($Config | ConvertTo-Json -Depth 3)")

    # 解析包库路径（相对路径基于工作目录）
    $PackagesPath = $Config["PackagesPath"]
    if (-not [System.IO.Path]::IsPathRooted($PackagesPath)) {
        $PackagesPath = Join-Path $Script:WorkFolder $PackagesPath
    }

    # 创建包库（如果不存在）
    if (-not (Test-Path -Path $PackagesPath -PathType Container)) {
        $null = New-Item -Path $PackagesPath -ItemType Directory
        $LibraryPath = New-NugetPackageLibraryManifest -Path $PackagesPath
    }
    else {
        $LibraryPath = (Get-Item -Path $PackagesPath).FullName
    }

    $Source = New-NugetSource -Url $Config['Sources'][0]

    foreach($Id in $Config['Packs']){
        $null = Update-NugetPackage -Source $Source -Id $Id -LibraryPath $LibraryPath
    }

    return @([InfinityModule]@{
        Name         = 'Builtin.Nuget'
        Code         = [System.Collections.Generic.List[string]]::new()
        Requires     = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}

# ---- PreDefineds 辅助函数 ----
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
#endregion

#region 主构建流程
$Script:BuildLogger.Info("=== Infinity Build 开始 ===")

# 从顶层键解析构建步骤（排除 System 元信息键）
$BuildSteps = @{}
$MetaKeys = @("System")
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

# 合并 ExtraConfig 到构建步骤（如果调用者提供了额外配置）
if ($ExtraConfig) {
    $Script:BuildLogger.Info("应用额外配置: $($ExtraConfig.Keys -join ', ')")
    foreach ($Key in $ExtraConfig.Keys) {
        $BuildSteps[$Key] = $ExtraConfig[$Key]
    }
}

# 收集所有模块
$AllModules = [System.Collections.Generic.List[InfinityModule]]::new()

# 定义构建步骤的处理顺序（Source 最先，因为用户模块可能被内置模块依赖）
$StepOrder = @("Source", "Nuget", "PreDefineds", "Resource")

foreach ($StepName in $StepOrder) {
    if (-not $BuildSteps.ContainsKey($StepName)) {
        continue
    }
    
    # 查表：跳过未注册的构建器
    if (-not $Script:ModuleBuilders.ContainsKey($StepName)) {
        $Script:BuildLogger.Warn("未注册的构建步骤: $StepName，已跳过")
        continue
    }
    
    $StepConfig = $BuildSteps[$StepName]
    
    # Nuget 特殊处理：Packs 为空时跳过（避免空包列表触发不必要的网络请求）
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
        # 统一查表调用
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

# 生成程序段
$ProgramSegment = New-InfinityProgramSegment -Modules $AllModules.ToArray()

# 确定输出路径（优先使用 Output 配置，其次使用 System.Name）
$OutputPath = if ($Script:BuildConfig.ContainsKey("Output")) {
    $Script:BuildConfig["Output"]
}
elseif ($Script:BuildName) {
    "$($Script:BuildName).ps1"
}
else {
    "output.ps1"
}

# 相对路径转绝对路径
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $Script:WorkFolder $OutputPath
}

# 确保输出目录存在
$OutputDir = Split-Path $OutputPath -Parent
if ($OutputDir -and -not (Test-Path $OutputDir)) {
    $null = New-Item -Path $OutputDir -ItemType Directory -Force
    $Script:BuildLogger.Info("创建输出目录: $OutputDir")
}

# 写入输出脚本
$Script:BuildLogger.Info("写入输出脚本: $OutputPath")
$ProgramSegment.Code | Set-Content -Path $OutputPath -Encoding UTF8

# 生成并写入调试映射文件（供 infinity_dbg.ps1 使用）
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
$DebugInfoList | ConvertTo-Json -Depth 2 | Set-Content -Path $DebugInfoPath -Encoding UTF8 -NoNewLine

$OutputSize = (Get-Item $OutputPath).Length
$Script:BuildLogger.Info("=== Infinity Build 完成 ===")
$Script:BuildLogger.Info("输出文件: $OutputPath ($([math]::Round($OutputSize / 1KB, 2)) KB)")
$Script:BuildLogger.Info("调试文件: $DebugInfoPath")
#endregion
