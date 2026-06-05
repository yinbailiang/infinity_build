##Module Builder.Nuget
##Import Std.Nuget
##Import Builder.Register

<#
.NOTES
    Nuget 构建器。
    管理 NuGet 包依赖，连接 NuGet 源下载包到本地包库。
    生成 Builtin.Nuget 标记模块。
#>

#region Nuget 构建器

$Script:ModuleBuilders["Nuget"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $Script:NugetLogger.Info("配置: $($Config | ConvertTo-Json -Depth 3)")

    # 解析包库路径（相对路径基于工作目录）
    $PackagesPath = $Config["PackagesPath"]
    if (-not [System.IO.Path]::IsPathRooted($PackagesPath)) {
        $PackagesPath = Join-Path (Get-Location) $PackagesPath
    }

    # 创建包库（如果不存在）
    if (-not (Test-Path -Path $PackagesPath -PathType Container)) {
        $null = New-Item -Path $PackagesPath -ItemType Directory
        $LibraryPath = New-NugetPackageLibraryManifest -Path $PackagesPath
    }
    else {
        $LibraryPath = (Get-Item -Path $PackagesPath).FullName
    }

    $Source = New-NugetSource -Url $Config['Sources'][0]

    foreach($Pack in $Config['Packs']){
        $Id = $Pack.Keys[0]
        $Ver = $Pack[$Pack.Keys[0]]
        $null = Install-NugetPackage -Source $Source -Id $Id -Version $Ver -LibraryPath $LibraryPath
    }

    return @([InfinityModule]@{
        Name         = 'Builtin.Nuget'
        Code         = [System.Collections.Generic.List[string]]::new()
        Requires     = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}

#endregion
