##Module Core.Resource
##Import Core.Types

#region 资源快照

<#
.SYNOPSIS
    计算资源文件集合的 SHA256 快照。
.DESCRIPTION
    遍历所有 ResourceFileInfo，对每个存在的文件计算 SHA256 哈希值，
    返回 ResourceFileHash 数组用于后续的变更检测。
    文件不存在或计算失败时发出警告并跳过。
#>
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

<#
.SYNOPSIS
    比较新旧两份资源快照，检测文件变更。
.DESCRIPTION
    对比新快照与旧快照中的文件列表和哈希值：
    - 新增文件、删除文件、哈希变化均视为变更
    - 完全相同返回 $true，有差异返回 $false
#>
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

<#
.SYNOPSIS
    将资源快照持久化保存为 JSON 文件。
.DESCRIPTION
    将 ResourceFileHash 数组序列化为 JSON 格式并写入指定路径，
    用于下次构建时的增量对比。
#>
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

<#
.SYNOPSIS
    从 JSON 文件读取之前保存的资源快照。
.DESCRIPTION
    反序列化指定路径的 JSON 快照文件为 ResourceFileHash 数组。
    文件不存在或读取失败时返回 $null。
#>
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

#endregion

#region 资源压缩

<#
.SYNOPSIS
    将资源文件集合压缩为 ZIP 包。
.DESCRIPTION
    遍历所有 ResourceFileInfo，使用 System.IO.Compression.ZipArchive
    创建 ZIP 文件，保留目标相对路径结构。支持指定压缩级别。
#>
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

#endregion

#region 资源嵌入模块

<#
.SYNOPSIS
    根据 ZIP 文件生成资源嵌入模块（Builtin.Resource）。
.DESCRIPTION
    Builtin 模式：将 ZIP 文件 Base64 编码后嵌入为 $BuiltinResourceZipContent 变量。
    External 模式：仅记录 ZIP 文件名和 SHA256 哈希，运行时从外部路径加载。
#>
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
            # 外部模式：仅存储哈希和 ZIP 文件名，由 Std.Resource 运行时按路径查找
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
            # 内置模式：Base64 嵌入完整 ZIP 内容
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

#endregion
