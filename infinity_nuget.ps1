<#
.NOTES
    Name: infinity_nuget
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    PowerShell 工具用于下载和管理 NuGet 包
.DESCRIPTION
    这个工具提供以下功能：
    1. 搜索 NuGet 包
    2. 下载和安装 NuGet 包
    3. 管理本地包缓存
    4. 更新已安装的包
    5. 管理包源
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot "configs" "infinity_nuget_config.json")
)

$Script:Config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

# 初始化
function Initialize-NuGetManager {
    <#
    .SYNOPSIS
        初始化 NuGet 管理器
    .DESCRIPTION
        确保所需的目录和文件存在
    #>

    

    Write-Host "NuGet 管理器初始化完成！" -ForegroundColor Green
}

Initialize-NuGetManager

# 导出函数
<#Export-ModuleMember -Function @(
    'Initialize-NuGetManager',
    'Search-NuGetPackage',
    'Install-NuGetPackage',
    'Get-InstalledPackages',
    'Update-NuGetPackage',
    'Remove-NuGetPackage',
    'Clear-NuGetCache',
    'Manage-NuGetSources',
    'Show-NuGetHelp',
    'Show-NuGetMenu'
)
param(
    [string]$Command,
    [string]$PackageId,
    [string]$Name,
    [string]$Version
)
switch ($Command) {
    "search" { Search-NuGetPackage -Name $Name }
    "install" { Install-NuGetPackage -PackageId $PackageId -Version $Version }
    "list" { Get-InstalledPackages }
    "update" { Update-NuGetPackage -PackageId $PackageId }
    "remove" { Remove-NuGetPackage -PackageId $PackageId }
    default { Show-NuGetMenu }
}#>