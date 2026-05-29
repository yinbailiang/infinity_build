##Module Core.Parser
##Import Core.Logger
##Import Core.Types

#region 模块解析

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

#endregion
