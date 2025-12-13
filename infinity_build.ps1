#region 参数
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$Clean
)

#region 日志函数
function Write-BuildLog {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[Build] $Message" -ForegroundColor Cyan
}
function Write-BuildWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[Build] WARNING: $Message" -ForegroundColor Yellow
}
function Write-BuildError {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[Build] ERROR: $Message" -ForegroundColor Red
}
#endregion

#region 初始化
$PSVersion = $PSVersionTable.PSVersion
if ($PSVersion.Major -lt 7) {
    Write-BuildError -Message "需要 PowerShell 7.0 或更高版本，当前版本: $PSVersion"
    throw "需要 PowerShell 7.0+"
}
Write-BuildLog -Message "PowerShell 版本: $PSVersion"

$WorkFolder = Get-Location
$CacheFolder = Join-Path $WorkFolder ".buildcache"
Write-BuildLog -Message "工作目录: $WorkFolder"
Write-BuildLog -Message "缓存目录: $CacheFolder"

# 确保缓存目录存在
if (-not (Test-Path -Path $CacheFolder -PathType Container)) {
    if (-not (New-Item -Path $CacheFolder -ItemType Directory -Force)) {
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
    
    $FoundFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($Filter in $Filters) {
        $Files = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            $FoundFiles.Add($File.FullName)
        }
    }
    
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
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-BuildLog -Message "读取模块: $Path"
    
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "模块文件不存在: $Path"
    }

    try {
        $FileContent = Get-Content -Path $Path -ReadCount 0 -Raw
    }
    catch {
        throw "读取模块文件失败 '$Path': $($_.Exception.Message)"
    }

    $SourceInfo = Get-Item -Path $Path
    $InfinityModule = [InfinityModule]@{
        Name         = $SourceInfo.BaseName
        Requires     = @()
        Code         = @()
        SourceInfo   = $SourceInfo
        LineMappings = @{}
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
                    }
                    'Import' {
                        $InfinityModule.Requires.Add($DirectiveParts[1].Trim())
                    }
                    Default {
                        Write-BuildWarning -Message "未知的预处理指令: $($Lines[$i])"
                        Write-BuildWarning -Message "来自: $($Path): line $($i+1)"
                    }
                }
            }
            continue
        }
        $InfinityModule.Code.Add($Lines[$i].TrimEnd())
        $InfinityModule.LineMappings[$InfinityModule.Code.Count] = $i + 1
    }

    return $InfinityModule
}
function Get-InfinityModuleOrdered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )

    # 创建模块名称到模块对象的映射
    $ModuleMap = [System.Collections.Generic.Dictionary[string, InfinityModule]]@{}
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    # 计算每个模块的入度（依赖数）
    $InDegree = [System.Collections.Generic.Dictionary[string, int]]@{}
    $AdjacencyList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]@{}
    foreach ($Module in $Modules) {
        $InDegree[$Module.Name] = 0
        $AdjacencyList[$Module.Name] = @()
    }
    # 构建邻接表和计算入度
    foreach ($Module in $Modules) {
        foreach ($RequiredModuleName in $Module.Requires) {
            if (-not $ModuleMap.ContainsKey($RequiredModuleName)) {
                Write-BuildWarning -Message "模块 '$($Module.Name)' 依赖的模块 '$RequiredModuleName' 不在提供的模块列表中"
                continue
            }
            $AdjacencyList[$RequiredModuleName].Add($Module.Name)
            $InDegree[$Module.Name] += 1
        }
    }
    #拓扑排序
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
        throw "检测到循环依赖！受影响的模块: $($RemainingModules -join ', ')"
    }

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
    
    $ProgramSegment = [InfinityProgramSegment]@{
        Code         = @()
        LineMappings = @{}
    }

    foreach ($Module in $Modules) {
        Write-BuildLog -Message "添加 $($Module.Name)"
        $ModuleLineNum = 0
        foreach ($Line in $Module.Code) {
            $ModuleLineNum++
            $ProgramSegment.Code.Add($Line)
            if ($Module.LineMappings.ContainsKey($ModuleLineNum)) {
                $ProgramSegment.LineMappings[$ProgramSegment.Code.Count] = [System.Tuple[string, int]]::new($Module.SourceInfo, $Module.LineMappings[$ModuleLineNum])
            }
        }
    }

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
        Write-BuildWarning -Message "资源目录不存在: $Path"
        return $FileList.ToArray()
    }
    
    # 找查所有Path下的子文件
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
            Write-BuildWarning -Message "处理文件失败 '$($File.FullName)': $($_.Exception.Message)"
        }
    }
    
    return $FileList.ToArray()
}
function Get-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileInfo[]]$ResourceFiles
    )
    
    $HashList = [System.Collections.Generic.List[ResourceFileHash]]::new()
    
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
                Write-BuildWarning -Message "文件不存在，跳过: $($ResourceFile.FileInfo)"
            }
        }
        catch {
            Write-BuildWarning -Message "计算文件哈希失败 '$($ResourceFile.FileInfo)': $($_.Exception.Message)"
        }
    }
    
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
    
    if ($NewSnapshot.Count -ne $OldSnapshot.Count) {
        Write-BuildLog -Message "快照文件数量不同: 新 $($NewSnapshot.Count) vs 旧 $($OldSnapshot.Count)"
    }

    #把老快照转换为 RelativePath -> Hash 的 Map 方便后续计算
    $OldFileHashTable = @{}
    foreach ($Item in $OldSnapshot) {
        $OldFileHashTable[$Item.RelativePath] = $Item.Hash256
    }
    
    $IsSame = $true
    foreach ($Item in $NewSnapshot) {
        $Path = $Item.RelativePath
        # 检查该文件是否为新增
        if (-not $OldFileHashTable.ContainsKey($Path)) {
            Write-BuildLog -Message "新增文件: $Path"
            $IsSame = $false
            # 新增文件在老快照中没有对应 Hash 直接跳过
            continue
        }
        # 检查哈希
        if ($OldFileHashTable[$Path] -ne $Item.Hash256) {
            Write-BuildLog -Message "文件哈希变化: $Path"
            $IsSame = $false
        }
        # 从老快照的 Map 中删除
        [void]$OldFileHashTable.Remove($Path)
    }

    # 如果老快照中还有剩余的项目，说明新快照中删除了部分文件
    foreach ($Path in $OldFileHashTable.Keys) {
        Write-BuildLog -Message "文件被删除：$Path"
        $IsSame = $false
    }

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
        
        Write-BuildLog -Message "资源快照已保存到: $Path"
    }
    catch {
        Write-BuildError -Message "保存资源快照失败: $($_.Exception.Message)"
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
            throw "未找到资源快照: $Path"
        }
        
        $SnapshotData = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        
        $Snapshot = @()
        foreach ($Item in $SnapshotData) {
            $Snapshot += [ResourceFileHash]@{
                RelativePath = $Item.RelativePath
                Hash256      = $Item.Hash256
            }
        }
        
        Write-BuildLog -Message "已从 $Path 读取 $($Snapshot.Count) 个文件快照"
        return $Snapshot
    }
    catch {
        Write-BuildWarning -Message "无法读取资源快照: $($_.Exception.Message)"
        throw
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
        $ZipFileStream = if ($Force -or -not (Test-Path $DestinationPath)) {
            [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create)
        }
        else {
            throw "目标位置被占用: $($DestinationPath)"
        }

        $ZipArchive = [System.IO.Compression.ZipArchive]::new($ZipFileStream, [System.IO.Compression.ZipArchiveMode]::Create)
        
        $FileCount = 0
        foreach ($ResourceFile in $ResourceFiles) {
            if (-not (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf)) {
                Write-BuildWarning -Message "找不到文件：$($ResourceFile.FileInfo)"
                Write-BuildWarning -Message "已自动跳过"
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
                    Write-BuildLog -Message "  已压缩 $FileCount 个文件..."
                }
            }
            catch {
                Write-BuildWarning -Message "压缩文件失败 '$($FileInfo.FullPath)': $($_.Exception.Message)"
                throw
            }
        }
        
        $ZipArchive.Dispose()
        $ZipFileStream.Close()
        
        Write-BuildLog -Message "资源压缩完成，共 $FileCount 个文件"
        
        if (Test-Path -Path $DestinationPath -PathType Leaf) {
            $ZipInfo = Get-Item -Path $DestinationPath
            Write-BuildLog -Message "ZIP文件大小: $([math]::Round($ZipInfo.Length / 1KB, 2)) KB"
        }
    }
    catch {
        Write-BuildError -Message "无法压缩资源文件：$($_.Exception.Message)"
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
        Write-BuildError -Message "ZIP文件不存在: $ZipFilePath"
        return $null
    }
    
    try {
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
            Requires     = @()
            SourceInfo   = Get-Item -Path $PSCommandPath
            LineMappings = @{}
        }
        $ModuleCodeSize = [math]::Round(($ResourceEmbedModule.Code.Length | Measure-Object -Sum).Sum / 1KB, 2)
        Write-BuildLog -Message "生成资源嵌入模块 (模块大小: $ModuleCodeSize KB)"
        return $ResourceEmbedModule
    }
    catch {
        Write-BuildError -Message "生成资源嵌入模块失败: $($_.Exception.Message)"
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
    Write-BuildLog -Message "找到 $($SourceFiles.Count) 个源文件"
    if ($SourceFiles.Count -eq 0) {
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
    Write-BuildLog -Message "找到 $($ResourceFiles.Count) 个资源文件"

    $CurrentSnapshot = Get-ResourceSnapshot -ResourceFiles $ResourceFiles
    $PreviousSnapshot = if (Test-Path -Path $ResourceSnapshotPath -PathType Leaf) {
        Read-ResourceSnapshot -Path $ResourceSnapshotPath
    }
    else {
        Write-BuildLog -Message "未找到先前的资源快照文件: $ResourceSnapshotPath"
        $null
    }

    $IsChanged = if ($PreviousSnapshot) {
        -not (Compare-ResourceSnapshot -NewSnapshot $CurrentSnapshot -OldSnapshot $PreviousSnapshot)
    }
    else {
        $true
    }
        
    if ($IsChanged) {
        Write-BuildLog -Message "开始压缩资源..."
        Compress-ResourceFiles -ResourceFiles $ResourceFiles -DestinationPath $ResourceZipPath -Force
        Write-ResourceSnapshot -Snapshot $CurrentSnapshot -Path $ResourceSnapshotPath
    }
    else {
        Write-BuildLog -Message "使用缓存的资源压缩包"
    }

    return Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
}
function Build-PreDefinedsModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $PreDefinedsModule = [InfinityModule]@{
        Name         = 'Builtin.PreDefineds'
        Requires     = @()
        Code         = @()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = @{}
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
            throw "不支持的预定义变量类型: $Name -> $($Config[$Name].GetType())"
        }
    }
    
    return $PreDefinedsModule
}
#endregion

#region 构建流程
try {
    # 读取构建配置
    if (-not (Test-Path -Path $ConfigPath)) {
        throw "构建配置文件不存在: $ConfigPath"
    }
    try {
        $BuildConfig = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        Write-BuildError -Message "加载构建配置失败: $($_.Exception.Message)"
        throw
    }

    if ($Clean) {
        Write-BuildLog -Message "正在清理缓存: $CacheFolder"
        $Items = Get-ChildItem -Path $CacheFolder -Recurse
        $Items | Remove-Item -Force
        Write-BuildLog -Message "清理缓存项: $($Items.Count) 个"
    }

    $OrderedModules = [System.Collections.Generic.List[InfinityModule]](Build-InfinityModules -SourceConfig $BuildConfig.Source)
    
    if ($BuildConfig.Resource) {
        $OrderedModules.Insert(0, (Build-ResourceEmbedModule -ResourceConfig $BuildConfig.Resource))
    }
    if ($BuildConfig.PreDefineds) {
        $OrderedModules.Insert(0, (Build-PreDefinedsModule -Config $BuildConfig.PreDefineds))
    }
    $OrderedModules.Add([InfinityModule]@{
        Name = "Builtin.MainStart"
        Requires = @()
        Code = @(
            'Invoke-Main $args'
        )
        SourceInfo = Get-Item -Path $PSCommandPath
        LineMappings = @{}
    })

    $ProgramSegment = New-InfinityProgramSegment -Modules $OrderedModules

    $ProgramName = if ($BuildConfig.Name) {
        $BuildConfig.Name
    }
    else {
        Write-BuildLog -Message '未找到配置的名称，使用默认值: infinity_program'
        "infinity_program"
    }

    $OutputPath = Join-Path $WorkFolder "$($ProgramName).ps1"

    $SegmentCodeSize = $([math]::Round(($ProgramSegment.Code.Length | Measure-Object -Sum).Sum / 1KB, 2))
    Write-BuildLog -Message "生成程序文件 (文件大小: $SegmentCodeSize KB)"
    $ProgramSegment.Code -join [System.Environment]::NewLine | Set-Content -Path $OutputPath -Encoding UTF8 -NoNewLine
    Write-BuildLog -Message "程序文件已保存到: $OutputPath"

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
        Write-BuildLog -Message "生成调试信息文件 (文件大小: $([math]::Round($DebugData.Length / 1KB, 2)) KB)"
        Set-Content -Path $DebugInfoPath -Value $DebugData -Encoding UTF8 -NoNewLine
        Write-BuildLog -Message "调试信息已保存到: $DebugInfoPath"
    }
    Write-BuildLog -Message "构建完成！"
}
catch {
    Write-BuildError -Message "构建失败: $($_.Exception.Message)"
    throw
}
#endregion