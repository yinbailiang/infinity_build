##Module Std.Nuget.Loader
##Import Std.Nuget.Logger
##Import Std.Nuget.Versioning
##Import Std.Nuget.Frameworks
##Import Std.Nuget.Library

<#
.NOTES
    Name: infinity_nuget_loader
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    NuGet 包加载器模块
.DESCRIPTION
    这个模块提供以下功能：
    1. 从本地包库中加载 NuGet 包的程序集
    2. 根据目标框架 (TFM) 自动匹配最佳兼容版本
    3. 幂等加载——同一包不会重复加载
    4. 自动检测当前 PowerShell 运行时的目标框架
#>

#region 内部状态

# 已加载包追踪表: Key = "PackageId|Version|TFM", Value = 加载时间
$Script:ImportedPackages = @{}

# 已加载程序集追踪: Key = 程序集完整路径, Value = 加载时间
$Script:ImportedAssemblies = @{}

#endregion

#region 运行时 TFM 检测

<#
.SYNOPSIS
获取当前 PowerShell 运行时的 NuGet 目标框架

.DESCRIPTION
自动检测当前 PowerShell 会话所运行的 .NET 运行时版本，
返回对应的 NuGet 框架短名称（如 net472、net8.0）。

.EXAMPLE
PS> Get-CurrentRuntimeFramework
# 在 PowerShell 7.4 上返回 net8.0，在 Windows PowerShell 5.1 上返回 net472
#>
function Get-CurrentRuntimeFramework {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 获取当前运行时的 .NET 版本
    $version = [System.Environment]::Version

    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell 6+ (.NET Core / .NET 5+)
        $major = $version.Major
        $minor = $version.Minor

        # .NET 5+ 统一为 .NETCoreApp 标识符
        if ($major -ge 5) {
            return "net$major.$minor"
        }

        # .NET Core 1.0-3.1
        return "netcoreapp$major.$minor"
    }
    else {
        # Windows PowerShell 5.1 (.NET Framework 4.x)
        $releaseKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue
        if ($releaseKey) {
            $release = $releaseKey.Release
            # 根据 .NET Framework Release DWORD 映射版本
            switch ($release) {
                { $_ -ge 533320 } { return 'net481' }
                { $_ -ge 528040 } { return 'net48' }
                { $_ -ge 461808 } { return 'net472' }
                { $_ -ge 461308 } { return 'net471' }
                { $_ -ge 460798 } { return 'net47' }
                { $_ -ge 394802 } { return 'net462' }
                { $_ -ge 394254 } { return 'net461' }
                { $_ -ge 393295 } { return 'net46' }
                { $_ -ge 379893 } { return 'net452' }
                { $_ -ge 378675 } { return 'net451' }
                { $_ -ge 378389 } { return 'net45' }
                default { return 'net48' }  # 默认假设最新
            }
        }
        # 回退：根据 Environment.Version 推断
        return "net$($version.Major)$($version.Minor)"
    }
}

#endregion

#region 包 TFM 扫描

<#
.SYNOPSIS
扫描指定 NuGet 包的 lib 目录，获取所有可用的目标框架

.DESCRIPTION
解析包目录下的 lib 子目录，将每个子文件夹名解析为 NuGetFramework 对象，
返回该包支持的所有目标框架列表。

.PARAMETER PackagePath
必选，已安装 NuGet 包的根目录路径（包含 lib 子目录）

.EXAMPLE
PS> Get-NugetPackageAvailableTFMs -PackagePath "C:\NuGetPackages\newtonsoft.json\13.0.1"
# 返回 Newtonsoft.Json 13.0.1 支持的所有 TFM 列表

.OUTPUTS
[NuGetFramework[]] - 包支持的目标框架数组
#>
function Get-NugetPackageAvailableTFMs {
    [CmdletBinding()]
    [OutputType([NuGetFramework[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath
    )

    $LibPath = Join-Path $PackagePath 'lib'
    if (-not (Test-Path -Path $LibPath -PathType Container)) {
        $Script:NugetLogger.Warn("包目录中未找到 lib 文件夹: $PackagePath")
        return @()
    }

    $TfmFolders = Get-ChildItem -Path $LibPath -Directory |
        Where-Object { $_.Name -notmatch '^_' } |  # 排除 _rels 等特殊目录
        ForEach-Object { $_.Name }

    if ($TfmFolders.Count -eq 0) {
        $Script:NugetLogger.Warn("lib 目录下未找到 TFM 子文件夹: $LibPath")
        return @()
    }

    $Frameworks = [System.Collections.Generic.List[NuGetFramework]]::new()
    foreach ($folder in $TfmFolders) {
        try {
            $fx = ConvertTo-NuGetFramework -FrameworkString $folder
            if (-not $fx.IsUnsupported()) {
                $Frameworks.Add($fx)
            }
            else {
                $Script:NugetLogger.Warn("跳过无法识别的 TFM 文件夹: $folder")
            }
        }
        catch {
            $Script:NugetLogger.Warn("解析 TFM 文件夹失败: $folder, 错误: $($_.Exception.Message)")
        }
    }

    return $Frameworks.ToArray()
}

<#
.SYNOPSIS
在包目录中找到与目标框架最匹配的程序集路径

.DESCRIPTION
使用 Get-NearestNuGetFramework 在包支持的所有 TFM 中匹配最佳框架，
返回对应 lib 子目录的完整路径。

.PARAMETER PackagePath
必选，已安装 NuGet 包的根目录路径

.PARAMETER TargetFramework
可选，目标框架字符串（如 net8.0、net472）。不指定时自动检测当前运行时

.EXAMPLE
PS> $LibDir = Resolve-NugetPackageTFMPath -PackagePath "C:\NuGetPackages\serilog\3.1.1" -TargetFramework "net8.0"
# 返回最匹配的 lib 子目录路径

.OUTPUTS
[string] - 最佳匹配的 lib 子目录完整路径，无匹配时返回 $null
#>
function Resolve-NugetPackageTFMPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )

    # 解析目标框架
    $TargetFxString = if ($TargetFramework) { $TargetFramework } else { Get-CurrentRuntimeFramework }
    $TargetFx = ConvertTo-NuGetFramework -FrameworkString $TargetFxString
    $Script:NugetLogger.Info("目标框架: $TargetFxString -> $(ConvertTo-NuGetFrameworkShortName $TargetFx)")

    # 获取包可用的 TFM 列表
    $AvailableFxs = Get-NugetPackageAvailableTFMs -PackagePath $PackagePath
    if ($AvailableFxs.Count -eq 0) {
        $Script:NugetLogger.Warn("包未提供任何可识别的 TFM 程序集")
        return $null
    }

    $Script:NugetLogger.Info("包可用 TFM: $($AvailableFxs.ForEach({ ConvertTo-NuGetFrameworkShortName $_ }) -join ', ')")

    # 就近匹配
    $BestMatch = Get-NearestNuGetFramework -Target $TargetFx -Candidates $AvailableFxs
    if (-not $BestMatch) {
        $Script:NugetLogger.Warn("未找到与 $TargetFxString 兼容的 TFM")
        return $null
    }

    $BestMatchFolder = ConvertTo-NuGetFrameworkShortName -Framework $BestMatch
    $Script:NugetLogger.Info("最佳 TFM 匹配: $BestMatchFolder")

    $MatchedLibPath = Join-Path $PackagePath 'lib' $BestMatchFolder
    if (-not (Test-Path -Path $MatchedLibPath -PathType Container)) {
        # 回退：尝试原始文件夹名（某些包可能使用非标准命名）
        $OriginalFolder = Get-ChildItem -Path (Join-Path $PackagePath 'lib') -Directory |
            Where-Object { (ConvertTo-NuGetFramework -FrameworkString $_.Name -ErrorAction SilentlyContinue).Equals($BestMatch) } |
            Select-Object -First 1
        if ($OriginalFolder) {
            $MatchedLibPath = $OriginalFolder.FullName
        }
        else {
            $Script:NugetLogger.Error("匹配的 TFM 目录不存在: $MatchedLibPath")
            return $null
        }
    }

    return $MatchedLibPath
}

#endregion

#region 程序集加载

<#
.SYNOPSIS
从指定的 lib 目录加载所有 .NET 程序集

.DESCRIPTION
遍历指定目录下的所有 .dll 文件，使用 [System.Reflection.Assembly]::LoadFrom 加载。
已加载的程序集会被跳过（幂等），通过 $Script:ImportedAssemblies 追踪。

.PARAMETER LibPath
必选，包含 .dll 程序集的目录路径

.PARAMETER Force
可选，强制重新加载已导入的程序集

.EXAMPLE
PS> $Assemblies = Import-NugetAssemblies -LibPath "C:\NuGetPackages\serilog\3.1.1\lib\net8.0"
# 加载 net8.0 目录下的所有程序集

.OUTPUTS
[System.Reflection.Assembly[]] - 本次新加载的程序集数组
#>
function Import-NugetAssemblies {
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if (-not (Test-Path -Path $LibPath -PathType Container)) {
        throw "程序集目录不存在: $LibPath"
    }

    $DllFiles = Get-ChildItem -Path $LibPath -Filter '*.dll' -File
    if ($DllFiles.Count -eq 0) {
        $Script:NugetLogger.Warn("目录中未找到 .dll 文件: $LibPath")
        return @()
    }

    $NewlyLoaded = [System.Collections.Generic.List[System.Reflection.Assembly]]::new()

    foreach ($dll in $DllFiles) {
        $DllPath = $dll.FullName

        # 幂等检查：跳过已加载的程序集
        if (-not $Force -and $Script:ImportedAssemblies.ContainsKey($DllPath)) {
            $Script:NugetLogger.Info("程序集已加载，跳过: $($dll.Name)")
            continue
        }

        try {
            $Script:NugetLogger.Info("加载程序集: $($dll.Name)")

            # 先尝试按名称查找，避免重复加载
            $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($DllPath)
            $ExistingAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { -not $_.IsDynamic -and $_.GetName().Name -eq $AssemblyName.Name } |
                Select-Object -First 1

            if ($ExistingAssembly -and -not $Force) {
                $Script:NugetLogger.Info("程序集已存在于 AppDomain，跳过加载: $($AssemblyName.Name)")
                $Script:ImportedAssemblies[$DllPath] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                continue
            }

            $LoadedAssembly = [System.Reflection.Assembly]::LoadFrom($DllPath)
            $Script:ImportedAssemblies[$DllPath] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $NewlyLoaded.Add($LoadedAssembly)
            $Script:NugetLogger.Info("程序集加载成功: $($AssemblyName.Name) v$($AssemblyName.Version)")
        }
        catch {
            $Script:NugetLogger.Error("加载程序集失败: $($dll.Name), 错误: $($_.Exception.Message)")
            # 对于非致命错误继续加载其他程序集
        }
    }

    return $NewlyLoaded.ToArray()
}

#endregion

#region 包加载

<#
.SYNOPSIS
从本地包库加载指定的 NuGet 包

.DESCRIPTION
在本地包库中查找指定包，解析最佳 TFM 匹配，并加载对应程序集。
支持按版本号指定、自动选择最新版本、幂等加载。

.PARAMETER Id
必选，NuGet 包的唯一标识符

.PARAMETER LibraryPath
必选，本地包库根目录路径

.PARAMETER Version
可选，指定要加载的包版本号。不指定时自动选择已安装的最新版本

.PARAMETER TargetFramework
可选，目标框架字符串。不指定时自动检测当前 PowerShell 运行时

.PARAMETER Force
可选，强制重新加载（即使已导入过）

.EXAMPLE
PS> Import-NugetPackage -Id "Newtonsoft.Json" -LibraryPath "C:\NuGetPackages"
# 加载 Newtonsoft.Json 最新版本，自动匹配当前运行时 TFM

.EXAMPLE
PS> Import-NugetPackage -Id "Serilog" -Version "3.1.1" -LibraryPath "C:\NuGetPackages" -TargetFramework "net8.0"
# 加载 Serilog 3.1.1，显式指定 net8.0 框架

.EXAMPLE
PS> Import-NugetPackage -Id "Dapper" -LibraryPath "C:\NuGetPackages" -Force
# 强制重新加载 Dapper 包

.OUTPUTS
[PSCustomObject] - 加载结果，包含 PackageId、Version、MatchedTFM、LoadedAssemblies 等属性
#>
function Import-NugetPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        # 验证包库路径
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }
        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $IdNormalized = $Id.Trim().ToLowerInvariant()

        # 读取包库清单
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath

        # 检查包是否已安装
        if (-not $Manifest.Packages.ContainsKey($IdNormalized)) {
            throw "包未安装: $Id。请先使用 Install-NugetPackage 安装。"
        }

        $InstalledVersions = $Manifest.Packages[$IdNormalized]

        # 确定要加载的版本
        $ResolvedVersion = $null
        if ($Version) {
            $VersionNormalized = $Version.Trim().ToLowerInvariant()
            if (-not $InstalledVersions.ContainsKey($VersionNormalized)) {
                throw "包版本未安装: $Id v$Version"
            }
            $ResolvedVersion = $VersionNormalized
        }
        else {
            # 自动选择最新版本：按 NuGetVersion 排序取最大值
            $SortedVersions = $InstalledVersions.Keys |
                ForEach-Object { [NuGetVersion]::new($_) } |
                Sort-Object -Descending
            if ($SortedVersions.Count -eq 0) {
                throw "包 $Id 无已安装版本"
            }
            $ResolvedVersion = $SortedVersions[0].NormalizedVersion
            $Script:NugetLogger.Info("自动选择最新版本: $ResolvedVersion")
        }

        # 解析目标框架
        $TargetFxString = if ($TargetFramework) { $TargetFramework } else { Get-CurrentRuntimeFramework }

        # 幂等检查
        $ImportKey = "$IdNormalized|$ResolvedVersion|$TargetFxString"
        if (-not $Force -and $Script:ImportedPackages.ContainsKey($ImportKey)) {
            $Script:NugetLogger.Info("包已导入，跳过（幂等）: $ImportKey")
            return [PSCustomObject]@{
                PackageId         = $IdNormalized
                Version           = $ResolvedVersion
                TargetFramework   = $TargetFxString
                MatchedTFM        = $Script:ImportedPackages[$ImportKey].MatchedTFM
                LoadedAssemblies  = @()
                IsCached          = $true
                ImportTime        = $Script:ImportedPackages[$ImportKey].ImportTime
            }
        }

        # 构造包路径
        $PackagePath = Join-Path $LibraryPath $IdNormalized $ResolvedVersion
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "包目录不存在，可能已被手动删除: $PackagePath"
        }

        $Script:NugetLogger.Info("开始加载包: $IdNormalized v$ResolvedVersion")

        # TFM 匹配
        $MatchedLibPath = Resolve-NugetPackageTFMPath -PackagePath $PackagePath -TargetFramework $TargetFxString
        if (-not $MatchedLibPath) {
            throw "无法为 $IdNormalized v$ResolvedVersion 找到与 $TargetFxString 兼容的程序集"
        }

        $Script:NugetLogger.Info("匹配的程序集路径: $MatchedLibPath")

        # 加载程序集
        $LoadedAssemblies = Import-NugetAssemblies -LibPath $MatchedLibPath -Force:$Force

        # 记录导入状态
        $MatchedTfmFolder = Split-Path $MatchedLibPath -Leaf
        $ImportTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Script:ImportedPackages[$ImportKey] = @{
            MatchedTFM  = $MatchedTfmFolder
            ImportTime  = $ImportTime
            PackagePath = $PackagePath
        }

        $Script:NugetLogger.Info("包加载完成: $IdNormalized v$ResolvedVersion -> $MatchedTfmFolder, 加载了 $($LoadedAssemblies.Count) 个程序集")

        return [PSCustomObject]@{
            PackageId         = $IdNormalized
            Version           = $ResolvedVersion
            TargetFramework   = $TargetFxString
            MatchedTFM        = $MatchedTfmFolder
            LoadedAssemblies  = $LoadedAssemblies
            IsCached          = $false
            ImportTime        = $ImportTime
        }
    }
    catch {
        $Script:NugetLogger.Error("加载包失败: $($_.Exception.Message)")
        throw
    }
}

<#
.SYNOPSIS
获取已通过 Import-NugetPackage 加载的包列表

.DESCRIPTION
查询当前会话中已导入的 NuGet 包信息，支持按包ID筛选。

.PARAMETER Id
可选，按包ID筛选已导入的包

.EXAMPLE
PS> Get-ImportedNugetPackage
# 列出所有已导入的包

.EXAMPLE
PS> Get-ImportedNugetPackage -Id "Newtonsoft.Json"
# 查看指定包的导入状态

.OUTPUTS
[PSCustomObject[]] - 已导入包的详细信息数组
#>
function Get-ImportedNugetPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id
    )

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($key in $Script:ImportedPackages.Keys) {
        $Parts = $key -split '\|'
        $PkgId = $Parts[0]
        $PkgVersion = $Parts[1]
        $PkgTFM = $Parts[2]

        if ($Id -and $PkgId -ne $Id.Trim().ToLowerInvariant()) { continue }

        $Results.Add([PSCustomObject]@{
            PackageId       = $PkgId
            Version         = $PkgVersion
            TargetFramework = $PkgTFM
            MatchedTFM      = $Script:ImportedPackages[$key].MatchedTFM
            ImportTime      = $Script:ImportedPackages[$key].ImportTime
            PackagePath     = $Script:ImportedPackages[$key].PackagePath
        })
    }

    return $Results.ToArray()
}

<#
.SYNOPSIS
清除当前会话的包导入记录

.DESCRIPTION
重置导入追踪状态，不会卸载已加载的程序集。
主要用于测试或需要重新导入所有包的场景。

.PARAMETER Id
可选，仅清除指定包的导入记录。不指定时清除全部

.EXAMPLE
PS> Reset-ImportedNugetPackage
# 清除所有导入记录

.EXAMPLE
PS> Reset-ImportedNugetPackage -Id "Newtonsoft.Json"
# 仅清除 Newtonsoft.Json 的导入记录
#>
function Reset-ImportedNugetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id
    )

    if ($Id) {
        $IdNormalized = $Id.Trim().ToLowerInvariant()
        $KeysToRemove = $Script:ImportedPackages.Keys | Where-Object { $_ -like "$IdNormalized|*" }
        foreach ($k in $KeysToRemove) {
            $Script:ImportedPackages.Remove($k)
        }
        $Script:NugetLogger.Info("已清除包 $IdNormalized 的导入记录")
    }
    else {
        $Script:ImportedPackages.Clear()
        $Script:NugetLogger.Info("已清除全部导入记录")
    }
}

#endregion