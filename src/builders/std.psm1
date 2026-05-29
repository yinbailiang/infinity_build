##Module Builder.Std
##Import Core.Logger
##Import Builder.Register
##Import Core.Parser

#region Std 构建器

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

#endregion
