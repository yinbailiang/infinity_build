##Module Builder.Boot
##Import Builder.Register
##Import Core.Logger
##Import Core.Types

<#
.NOTES
    Boot 构建器。
    生成 Builtin.Boot 入口模块，包含 EntryPoint 函数调用。
    Require 字段指定依赖的模块名，触发树摇优化。
#>

#region Boot 构建器

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
    
    # 读取依赖模块名（拓扑排序会确保该模块在 Boot 之前）
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

#endregion
