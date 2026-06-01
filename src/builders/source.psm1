##Module Builder.Source
##Import Core.Logger
##Import Builder.Register
##Import Core.Finder
##Import Core.Parser

#region Source 构建器

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
    $Modules = $SourceFiles | Select-Object -Unique | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}

#endregion
