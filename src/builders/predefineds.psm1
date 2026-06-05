##Module Builder.PreDefineds
##Import Core.Logger
##Import Builder.Register
##Import Core.Types
##Import Core.PreDefineds

<#
.NOTES
    PreDefineds 构建器。
    生成 Builtin.PreDefineds 模块，将编译期常量注入输出脚本。
    支持 Default 系统变量（$BuildName/$BuildVersion/$BuildMode）和自定义 Defineds。
#>

#region PreDefineds 构建器

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

#endregion
