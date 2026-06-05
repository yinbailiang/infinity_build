##Module Builder.Std
##Import Core.Logger
##Import Builder.Register
##Import Core.Parser
##Import Core.Finder

<#
.NOTES
    Std 标准库构建器。
    读取 std/std.json 配置，收集并解析标准库源文件。
    支持 Enable 开关和自定义包含模式。
#>

#region Std 构建器

$Script:ModuleBuilders["Std"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    if ($Config.ContainsKey("Enable")) {
        if (-not $Config.Enable) {
            return @()
        }
    }

    $AllSourceFiles = [System.Collections.Generic.List[string]]::new()

    $StdLibPath = Join-Path $PSScriptRoot "std"
    if (Test-Path $StdLibPath -PathType Container) {
        # 读取 std.json 获取包含模式
        $StdJsonPath = Join-Path $StdLibPath "std.json"
        $IncludePatterns = @()
        if (Test-Path $StdJsonPath -PathType Leaf) {
            try {
                $StdJsonConfig = Get-Content $StdJsonPath -Raw | ConvertFrom-Json -AsHashtable
                if ($StdJsonConfig.ContainsKey("Std") -and $StdJsonConfig["Std"] -is [array]) {
                    $IncludePatterns = $StdJsonConfig["Std"]
                    $Script:BuildLogger.Info("从 std.json 读取包含模式: $($IncludePatterns -join ', ')")
                }
            }
            catch {
                $Script:BuildLogger.Warn("读取 std.json 失败: $($_.Exception.Message)，使用默认模式 *.psm1")
            }
        }
        if ($IncludePatterns.Count -eq 0) {
            $Script:BuildLogger.Info("std.json 未配置或不存在，使用默认模式 *.psm1")
            $IncludePatterns = @("*.psm1")
        }

        $BuiltinFiles = Find-Files -Filters $IncludePatterns -Path $StdLibPath
        foreach ($f in $BuiltinFiles) {
            $AllSourceFiles.Add($f)
        }
        $Script:BuildLogger.Info("内置 Std: 找到 $($BuiltinFiles.Count) 个源文件")
    }
    else {
        $Script:BuildLogger.Warn("标准库目录不存在: $StdLibPath")
    }

    $Script:BuildLogger.Info("Std 总共收集 $($AllSourceFiles.Count) 个源文件")
    if ($AllSourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到任何标准库源文件")
        return @()
    }

    $UniqueFiles = $AllSourceFiles | Select-Object -Unique

    $Modules = $UniqueFiles | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}

#endregion
