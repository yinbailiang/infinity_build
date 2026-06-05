##Module Builder.Resource
##Import Core.Logger
##Import Builder.Register
##Import Core.Types
##Import Core.Resource

<#
.NOTES
    Resource 构建器。
    将外部资源文件打包嵌入输出脚本。
    支持 Builtin（Base64 内嵌）和 External（独立 ZIP 文件）两种模式。
    通过 SHA256 快照实现增量构建，仅在资源变更时重新打包。
#>

#region Resource 构建器

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
                Join-Path (Get-Location) $SourceRel
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

    if ($ResourceType -eq "Builtin") {
        $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
        $Ret = if ($Module) { @($Module) } else { @() }
        return $Ret
    }
    elseif ($ResourceType -eq "External") {
        # 解析外部输出目录
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

        # 解析外部输出文件名（默认: <构建名>-resources.zip）
        $ExternalOutputName = if ($Config.ContainsKey("OutputName")) {
            $Config["OutputName"]
        } else {
            "$Script:BuildName-resources.zip"
        }

        # 确保 .zip 扩展名
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

#endregion
