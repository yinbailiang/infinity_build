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

# 配置
$Script:Config = @{
    DefaultPackagesPath = "$env:USERPROFILE\.nuget\packages"
    NuGetExePath = "$env:TEMP\nuget.exe"
    DefaultSources = @(
        "https://api.nuget.org/v3/index.json"
    )
    ConfigFile = "$PSScriptRoot\nuget-config.json"
}

# 初始化
function Initialize-NuGetManager {
    <#
    .SYNOPSIS
        初始化 NuGet 管理器
    .DESCRIPTION
        确保所需的目录和文件存在
    #>
    
    # 创建必要的目录
    $paths = @(
        $Config.DefaultPackagesPath
        Split-Path $Config.ConfigFile -Parent
    )
    
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "已创建目录: $path" -ForegroundColor Green
        }
    }
    
    # 初始化配置文件
    if (-not (Test-Path $Config.ConfigFile)) {
        $defaultConfig = @{
            PackageSources = $Config.DefaultSources
            InstalledPackages = @()
            PackageCache = @{}
        }
        $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $Config.ConfigFile -Encoding UTF8
    }
    
    # 确保 NuGet.exe 存在
    if (-not (Test-Path $Config.NuGetExePath)) {
        Write-Host "正在下载 NuGet.exe..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" `
                         -OutFile $Config.NuGetExePath `
                         -UseBasicParsing
        Write-Host "NuGet.exe 已下载到: $($Config.NuGetExePath)" -ForegroundColor Green
    }
    
    Write-Host "NuGet 管理器初始化完成！" -ForegroundColor Green
}

# 加载配置
function Get-NuGetConfig {
    <#
    .SYNOPSIS
        获取当前配置
    #>
    if (Test-Path $Config.ConfigFile) {
        return Get-Content $Config.ConfigFile -Raw | ConvertFrom-Json
    }
    return $null
}

# 保存配置
function Save-NuGetConfig {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ConfigObject
    )
    
    $ConfigObject | ConvertTo-Json -Depth 10 | Set-Content -Path $Config.ConfigFile -Encoding UTF8
}

# 搜索 NuGet 包
function Search-NuGetPackage {
    <#
    .SYNOPSIS
        搜索 NuGet 包
    .PARAMETER Name
        包名称（支持通配符）
    .PARAMETER Source
        包源 URL（可选）
    .PARAMETER Take
        返回结果数量（默认20）
    .EXAMPLE
        Search-NuGetPackage -Name "Newtonsoft.Json"
        Search-NuGetPackage -Name "Microsoft.*" -Take 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [string]$Source,
        
        [int]$Take = 20
    )
    
    # 如果没有指定源，使用第一个默认源
    if ([string]::IsNullOrEmpty($Source)) {
        $config = Get-NuGetConfig
        $Source = $config.PackageSources[0]
    }
    
    Write-Host "正在搜索包: $Name" -ForegroundColor Yellow
    
    # 使用 NuGet.exe 搜索
    $searchCommand = "& `"$($Config.NuGetExePath)`" search `"$Name`" -Source `"$Source`" -Take $Take -NonInteractive"
    $result = Invoke-Expression $searchCommand
    
    if ($result) {
        Write-Host "找到以下包:" -ForegroundColor Green
        $packages = @()
        
        foreach ($line in $result) {
            if ($line -match "^(\S+)\s+(\S+)\s+(.*)$") {
                $package = [PSCustomObject]@{
                    Id = $matches[1]
                    Version = $matches[2]
                    Description = $matches[3]
                }
                $packages += $package
                Write-Host "  $($package.Id) [$($package.Version)]" -ForegroundColor Cyan
                Write-Host "    $($package.Description)" -ForegroundColor Gray
            }
        }
        
        return $packages
    }
    else {
        Write-Host "未找到匹配的包。" -ForegroundColor Red
    }
}

# 下载并安装 NuGet 包
function Install-NuGetPackage {
    <#
    .SYNOPSIS
        下载并安装 NuGet 包
    .PARAMETER PackageId
        包 ID
    .PARAMETER Version
        版本号（可选，默认最新版）
    .PARAMETER OutputDirectory
        输出目录（可选）
    .PARAMETER Source
        包源 URL（可选）
    .PARAMETER IncludeDependencies
        是否包含依赖项
    .EXAMPLE
        Install-NuGetPackage -PackageId "Newtonsoft.Json"
        Install-NuGetPackage -PackageId "Newtonsoft.Json" -Version "13.0.1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,
        
        [string]$Version,
        
        [string]$OutputDirectory,
        
        [string]$Source,
        
        [switch]$IncludeDependencies = $true
    )
    
    # 设置输出目录
    if ([string]::IsNullOrEmpty($OutputDirectory)) {
        $OutputDirectory = Join-Path $Config.DefaultPackagesPath $PackageId
    }
    
    # 构建安装命令
    $installCmd = "& `"$($Config.NuGetExePath)`" install $PackageId"
    
    if (-not [string]::IsNullOrEmpty($Version)) {
        $installCmd += " -Version $Version"
    }
    
    if (-not [string]::IsNullOrEmpty($OutputDirectory)) {
        $installCmd += " -OutputDirectory `"$OutputDirectory`""
    }
    
    if (-not [string]::IsNullOrEmpty($Source)) {
        $installCmd += " -Source `"$Source`""
    }
    
    if (-not $IncludeDependencies) {
        $installCmd += " -DependencyVersion Ignore"
    }
    
    $installCmd += " -NonInteractive"
    
    Write-Host "正在安装包: $PackageId" -ForegroundColor Yellow
    Write-Host "命令: $installCmd" -ForegroundColor Gray
    
    try {
        # 执行安装
        Invoke-Expression $installCmd
        
        # 更新配置文件
        $config = Get-NuGetConfig
        if ($config -eq $null) {
            $config = @{
                PackageSources = $Config.DefaultSources
                InstalledPackages = @()
                PackageCache = @{}
            } | ConvertTo-Json | ConvertFrom-Json
        }
        
        # 添加到已安装包列表
        $packageInfo = @{
            Id = $PackageId
            Version = $Version
            InstallDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            InstallPath = $OutputDirectory
        }
        
        $config.InstalledPackages = @($config.InstalledPackages) + $packageInfo
        Save-NuGetConfig -ConfigObject $config
        
        Write-Host "包 $PackageId 安装成功！" -ForegroundColor Green
        Write-Host "安装路径: $OutputDirectory" -ForegroundColor Cyan
        
        return $true
    }
    catch {
        Write-Host "安装失败: $_" -ForegroundColor Red
        return $false
    }
}

# 列出已安装的包
function Get-InstalledPackages {
    <#
    .SYNOPSIS
        列出所有已安装的包
    #>
    
    $config = Get-NuGetConfig
    if ($config -and $config.InstalledPackages) {
        Write-Host "已安装的包:" -ForegroundColor Green
        
        $table = @()
        foreach ($package in $config.InstalledPackages) {
            $table += [PSCustomObject]@{
                PackageId = $package.Id
                Version = if ($package.Version) { $package.Version } else { "Latest" }
                InstallDate = $package.InstallDate
                InstallPath = $package.InstallPath
            }
        }
        
        return $table | Format-Table -AutoSize
    }
    else {
        Write-Host "没有已安装的包。" -ForegroundColor Yellow
    }
}

# 更新包
function Update-NuGetPackage {
    <#
    .SYNOPSIS
        更新已安装的包
    .PARAMETER PackageId
        包 ID（可选，不指定则更新所有包）
    .PARAMETER Source
        包源 URL（可选）
    #>
    [CmdletBinding()]
    param(
        [string]$PackageId,
        
        [string]$Source
    )
    
    $config = Get-NuGetConfig
    if (-not $config -or -not $config.InstalledPackages) {
        Write-Host "没有可更新的包。" -ForegroundColor Yellow
        return
    }
    
    $packagesToUpdate = @()
    if ([string]::IsNullOrEmpty($PackageId)) {
        $packagesToUpdate = $config.InstalledPackages
    }
    else {
        $packagesToUpdate = $config.InstalledPackages | Where-Object { $_.Id -eq $PackageId }
    }
    
    foreach ($package in $packagesToUpdate) {
        Write-Host "正在更新包: $($package.Id)" -ForegroundColor Yellow
        
        $updateCmd = "& `"$($Config.NuGetExePath)`" update `"$($package.InstallPath)\$($package.Id)`""
        
        if (-not [string]::IsNullOrEmpty($Source)) {
            $updateCmd += " -Source `"$Source`""
        }
        
        $updateCmd += " -NonInteractive"
        
        try {
            Invoke-Expression $updateCmd
            
            # 更新配置中的安装时间
            $package.InstallDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            Write-Host "包 $($package.Id) 更新成功！" -ForegroundColor Green
        }
        catch {
            Write-Host "更新包 $($package.Id) 失败: $_" -ForegroundColor Red
        }
    }
    
    Save-NuGetConfig -ConfigObject $config
}

# 移除包
function Remove-NuGetPackage {
    <#
    .SYNOPSIS
        移除已安装的包
    .PARAMETER PackageId
        包 ID
    .PARAMETER RemoveFiles
        是否同时删除文件
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,
        
        [switch]$RemoveFiles = $false
    )
    
    $config = Get-NuGetConfig
    if (-not $config -or -not $config.InstalledPackages) {
        Write-Host "没有已安装的包。" -ForegroundColor Yellow
        return
    }
    
    $packageToRemove = $config.InstalledPackages | Where-Object { $_.Id -eq $PackageId }
    
    if (-not $packageToRemove) {
        Write-Host "未找到包: $PackageId" -ForegroundColor Red
        return
    }
    
    if ($RemoveFiles -and (Test-Path $packageToRemove.InstallPath)) {
        try {
            Remove-Item -Path $packageToRemove.InstallPath -Recurse -Force
            Write-Host "已删除文件: $($packageToRemove.InstallPath)" -ForegroundColor Green
        }
        catch {
            Write-Host "删除文件失败: $_" -ForegroundColor Red
        }
    }
    
    # 从配置中移除
    $config.InstalledPackages = @($config.InstalledPackages | Where-Object { $_.Id -ne $PackageId })
    Save-NuGetConfig -ConfigObject $config
    
    Write-Host "包 $PackageId 已从配置中移除。" -ForegroundColor Green
}

# 清理包缓存
function Clear-NuGetCache {
    <#
    .SYNOPSIS
        清理 NuGet 缓存
    .PARAMETER All
        清理所有缓存
    .PARAMETER OldVersions
        清理旧版本
    #>
    [CmdletBinding()]
    param(
        [switch]$All,
        
        [switch]$OldVersions
    )
    
    Write-Host "正在清理 NuGet 缓存..." -ForegroundColor Yellow
    
    if ($All) {
        $clearCmd = "& `"$($Config.NuGetExePath)`" locals all -clear"
    }
    elseif ($OldVersions) {
        # 清理除最新版本外的所有版本
        $packagesDir = $Config.DefaultPackagesPath
        if (Test-Path $packagesDir) {
            $packageFolders = Get-ChildItem -Path $packagesDir -Directory
            
            foreach ($folder in $packageFolders) {
                $versions = Get-ChildItem -Path $folder.FullName -Directory
                if ($versions.Count -gt 1) {
                    $latest = $versions | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
                    $oldVersions = $versions | Where-Object { $_.FullName -ne $latest.FullName }
                    
                    foreach ($old in $oldVersions) {
                        Remove-Item -Path $old.FullName -Recurse -Force
                        Write-Host "已删除旧版本: $($folder.Name)\$($old.Name)" -ForegroundColor Gray
                    }
                }
            }
        }
        Write-Host "旧版本清理完成！" -ForegroundColor Green
        return
    }
    else {
        $clearCmd = "& `"$($Config.NuGetExePath)`" locals http-cache -clear"
    }
    
    $clearCmd += " -NonInteractive"
    
    try {
        Invoke-Expression $clearCmd
        Write-Host "缓存清理完成！" -ForegroundColor Green
    }
    catch {
        Write-Host "清理缓存失败: $_" -ForegroundColor Red
    }
}

# 管理包源
function Manage-NuGetSources {
    <#
    .SYNOPSIS
        管理 NuGet 包源
    .PARAMETER Action
        操作：List, Add, Remove
    .PARAMETER Name
        源名称
    .PARAMETER SourceUrl
        源 URL
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("List", "Add", "Remove")]
        [string]$Action,
        
        [string]$Name,
        
        [string]$SourceUrl
    )
    
    switch ($Action) {
        "List" {
            $config = Get-NuGetConfig
            if ($config -and $config.PackageSources) {
                Write-Host "配置的包源:" -ForegroundColor Green
                for ($i = 0; $i -lt $config.PackageSources.Count; $i++) {
                    Write-Host "  [$i] $($config.PackageSources[$i])" -ForegroundColor Cyan
                }
            }
        }
        "Add" {
            if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($SourceUrl)) {
                Write-Host "需要提供源名称和 URL。" -ForegroundColor Red
                return
            }
            
            $config = Get-NuGetConfig
            if (-not $config) {
                $config = @{
                    PackageSources = @()
                    InstalledPackages = @()
                    PackageCache = @{}
                } | ConvertTo-Json | ConvertFrom-Json
            }
            
            if ($config.PackageSources -notcontains $SourceUrl) {
                $config.PackageSources += $SourceUrl
                Save-NuGetConfig -ConfigObject $config
                Write-Host "已添加包源: $Name ($SourceUrl)" -ForegroundColor Green
            }
            else {
                Write-Host "包源已存在。" -ForegroundColor Yellow
            }
        }
        "Remove" {
            if ([string]::IsNullOrEmpty($SourceUrl)) {
                Write-Host "需要提供源 URL。" -ForegroundColor Red
                return
            }
            
            $config = Get-NuGetConfig
            if ($config -and $config.PackageSources) {
                $config.PackageSources = @($config.PackageSources | Where-Object { $_ -ne $SourceUrl })
                Save-NuGetConfig -ConfigObject $config
                Write-Host "已移除包源: $SourceUrl" -ForegroundColor Green
            }
        }
    }
}

# 显示帮助
function Show-NuGetHelp {
    <#
    .SYNOPSIS
        显示帮助信息
    #>
    
    $helpText = @"
===============================================================================
                        NuGet 包管理器 - 帮助
===============================================================================

基本命令:
    1. Search-NuGetPackage -Name "包名"           # 搜索包
    2. Install-NuGetPackage -PackageId "包ID"    # 安装包
    3. Get-InstalledPackages                      # 列出已安装的包
    4. Update-NuGetPackage                       # 更新包
    5. Remove-NuGetPackage -PackageId "包ID"     # 移除包
    6. Clear-NuGetCache                          # 清理缓存
    7. Manage-NuGetSources                       # 管理包源

高级用法:
    • 指定版本: Install-NuGetPackage -PackageId "包ID" -Version "1.0.0"
    • 指定源: Install-NuGetPackage -PackageId "包ID" -Source "源URL"
    • 清理旧版本: Clear-NuGetCache -OldVersions
    • 添加包源: Manage-NuGetSources -Action Add -Name "源名" -SourceUrl "URL"

配置文件位置:
    $($Config.ConfigFile)

包安装目录:
    $($Config.DefaultPackagesPath)

===============================================================================
"@
    
    Write-Host $helpText -ForegroundColor Cyan
}

# 主菜单（交互式）
function Show-NuGetMenu {
    <#
    .SYNOPSIS
        显示交互式菜单
    #>
    
    do {
        Clear-Host
        Write-Host "===============================================================================" -ForegroundColor Cyan
        Write-Host "                       NuGet 包管理器" -ForegroundColor Yellow
        Write-Host "===============================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1.  搜索包" -ForegroundColor Green
        Write-Host "2.  安装包" -ForegroundColor Green
        Write-Host "3.  列出已安装的包" -ForegroundColor Green
        Write-Host "4.  更新包" -ForegroundColor Green
        Write-Host "5.  移除包" -ForegroundColor Green
        Write-Host "6.  清理缓存" -ForegroundColor Green
        Write-Host "7.  管理包源" -ForegroundColor Green
        Write-Host "8.  显示帮助" -ForegroundColor Green
        Write-Host "0.  退出" -ForegroundColor Red
        Write-Host ""
        Write-Host "===============================================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "请选择操作 (0-8)"
        
        switch ($choice) {
            "1" {
                $packageName = Read-Host "输入包名 (支持通配符)"
                if (-not [string]::IsNullOrEmpty($packageName)) {
                    Search-NuGetPackage -Name $packageName
                    Pause
                }
            }
            "2" {
                $packageId = Read-Host "输入包ID"
                if (-not [string]::IsNullOrEmpty($packageId)) {
                    $version = Read-Host "输入版本 (可选，按回车跳过)"
                    Install-NuGetPackage -PackageId $packageId -Version $version
                    Pause
                }
            }
            "3" {
                Get-InstalledPackages
                Pause
            }
            "4" {
                $packageId = Read-Host "输入包ID (可选，按回车更新所有)"
                Update-NuGetPackage -PackageId $packageId
                Pause
            }
            "5" {
                $packageId = Read-Host "输入要移除的包ID"
                if (-not [string]::IsNullOrEmpty($packageId)) {
                    $confirm = Read-Host "是否删除文件？(Y/N)"
                    Remove-NuGetPackage -PackageId $packageId -RemoveFiles:($confirm -eq 'Y')
                    Pause
                }
            }
            "6" {
                Write-Host "1. 清理HTTP缓存" -ForegroundColor Cyan
                Write-Host "2. 清理所有缓存" -ForegroundColor Cyan
                Write-Host "3. 清理旧版本" -ForegroundColor Cyan
                $cacheChoice = Read-Host "选择 (1-3)"
                switch ($cacheChoice) {
                    "1" { Clear-NuGetCache }
                    "2" { Clear-NuGetCache -All }
                    "3" { Clear-NuGetCache -OldVersions }
                }
                Pause
            }
            "7" {
                Write-Host "1. 列出包源" -ForegroundColor Cyan
                Write-Host "2. 添加包源" -ForegroundColor Cyan
                Write-Host "3. 移除包源" -ForegroundColor Cyan
                $sourceChoice = Read-Host "选择 (1-3)"
                switch ($sourceChoice) {
                    "1" { Manage-NuGetSources -Action List }
                    "2" { 
                        $name = Read-Host "输入源名称"
                        $url = Read-Host "输入源URL"
                        Manage-NuGetSources -Action Add -Name $name -SourceUrl $url
                    }
                    "3" { 
                        $url = Read-Host "输入要移除的源URL"
                        Manage-NuGetSources -Action Remove -SourceUrl $url
                    }
                }
                Pause
            }
            "8" {
                Show-NuGetHelp
                Pause
            }
            "0" {
                Write-Host "再见！" -ForegroundColor Green
                return
            }
        }
    } while ($true)
}

# 初始化并显示菜单（如果以交互模式运行）
if ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.InvocationName -eq $PSCommandPath) {
    Initialize-NuGetManager
    Show-NuGetMenu
}

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
)#>

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
}