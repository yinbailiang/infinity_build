##Module Builder.Nuget
##Import Builder.Register

#region Nuget 构建器

$Script:ModuleBuilders["Nuget"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    # 避免重复加载 nuget 模块（其中包含 infinity_log.ps1 的类型定义）
    if (-not (Get-Command "New-NugetSource" -ErrorAction SilentlyContinue)) {
        . (Join-Path -Path $PSScriptRoot 'infinity_nuget.ps1')
    }
    
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
        if ($Ver -eq "Latest"){
            $null = Update-NugetPackage -Source $Source -Id $Id -LibraryPath $LibraryPath
        }
        else{
            $null = Install-NugetPackage -Source $Source -Id $Id -Version $Ver -LibraryPath $LibraryPath
        }
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
