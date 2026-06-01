##Module Std.Nuget.Library
##Import Std.Nuget.Logger
##Import Std.Nuget.Source

<#
.NOTES
    Name: infinity_nuget_library
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    NuGet 本地包库管理模块
.DESCRIPTION
    这个模块提供以下功能：
    1. 创建和管理本地 NuGet 包库
    2. 安装和卸载 NuGet 包
    3. 包库清单的读写
#>

#region 包库管理
<#
.SYNOPSIS
表示 NuGet 包库的核心类，用于记录包库中的包和包的版本
#>
class NugetPackageLibraryManifest {
    <#
    .SYNOPSIS
    NuGet 包库的包字典，Key 为包Id，Value 为包版本信息字典
    #>
    [hashtable]$Packages = @{}
}

$Script:NugetPackageLibraryManifestFileName = "infinity_nuget_library.json"

<#
.SYNOPSIS
保存 NuGet 包库清单到指定路径

.DESCRIPTION
将 NugetPackageLibraryManifest 对象序列化为 JSON 并保存到指定路径

.PARAMETER Path
必选，包库根目录路径

.PARAMETER Manifest
必选，要保存的包库清单对象

.EXAMPLE
PS> Save-NugetPackageLibraryManifest -Path "C:\NuGetPackages" -Manifest $Manifest
# 保存包库清单到指定目录
#>
function Save-NugetPackageLibraryManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetPackageLibraryManifest]$Manifest
    )
    
    try {
        $ManifestPath = Join-Path $Path $Script:NugetPackageLibraryManifestFileName
        $Script:NugetLogger.Info("保存包库清单到: $ManifestPath")
        
        $Manifest | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $ManifestPath -Encoding UTF8 -Force
        $Script:NugetLogger.Info("包库清单保存成功")
    }
    catch {
        $Script:NugetLogger.Error("保存包库清单失败: $($_.Exception.Message)")
        throw
    }
}

<#
.SYNOPSIS
读取 NuGet 包库清单

.DESCRIPTION
从指定路径读取并反序列化包库清单文件

.PARAMETER Path
必选，包库根目录路径

.EXAMPLE
PS> $Manifest = Read-NugetPackageLibraryManifest -Path "C:\NuGetPackages"
# 从指定目录读取包库清单

.OUTPUTS
[NugetPackageLibraryManifest] - 包库清单对象
#>
function Read-NugetPackageLibraryManifest {
    [CmdletBinding()]
    [OutputType([NugetPackageLibraryManifest])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    try {
        $ManifestPath = Join-Path $Path $Script:NugetPackageLibraryManifestFileName
        
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "未找到库清单文件: $ManifestPath"
        }

        $Script:NugetLogger.Info("从 $ManifestPath 读取包库清单")
        $Json = Get-Content -Path $ManifestPath -Raw -Encoding UTF8
        $ManifestData = $Json | ConvertFrom-Json -AsHashtable
        
        if(-not $ManifestData.ContainsKey("Packages")){
            $Script:NugetLogger.Warn("包库清单缺失 Packages 项, 自动补全")
            $PackageManifest['Packages'] = @{}
        }

        $PackageManifest = [NugetPackageLibraryManifest]::new()
        $PackageManifest.Packages = $ManifestData.Packages
            
        $Script:NugetLogger.Info("包库清单读取成功")
        return $PackageManifest
    }
    catch {
        $Script:NugetLogger.Error("读取包库清单失败: $($_.Exception.Message)")
        throw
    }
}

<#
.SYNOPSIS
创建新的 NuGet 包库

.DESCRIPTION
在指定路径创建包库目录结构并初始化清单文件

.PARAMETER Path
必选，包库根目录路径

.EXAMPLE
PS> $LibraryPath = New-NugetPackageLibraryManifest -Path "C:\NuGetPackages"
# 在指定路径创建包库

.OUTPUTS
[string] - 创建后的包库完整路径
#>
function New-NugetPackageLibraryManifest {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $Item = New-Item -Path $Path -ItemType Directory -Force
        $Path = $Item.FullName
    }
    else {
        $Item = Get-Item -Path $Path
        $Path = $Item.FullName
    }
    $Script:NugetLogger.Info("Nuget 包库文件夹: $($Path)")

    $PackageLibrary = [NugetPackageLibraryManifest]::new()

    Save-NugetPackageLibraryManifest -Path $Path -Manifest $PackageLibrary

    return $Path
}

<#
.SYNOPSIS
安装指定的 NuGet 包

.DESCRIPTION
从指定的包源下载并安装 NuGet 包到本地包库，解压包内容到包库目录

.PARAMETER Source
必选，NugetSource 类的实例（已初始化的包源对象）

.PARAMETER Id
必选，要安装的 NuGet 包ID

.PARAMETER Version
必选，要安装的 NuGet 包版本

.PARAMETER LibraryPath
必选，包库根目录路径

.PARAMETER Force
可选，强制重新安装包（覆盖已存在的版本）

.EXAMPLE
PS> Install-NugetPackage -Source $Source -Id "Newtonsoft.Json" -Version "13.0.1" -LibraryPath "C:\NuGetPackages"
# 安装 Newtonsoft.Json 13.0.1 版本到指定包库

.EXAMPLE
PS> Install-NugetPackage -Source $Source -Id "Serilog" -Version "3.1.1" -LibraryPath "C:\NuGetPackages" -Force
# 强制重新安装 Serilog 3.1.1 版本

.OUTPUTS
[string] - 安装后的包目录路径
#>
function Install-NugetPackage {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # 验证包库路径
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }

        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $Id = $Id.Trim().ToLowerInvariant()
        $Version = $Version.Trim().ToLowerInvariant()

        # 读取包库清单
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath
        
        # 构造包位置
        $PackagePath = Join-Path $LibraryPath $Id $Version

        # 检查是否已安装
        if ($Manifest.Packages.ContainsKey($Id) -and $Manifest.Packages[$Id].ContainsKey($Version)) {
            if ($Force) {
                $Script:NugetLogger.Warn("包已存在，强制重新安装: $Id.$Version")
                if (Test-Path -Path $PackagePath) {
                    Remove-Item -Path $PackagePath -Recurse -Force
                }
            }
            else {
                $Script:NugetLogger.Info("包已安装: $Id.$Version")
                return $PackagePath
            }
        }

        if (Test-Path -Path $PackagePath) {
            if ($Force) {
                $Script:NugetLogger.Warn("异常的包文件存在于: $PackagePath")
                $Script:NugetLogger.Warn("强制删除: $PackagePath")
                Remove-Item -Path $PackagePath -Recurse -Force
            }
            else {
                throw "异常的包文件存在于: $PackagePath"
            }
        }
        
        $Script:NugetLogger.Info("开始安装包: $Id 版本: $Version")
        
        # 下载包内容
        $PackageBytes = Get-NugetPackagContent -Source $Source -Id $Id -Version $Version
        $Script:NugetLogger.Info("包下载完成，大小: $([math]::Round($PackageBytes.Length/1KB,2)) KB")
        
        # 创建包目录
        $null = New-Item -Path $PackagePath -ItemType Directory -Force
        $Script:NugetLogger.Info("创建包目录: $PackagePath")
        
        # 保存 .nupkg 文件
        $NupkgPath = Join-Path $PackagePath "$Id.$Version.nupkg"
        [System.IO.File]::WriteAllBytes($NupkgPath, $PackageBytes)
        $Script:NugetLogger.Info("保存 .nupkg 文件到: $NupkgPath")
        
        # 解压 .nupkg 文件
        $Script:NugetLogger.Info("开始解压包文件")
        Expand-Archive -Path $NupkgPath -DestinationPath $PackagePath
        $Script:NugetLogger.Info("包解压完成")
        
        # 更新包库清单
        if (-not $Manifest.Packages.ContainsKey($Id)) {
            $Manifest.Packages[$Id] = @{}
        }
        
        $Manifest.Packages[$Id][$Version] = @{
            InstallDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
        $Script:NugetLogger.Info("包安装成功: $Id.$Version")
        
        return $PackagePath
    }
    catch {
        $Script:NugetLogger.Error("安装包失败: $($_.Exception.Message)")
        
        # 清理失败安装的目录
        if ($PackagePath -and (Test-Path -Path $PackagePath)) {
            Remove-Item -Path $PackagePath -Recurse -Force -ErrorAction SilentlyContinue
            $Script:NugetLogger.Info("清理失败安装的目录: $PackagePath")
        }
        
        throw
    }
}

<#
.SYNOPSIS
卸载指定的 NuGet 包

.DESCRIPTION
从本地包库中卸载指定的 NuGet 包，删除包目录并更新清单

.PARAMETER Id
必选，要卸载的 NuGet 包ID

.PARAMETER Version
必选，要卸载的 NuGet 包版本

.PARAMETER LibraryPath
必选，包库根目录路径

.PARAMETER AllVersions
可选，卸载该包的所有版本

.EXAMPLE
PS> Uninstall-NugetPackage -Id "Newtonsoft.Json" -Version "13.0.1" -LibraryPath "C:\NuGetPackages"
# 卸载指定版本的 Newtonsoft.Json 包

.EXAMPLE
PS> Uninstall-NugetPackage -Id "Serilog" -LibraryPath "C:\NuGetPackages" -AllVersions
# 卸载 Serilog 包的所有版本

.OUTPUTS
[bool] - 卸载是否成功
#>
function Uninstall-NugetPackage {
    [CmdletBinding(DefaultParameterSetName = 'SpecificVersion')]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVersion')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AllVersions')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVersion')]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'AllVersions')]
        [switch]$AllVersions
    )
    
    try {
        # 验证包库路径
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }
        
        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $Id = $Id.Trim().ToLowerInvariant()
        
        # 读取包库清单
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath
        
        if (-not $Manifest.Packages.ContainsKey($Id)) {
            $Script:NugetLogger.Warn("包未安装: $Id")
            return $false
        }
        
        if ($AllVersions) {
            # 卸载所有版本
            $VersionCount = $Manifest.Packages[$Id].Count
            if ($VersionCount -eq 0) {
                $Manifest.Packages.Remove($Id)
                Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
                return $true
            }
            
            $Script:NugetLogger.Info("开始卸载包 $Id 的所有版本，共 $VersionCount 个版本")
            
            # 删除包目录
            $PackageDir = Join-Path $LibraryPath $Id
            if (Test-Path -Path $PackageDir -PathType Container) {
                Remove-Item -Path $PackageDir -Recurse -Force
                $Script:NugetLogger.Info("删除包目录: $PackageDir")
            }
            
            # 从清单中移除
            $Manifest.Packages.Remove($Id)
            
            Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
            $Script:NugetLogger.Info("成功卸载包 $Id 的所有版本")
            
            return $true
        }
        # 卸载指定版本
        $Version = $Version.Trim().ToLowerInvariant()
            
        if (-not $Manifest.Packages[$Id].ContainsKey($Version)) {
            $Script:NugetLogger.Warn("包版本未安装: $Id.$Version")
            return $false
        }
            
        $Script:NugetLogger.Info("开始卸载包: $Id.$Version")
            
        # 删除包目录
        $PackageDir = Join-Path $LibraryPath $Id $Version
        if (Test-Path -Path $PackageDir -PathType Container) {
            Remove-Item -Path $PackageDir -Recurse -Force
            $Script:NugetLogger.Info("删除包目录: $PackageDir")
        }
            
        # 从清单中移除
        $Manifest.Packages[$Id].Remove($Version)
            
        # 如果该包没有其他版本，移除包条目
        if ($Manifest.Packages[$Id].Count -eq 0) {
            $Manifest.Packages.Remove($Id)
        }
            
        Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
        $Script:NugetLogger.Info("成功卸载包: $Id.$Version")
            
        return $true
        
    }
    catch {
        $Script:NugetLogger.Error("卸载包失败: $($_.Exception.Message)")
        throw
    }
}
#endregion