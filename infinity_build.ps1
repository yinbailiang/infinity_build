<#
.NOTES
    Name: infinity_build
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    PowerShell 工具用于管理和打包 PowerShell 项目
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
    [switch]$Clean
)
#endregion

#region 日志初始化
. (Join-Path -Path $PSScriptRoot -ChildPath 'infinity_log.ps1')
$Script:BuildLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityBuild")
$Script:BuildLogger = [LogClient]::new($Script:BuildLoggerServer)
#endregion

#region 初始化
$PSVersion = $PSVersionTable.PSVersion
if ($PSVersion.Major -lt 7) {
    $Script:BuildLogger.Error("需要 PowerShell 7.0 或更高版本，当前版本: $PSVersion")
    throw "需要 PowerShell 7.0+"
}
$Script:BuildLogger.Info("PowerShell 版本: $PSVersion")

$WorkFolder = Get-Location
$CacheFolder = Join-Path $WorkFolder ".infinity_build"
$Script:BuildLogger.Info("工作目录: $WorkFolder")
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
        [string]$Path = $WorkFolder
    )
    
    $Script:BuildLogger.Debug("查找文件: 路径=$Path, 过滤器=$($Filters -join ', ')")
    $FoundFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($Filter in $Filters) {
        $Files = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue
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
            if($Lines[$i].Trim().StartsWith('#>')){
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

function Find-ResourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $FileList = [System.Collections.Generic.List[ResourceFileInfo]]::new()
    
    # 检查Path是否存在
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $Script:BuildLogger.Warn("资源目录不存在: $Path")
        return $FileList.ToArray()
    }
    
    $Script:BuildLogger.Info("查找资源文件: $Path")
    # 查找所有Path下的子文件
    $Files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue

    foreach ($File in $Files) {
        try {
            $RelativePath = Resolve-Path -Path $File -Relative -RelativeBasePath $Path
            $FileInfo = [ResourceFileInfo]@{
                FileInfo     = $File
                RelativePath = $RelativePath
            }
            $FileList.Add($FileInfo)
        }
        catch {
            $Script:BuildLogger.Warn("处理文件失败 '$($File.FullName)': $($_.Exception.Message)")
        }
    }
    
    $Script:BuildLogger.Info("找到 $($FileList.Count) 个资源文件")
    return $FileList.ToArray()
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
        $ModuleCodeSize = [math]::Round(($ResourceEmbedModule.Code.Length | Measure-Object -Sum).Sum / 1KB, 2)
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
function Build-InfinityModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceConfig
    )
    $SourceFiles = Find-Files -Filters $SourceConfig.Files
    $Script:BuildLogger.Info("找到 $($SourceFiles.Count) 个源文件")
    if ($SourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到任何源文件")
        return @()
    }
    $Modules = $SourceFiles | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return Get-InfinityModuleOrdered -Modules $Modules
}

function Build-ResourceEmbedModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResourceConfig,
        
        [Parameter()]
        [switch]$Clean
    )
    $ResourceZipPath = Join-Path $CacheFolder "resource.zip"
    $ResourceSnapshotPath = Join-Path $CacheFolder "resource_snapshot.json"
    $ResourcePath = $ResourceConfig.RootDir

    $ResourceFiles = Find-ResourceFiles -Path $ResourcePath
    $Script:BuildLogger.Info("找到 $($ResourceFiles.Count) 个资源文件")

    if($ResourceFiles.Count -eq 0) {
        $Script:BuildLogger.Error("没有找到任何资源文件，无法构建资源模块")
        throw "没有找到任何资源文件，无法构建资源模块"
    }

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

    return Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
}

function Build-PreDefinedsModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $Script:BuildLogger.Info("生成预定义变量模块，包含 $($Config.Count) 个变量")
    
    $PreDefinedsModule = [InfinityModule]@{
        Name         = 'Builtin.PreDefineds'
        Requires     = [System.Collections.Generic.List[string]]::new()
        Code         = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    }

    foreach ($Name in $Config.Keys) {
        if ($Config[$Name] -is [string]) {
            $PreDefinedsModule.Code.Add("`$$Name = '$($Config[$Name].Replace("'","''"))'")
        }
        elseif ($Config[$Name] -is [int]) {
            $PreDefinedsModule.Code.Add("`$$Name = $($Config[$Name].ToString())")
        }
        elseif ($Config[$Name] -is [bool]) {
            if ($Config[$Name]) {
                $PreDefinedsModule.Code.Add("`$$Name = `$true")
            }
            else {
                $PreDefinedsModule.Code.Add("`$$Name = `$false")
            }
        }
        else {
            $Script:BuildLogger.Error("不支持的预定义变量类型: $Name -> $($Config[$Name].GetType())")
            throw "不支持的预定义变量类型: $Name -> $($Config[$Name].GetType())"
        }
    }
    
    $Script:BuildLogger.Info("预定义变量模块生成完成: $($PreDefinedsModule.Code.Count) 个变量")
    return $PreDefinedsModule
}
#endregion

#region 构建流程
try {
    # 读取构建配置
    if (-not (Test-Path -Path $ConfigPath)) {
        $Script:BuildLogger.Error("构建配置文件不存在: $ConfigPath")
        throw "构建配置文件不存在: $ConfigPath"
    }
    
    try {
        $Script:BuildLogger.Info("读取构建配置: $ConfigPath")
        $BuildConfig = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $Script:BuildLogger.Info("构建配置读取成功")
    }
    catch {
        $Script:BuildLogger.Error("加载构建配置失败: $($_.Exception.Message)")
        throw
    }

    if ($Clean) {
        $Script:BuildLogger.Info("正在清理缓存: $CacheFolder")
        $Items = Get-ChildItem -Path $CacheFolder -Recurse
        $Items | Remove-Item -Force
        $Script:BuildLogger.Info("清理缓存项: $($Items.Count) 个")
    }

    $OrderedModules = [System.Collections.Generic.List[InfinityModule]](Build-InfinityModules -SourceConfig $BuildConfig.Source)
    
    if ($BuildConfig.Resource) {
        $Script:BuildLogger.Info("构建资源嵌入模块")
        $OrderedModules.Insert(0, (Build-ResourceEmbedModule -ResourceConfig $BuildConfig.Resource))
    }
    
    if ($BuildConfig.PreDefineds) {
        $Script:BuildLogger.Info("构建预定义变量模块")
        $OrderedModules.Insert(0, (Build-PreDefinedsModule -Config $BuildConfig.PreDefineds))
    }
    
    $Script:BuildLogger.Info("添加主启动模块")
    $OrderedModules.Add([InfinityModule]@{
        Name = "Builtin.MainStart"
        Requires = [System.Collections.Generic.List[string]]::new()
        Code = [System.Collections.Generic.List[string]]@(
            'Invoke-Main $args'
        )
        SourceInfo = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })

    $ProgramSegment = New-InfinityProgramSegment -Modules $OrderedModules

    $ProgramName = if ($BuildConfig.Name) {
        $BuildConfig.Name
    }
    else {
        $Script:BuildLogger.Warn('未找到配置的名称，使用默认值: infinity_program')
        "infinity_program"
    }

    $OutputPath = Join-Path $WorkFolder "$($ProgramName).ps1"

    $SegmentCodeSize = $([math]::Round(($ProgramSegment.Code.Length | Measure-Object -Sum).Sum / 1KB, 2))
    $Script:BuildLogger.Info("生成程序文件 (文件大小: $SegmentCodeSize KB)")
    $ProgramSegment.Code -join [System.Environment]::NewLine | Set-Content -Path $OutputPath -Encoding UTF8 -NoNewLine
    $Script:BuildLogger.Info("程序文件已保存到: $OutputPath")

    if ($BuildConfig.Mode.DevMode -eq "Debug") {
        # 生成调试信息文件
        $DebugInfoPath = Join-Path $WorkFolder "$($ProgramName).debug.json"
        $DebugInfo = @()
        foreach ($LineNum in $ProgramSegment.LineMappings.Keys) {
            $SourceTuple = $ProgramSegment.LineMappings[$LineNum]
            $DebugInfo += @{
                OutputLine    = $LineNum
                SourceFile    = $SourceTuple.Item1
                SourceLineNum = $SourceTuple.Item2
            }
        }
        $DebugData = $DebugInfo | ConvertTo-Json -Depth 3 -Compress
        $Script:BuildLogger.Info("生成调试信息文件 (文件大小: $([math]::Round($DebugData.Length / 1KB, 2)) KB)")
        Set-Content -Path $DebugInfoPath -Value $DebugData -Encoding UTF8 -NoNewLine
        $Script:BuildLogger.Info("调试信息已保存到: $DebugInfoPath")
    }
    
    $Script:BuildLogger.Info("构建完成！")
}
catch {
    $Script:BuildLogger.Error("构建失败: $($_.Exception.Message)")
    throw
}
#endregion