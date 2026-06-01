##Module Std.Nuget.Versioning

<#
.NOTES
    Name: infinity_nuget_versioning
    Author: YinBailiang
    Version: 2.0.0
.SYNOPSIS
    NuGet 包版本号处理模块
.DESCRIPTION
    这个模块提供以下功能：
    1. 解析 NuGet 包版本号（遵循微软 NuGet 官方版本规范）
    2. 比较 NuGet 版本号（遵循 SemVer 2.0.0 排序规则）
    3. 版本范围约束（VersionRange：最小/最大版本 + 浮动行为）
    4. 浮动版本行为（FloatRange：通配符如 1.0.*、*-*）
    5. 最佳版本匹配（Find-BestMatch）
    6. 多种比较模式（VersionComparison：仅版本/含预发布/含元数据）

    参考：NuGet.Client\src\NuGet.Core\NuGet.Versioning
#>

#region 枚举定义

<#
.SYNOPSIS
版本比较模式枚举（对应官方 NuGet.Versioning.VersionComparison）

.DESCRIPTION
- Default: SemVer 2.0.0 规则比较（含预发布标签，忽略构建元数据）
- Version: 仅比较核心版本号（Major.Minor.Patch.Revision）
- VersionRelease: 比较核心版本号 + 预发布标签
- VersionReleaseMetadata: 比较全部字段（含构建元数据）
#>
enum VersionComparison {
    Default               = 0
    Version               = 1
    VersionRelease        = 2
    VersionReleaseMetadata = 3
}

<#
.SYNOPSIS
浮动版本行为枚举（对应官方 NuGet.Versioning.NuGetVersionFloatBehavior）

.DESCRIPTION
- None: 不浮动，精确匹配
- Prerelease: 浮动预发布标签，匹配最高预发布版
- Revision: 浮动修订号（x.y.z.*）
- Patch: 浮动补丁号（x.y.*）
- Minor: 浮动次版本号（x.*）
- Major: 浮动主版本号（*）
- AbsoluteLatest: 浮动所有段 + 预发布（*-*），匹配绝对最新版
- PrereleaseRevision: 浮动修订号 + 预发布（x.y.z.*-*）
- PrereleasePatch: 浮动补丁号 + 预发布（x.y.*-*）
- PrereleaseMinor: 浮动次版本号 + 预发布（x.*-*）
- PrereleaseMajor: 浮动主版本号 + 部分预发布（*-rc.*）
#>
enum NuGetVersionFloatBehavior {
    None
    Prerelease
    Revision
    Patch
    Minor
    Major
    AbsoluteLatest
    PrereleaseRevision
    PrereleasePatch
    PrereleaseMinor
    PrereleaseMajor
}

#endregion

#region 版本类定义

<#
.SYNOPSIS
NuGet 包版本号类（遵循微软 NuGet 官方版本规范）

.DESCRIPTION
封装 NuGet 版本号的解析结果，包含核心段、预发布标签、构建元数据等属性。
通过构造函数自动解析版本字符串，支持 ToString() 输出归一化版本号。

.PROPERTY OriginalVersion
原始版本字符串（如：v10.0.17763.1-preview）

.PROPERTY NormalizedVersion
归一化版本号（如：10.0.17763.1-preview）

.PROPERTY Major
主版本号 [int]

.PROPERTY Minor
次版本号 [int]

.PROPERTY Patch
补丁版本号 [int]

.PROPERTY Revision
修订版本号 [int]（第4段，缺省为0）

.PROPERTY CoreSegments
核心段数组 [int[]]（4元素：Major, Minor, Patch, Revision）

.PROPERTY PreRelease
预发布标签 [string]（如：preview、rc.2），无则为 $null

.PROPERTY BuildMetadata
构建元数据 [string]（如：git789012），无则为 $null

.EXAMPLE
PS> [NuGetVersion]::new("v10.0.17763.1-preview")

OriginalVersion   : v10.0.17763.1-preview
NormalizedVersion : 10.0.17763.1-preview
Major             : 10
Minor             : 0
Patch             : 17763
Revision          : 1
CoreSegments      : {10, 0, 17763, 1}
PreRelease        : preview
BuildMetadata     :
#>
class NuGetVersion {
    [string]   $OriginalVersion
    [string]   $NormalizedVersion
    [int]      $Major
    [int]      $Minor
    [int]      $Patch
    [int]      $Revision
    [int[]]    $CoreSegments
    [string]   $PreRelease
    [string[]] $ReleaseLabels
    [string]   $BuildMetadata

    <#
    .SYNOPSIS
    解析 NuGet 版本字符串并构造 NuGetVersion 实例
    
    .DESCRIPTION
    遵循 NuGet 官方版本规范：1-4 段核心数字、v 前缀、版本归一化、SemVer 2.0 预发布/构建元数据。
    不符合规范的版本号直接抛出错误。
    
    .PARAMETER VersionString
    NuGet 包版本字符串（如：v10.0.17763.1-preview、2.5.8、1.01.0-beta+git789）
    
    .EXAMPLE
    PS> [NuGetVersion]::new("v2.5.0.0-alpha")
    #>
    NuGetVersion([string] $VersionString) {
        # NuGet 官方版本规范正则（使用 [regex]::Match 避免 PowerShell 类中 $Matches 不可用的问题）
        $NugetVersionRegex = [regex]::new(
            '^(?:v)?(?<CoreSegments>\d+(?:\.\d+){0,3})(?:-(?<Prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<Buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
        )

        # 步骤1：清理输入（移除所有空格，兼容 NuGet 官方行为：value.Replace(" ", "")）
        $CleanVersion = $VersionString.Trim() -replace '\s+', ''

        # 步骤2：匹配 NuGet 版本正则
        $RegexMatch = $NugetVersionRegex.Match($CleanVersion)
        if (-not $RegexMatch.Success) {
            throw "无效的 NuGet 版本号 '$CleanVersion'：不符合 NuGet 官方版本规范（参考：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning）"
        }

        $this.OriginalVersion = $CleanVersion

        # 步骤3：拆分核心数字段并处理前导零（NuGet 归一化规则：移除前导零）
        $Segments = $RegexMatch.Groups['CoreSegments'].Value -split '\.' | ForEach-Object {
            if ($_ -eq '0') { 0 } else { [int]($_ -replace '^0+', '') }
        }

        # 步骤4：补全核心段到4段（NuGet 支持 1-4 段，缺省补 0）
        while ($Segments.Count -lt 4) {
            $Segments += 0
        }

        $this.CoreSegments = $Segments
        $this.Major   = $Segments[0]
        $this.Minor   = $Segments[1]
        $this.Patch   = $Segments[2]
        $this.Revision = $Segments[3]

        # 步骤5：生成 NuGet 归一化版本号
        $NormalizedCore = $Segments[0..2] -join '.'
        if ($Segments[3] -ne 0) {
            $NormalizedCore = $Segments -join '.'
        }
        # NuGet 归一化版本号不包含构建元数据（构建元数据仅用于显示）
        $Normalized = $NormalizedCore
        $PreReleaseGroup = $RegexMatch.Groups['Prerelease']
        $BuildMetadataGroup = $RegexMatch.Groups['Buildmetadata']
        if ($PreReleaseGroup.Success -and $PreReleaseGroup.Value) {
            $Normalized += "-$($PreReleaseGroup.Value)"
        }
        $this.NormalizedVersion = $Normalized

        # 步骤6：设置预发布和构建元数据
        $this.PreRelease    = if ($PreReleaseGroup.Success)    { $PreReleaseGroup.Value    } else { $null }
        $this.BuildMetadata = if ($BuildMetadataGroup.Success) { $BuildMetadataGroup.Value } else { $null }

        # 步骤7：设置预发布标签数组
        if ($this.PreRelease) {
            $this.ReleaseLabels = $this.PreRelease -split '\.'
        }
        else {
            $this.ReleaseLabels = @()
        }
    }

    <#
    .SYNOPSIS
    返回归一化版本号字符串（不含构建元数据）
    #>
    [string] ToString() {
        return $this.NormalizedVersion
    }

    <#
    .SYNOPSIS
    返回含构建元数据的完整版本号字符串
    #>
    [string] ToFullString() {
        $result = $this.NormalizedVersion
        if ($this.HasMetadata()) {
            $result += "+$($this.BuildMetadata)"
        }
        return $result
    }

    <#
    .SYNOPSIS
    是否为预发布版本（有预发布标签）
    #>
    [bool] IsPrerelease() {
        return $null -ne $this.PreRelease -and $this.PreRelease.Length -gt 0
    }

    <#
    .SYNOPSIS
    是否有构建元数据
    #>
    [bool] HasMetadata() {
        return $null -ne $this.BuildMetadata -and $this.BuildMetadata.Length -gt 0
    }

    <#
    .SYNOPSIS
    是否为旧版4段版本号（Revision > 0）
    #>
    [bool] IsLegacyVersion() {
        return $this.Revision -gt 0
    }

    <#
    .SYNOPSIS
    是否为 SemVer 2.0.0 版本（多级预发布标签 或 含构建元数据）
    #>
    [bool] IsSemVer2() {
        return ($this.ReleaseLabels.Count -gt 1) -or ($this.HasMetadata())
    }
}

#endregion

#region 版本范围类定义

<#
.SYNOPSIS
浮动版本范围类（对应官方 NuGet.Versioning.FloatRange）

.DESCRIPTION
表示版本号中的浮动（通配符）部分，如 1.0.*、*-rc.* 等。
用于确定版本匹配时的浮动行为。

.PROPERTY FloatBehavior
浮动行为类型 [NuGetVersionFloatBehavior]

.PROPERTY MinVersion
浮动范围的最小版本 [NuGetVersion]

.PROPERTY OriginalReleasePrefix
原始预发布标签前缀 [string]

.PROPERTY IncludePrerelease
是否包含预发布版本 [bool]
#>
class FloatRange {
    [NuGetVersionFloatBehavior] $FloatBehavior
    [NuGetVersion]             $MinVersion
    [string]                   $OriginalReleasePrefix
    [bool]                     $IncludePrerelease

    <#
    .SYNOPSIS
    从浮动版本字符串创建 FloatRange
    
    .DESCRIPTION
    支持的格式：
    - "*"                  → Major（浮动所有）
    - "1.*"                → Minor（浮动次版本号）
    - "1.0.*"              → Patch（浮动补丁号）
    - "1.0.0.*"            → Revision（浮动修订号）
    - "*-*"                → AbsoluteLatest（浮动所有 + 预发布）
    - "1.0.*-*"            → PrereleasePatch
    - "1.*-*"              → PrereleaseMinor
    - "*-rc.*"             → PrereleaseMajor
    - "1.0.0-*"            → Prerelease
    - "1.0.0.*-*"          → PrereleaseRevision
    #>
    FloatRange([string] $FloatVersionString) {
        $Clean = $FloatVersionString.Trim()
        $this.OriginalReleasePrefix = $null
        $this.IncludePrerelease = $false

        # 处理 *-* → AbsoluteLatest
        if ($Clean -eq '*-*') {
            $this.FloatBehavior = [NuGetVersionFloatBehavior]::AbsoluteLatest
            $this.MinVersion = [NuGetVersion]::new('0.0.0-0')
            $this.IncludePrerelease = $true
            $this.OriginalReleasePrefix = ''
            return
        }

        # 处理 * → Major
        if ($Clean -eq '*') {
            $this.FloatBehavior = [NuGetVersionFloatBehavior]::Major
            $this.MinVersion = [NuGetVersion]::new('0.0.0')
            $this.OriginalReleasePrefix = $null
            return
        }

        # 拆分预发布标签
        $DashIndex = $Clean.IndexOf('-')
        $VersionPart = $Clean
        $PreReleasePart = $null
        if ($DashIndex -ge 0) {
            $VersionPart = $Clean.Substring(0, $DashIndex)
            $PreReleasePart = $Clean.Substring($DashIndex + 1)
        }

        # 统计版本段中的 * 位置
        $Segments = $VersionPart -split '\.'
        $StarIndex = -1
        for ($i = 0; $i -lt $Segments.Count; $i++) {
            if ($Segments[$i] -eq '*') { $StarIndex = $i; break }
        }

        # 构建最小版本（将 * 替换为 0）
        $MinVersionString = ($Segments | ForEach-Object { if ($_ -eq '*') { '0' } else { $_ } }) -join '.'
        # 确保至少3段
        $MinSegments = $MinVersionString -split '\.'
        while ($MinSegments.Count -lt 3) { $MinSegments += '0' }
        $MinVersionString = $MinSegments -join '.'

        if ($PreReleasePart) {
            $this.IncludePrerelease = $true

            # 计算发布前缀（去掉末尾 *，对应官方 _releasePrefix）
            $ReleasePrefix = if ($PreReleasePart.EndsWith('*')) {
                $PreReleasePart.Substring(0, $PreReleasePart.Length - 1)
            } else {
                $PreReleasePart
            }
            $this.OriginalReleasePrefix = $ReleasePrefix

            # 构建预发布部分用于 MinVersion（将 * 替换为 0）
            $ReleasePartForVersion = if ($PreReleasePart -eq '*') {
                '0'
            } else {
                $PreReleasePart -replace '\*', '0'
            }
            # 确保预发布标签有效（空标签追加 0，对应官方行为）
            if ($ReleasePartForVersion.Length -eq 0 -or $ReleasePartForVersion.EndsWith('.')) {
                $ReleasePartForVersion += '0'
            }
            $MinVersionString += "-$ReleasePartForVersion"

            if ($PreReleasePart -eq '*') {
                # 根据星号位置确定浮动行为
                # 4段 x.y.z.*-* → PrereleaseRevision
                # 3段 x.y.*-*   → PrereleasePatch
                # 2段 x.*-*     → PrereleaseMinor
                # 1段 *-*       → PrereleaseMajor (但 *-* 已在上面处理)
                # 0段无星号     → Prerelease
                if ($Segments.Count -eq 4 -and $StarIndex -eq 3) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseRevision
                }
                elseif ($Segments.Count -eq 3 -and $StarIndex -eq 2) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleasePatch
                }
                elseif ($Segments.Count -eq 2 -and $StarIndex -eq 1) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMinor
                }
                elseif ($Segments.Count -eq 1 -and $StarIndex -eq 0) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMajor
                }
                else {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::Prerelease
                }
            }
            else {
                # 有具体预发布标签前缀（如 *-rc.*）
                if ($PreReleasePart.Contains('*')) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMajor
                }
                else {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::Prerelease
                }
            }
        }
        else {
            # 无预发布标签，根据星号位置确定浮动行为
            # 4段 x.y.z.* → Revision
            # 3段 x.y.*   → Patch
            # 2段 x.*     → Minor
            # 1段 *       → Major（已在上面处理）
            if ($Segments.Count -eq 4 -and $StarIndex -eq 3) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Revision
            }
            elseif ($Segments.Count -eq 3 -and $StarIndex -eq 2) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Patch
            }
            elseif ($Segments.Count -eq 2 -and $StarIndex -eq 1) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Minor
            }
            elseif ($Segments.Count -eq 1 -and $StarIndex -eq 0) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Major
            }
            else {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::None
            }
        }

        $this.MinVersion = [NuGetVersion]::new($MinVersionString)
    }

    <#
    .SYNOPSIS
    判断给定版本是否满足浮动范围
    #>
    [bool] Satisfies([NuGetVersion] $version) {
        if ($null -eq $version) { return $false }

        $behavior = $this.FloatBehavior

        # AbsoluteLatest 接受所有版本
        if ($behavior -eq [NuGetVersionFloatBehavior]::AbsoluteLatest) {
            return $true
        }

        # Major 浮动接受所有稳定版
        if ($behavior -eq [NuGetVersionFloatBehavior]::Major -and -not $version.IsPrerelease()) {
            return $true
        }

        # 带预发布的浮动行为（对应官方 IncludePrerelease）
        if ($this.IncludePrerelease) {
            $prefix = $this.OriginalReleasePrefix

            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseRevision) {
                # 对应官方：Major/Minor/Patch 匹配 + 前缀检查（或稳定版）
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       $this.MinVersion.Patch -eq $version.Patch -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleasePatch) {
                # 对应官方：Major/Minor 匹配 + 前缀检查（或稳定版）
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMinor) {
                # 对应官方：Major 匹配 + 前缀检查（或稳定版）
                return $this.MinVersion.Major -eq $version.Major -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMajor) {
                # 对应官方：仅前缀检查（或稳定版），不比较核心段
                return (($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                       (-not $version.IsPrerelease())
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Prerelease) {
                # 对应官方：使用 Version 比较器（含 Revision）+ 前缀检查（或稳定版）
                $verCmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MinVersion -ComparisonMode ([VersionComparison]::Version)
                return $verCmp -eq 0 -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
        }
        else {
            # 纯浮动（仅稳定版）
            if ($behavior -eq [NuGetVersionFloatBehavior]::Revision) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       $this.MinVersion.Patch -eq $version.Patch -and
                       -not $version.IsPrerelease()
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Patch) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       -not $version.IsPrerelease()
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Minor) {
                return $this.MinVersion.Major -eq $version.Major -and
                       -not $version.IsPrerelease()
            }
        }

        return $false
    }

    <#
    .SYNOPSIS
    返回浮动范围的字符串表示
    #>
    [string] ToString() {
        $min = $this.MinVersion
        $behavior = $this.FloatBehavior

        # Major
        if ($behavior -eq [NuGetVersionFloatBehavior]::Major) {
            return '*'
        }
        # AbsoluteLatest
        if ($behavior -eq [NuGetVersionFloatBehavior]::AbsoluteLatest) {
            return '*-*'
        }
        # Minor
        if ($behavior -eq [NuGetVersionFloatBehavior]::Minor) {
            return "$($min.Major).*"
        }
        # Patch
        if ($behavior -eq [NuGetVersionFloatBehavior]::Patch) {
            return "$($min.Major).$($min.Minor).*"
        }
        # Revision
        if ($behavior -eq [NuGetVersionFloatBehavior]::Revision) {
            return "$($min.Major).$($min.Minor).$($min.Patch).*"
        }
        # Prerelease
        if ($behavior -eq [NuGetVersionFloatBehavior]::Prerelease) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).$($min.Patch)-$prefix*"
        }
        # PrereleaseRevision
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseRevision) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).$($min.Patch).*-$prefix*"
        }
        # PrereleasePatch
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleasePatch) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).*-$prefix*"
        }
        # PrereleaseMinor
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMinor) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).*-$prefix*"
        }
        # PrereleaseMajor
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMajor) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "*-$prefix*"
        }

        # Default: None or unknown
        return $min.NormalizedVersion
    }
}

<#
.SYNOPSIS
版本范围类（对应官方 NuGet.Versioning.VersionRange）

.DESCRIPTION
表示一个版本范围约束，包含最小/最大版本边界和浮动行为。
支持区间表示法：
- [1.0, 2.0]   → 1.0 ≤ x ≤ 2.0
- (1.0, 2.0)   → 1.0 < x < 2.0
- [1.0, 2.0)   → 1.0 ≤ x < 2.0
- (1.0, 2.0]   → 1.0 < x ≤ 2.0
- [1.0,]        → 1.0 ≤ x
- (,1.0]        → x ≤ 1.0
- 1.0           → 1.0 ≤ x
- (1.0,)        → 1.0 < x
- *             → 所有版本

.PROPERTY MinVersion
最小版本 [NuGetVersion]（$null 表示无下限）

.PROPERTY IsMinInclusive
最小版本是否包含 [bool]

.PROPERTY MaxVersion
最大版本 [NuGetVersion]（$null 表示无上限）

.PROPERTY IsMaxInclusive
最大版本是否包含 [bool]

.PROPERTY FloatRange
浮动行为 [FloatRange]（$null 表示无浮动）

.PROPERTY HasLowerBound
是否有下限 [bool]

.PROPERTY HasUpperBound
是否有上限 [bool]

.PROPERTY HasLowerAndUpperBounds
是否有上下限 [bool]

.PROPERTY IsFloating
是否为浮动版本 [bool]
#>
class VersionRange {
    [NuGetVersion] $MinVersion
    [bool]         $IsMinInclusive
    [NuGetVersion] $MaxVersion
    [bool]         $IsMaxInclusive
    [FloatRange]   $FloatRange

    VersionRange() {
        $this.IsMinInclusive = $true
        $this.IsMaxInclusive = $false
    }

    <#
    .SYNOPSIS
    从版本范围字符串创建 VersionRange

    .DESCRIPTION
    支持两种格式：
    1. 区间表示法：(1.0, 2.0]、[1.0,)、[1.0, 2.0] 等
    2. 浮动表示法：1.0.*、*、*-* 等
    3. 简单版本：1.0 → [1.0,)
    #>
    VersionRange([string] $RangeString) {
        $this.IsMinInclusive = $true
        $this.IsMaxInclusive = $false

        $Clean = $RangeString.Trim()
        if (-not $Clean) {
            throw "版本范围字符串不能为空"
        }

        # 处理纯 * 或 *-*
        if ($Clean -eq '*' -or $Clean -eq '*-*' -or $Clean.Contains('*')) {
            $this.FloatRange = [FloatRange]::new($Clean)
            $this.MinVersion = $this.FloatRange.MinVersion
            $this.IsMinInclusive = $true
            $this.MaxVersion = $null
            return
        }

        # 处理区间表示法：(1.0, 2.0] 等
        if ($Clean[0] -eq '(' -or $Clean[0] -eq '[') {
            $LastChar = $Clean[$Clean.Length - 1]
            if ($LastChar -ne ')' -and $LastChar -ne ']') {
                throw "无效的版本范围 '$Clean'：缺少闭合括号"
            }

            $this.IsMinInclusive = ($Clean[0] -eq '[')
            $this.IsMaxInclusive = ($LastChar -eq ']')

            # 去掉括号
            $Inner = $Clean.Substring(1, $Clean.Length - 2)
            $Parts = $Inner -split ','

            if ($Parts.Count -gt 2) {
                throw "无效的版本范围 '$Clean'：逗号分隔的部分过多"
            }

            # 校验：单段区间必须两端都是 inclusive，如 (1.0]、(1.0)、[1.0) 均非法
            if ($Parts.Count -eq 1 -and -not ($this.IsMinInclusive -and $this.IsMaxInclusive)) {
                throw "无效的版本范围 '$Clean'：单版本区间两端必须都是闭区间（如 [1.0]），不支持 (1.0]、[1.0)、(1.0)"
            }

            $MinStr = $Parts[0].Trim()
            $MaxStr = if ($Parts.Count -gt 1) { $Parts[1].Trim() } else { '' }

            if ($MinStr) {
                # 检查是否含浮动
                if ($MinStr.Contains('*')) {
                    $this.FloatRange = [FloatRange]::new($MinStr)
                    $this.MinVersion = $this.FloatRange.MinVersion
                }
                else {
                    $this.MinVersion = [NuGetVersion]::new($MinStr)
                }
            }
            if ($MaxStr) {
                $this.MaxVersion = [NuGetVersion]::new($MaxStr)
            }

            # 校验：minVersion > maxVersion
            if ($this.MinVersion -and $this.MaxVersion) {
                $minMaxCmp = Compare-NugetVersionInternal -VersionA $this.MinVersion -VersionB $this.MaxVersion -ComparisonMode ([VersionComparison]::VersionRelease)
                if ($minMaxCmp -gt 0) {
                    throw "无效的版本范围 '$Clean'：最小版本大于最大版本"
                }
                # 校验：minVersion == maxVersion 且两端 inclusiveness 不一致
                if ($minMaxCmp -eq 0 -and ($this.IsMinInclusive -xor $this.IsMaxInclusive)) {
                    throw "无效的版本范围 '$Clean'：最小版本等于最大版本时，两端区间开闭必须一致（如 [1.0, 1.0) 非法）"
                }
            }
        }
        else {
            # 简单版本字符串：1.0 → [1.0,)
            if ($Clean.Contains('*')) {
                $this.FloatRange = [FloatRange]::new($Clean)
                $this.MinVersion = $this.FloatRange.MinVersion
            }
            else {
                $this.MinVersion = [NuGetVersion]::new($Clean)
            }
            $this.IsMinInclusive = $true
        }
    }

    <#
    .SYNOPSIS
    是否有下限
    #>
    [bool] HasLowerBound() {
        return $null -ne $this.MinVersion
    }

    <#
    .SYNOPSIS
    是否有上限
    #>
    [bool] HasUpperBound() {
        return $null -ne $this.MaxVersion
    }

    <#
    .SYNOPSIS
    是否同时有上下限
    #>
    [bool] HasLowerAndUpperBounds() {
        return $this.HasLowerBound() -and $this.HasUpperBound()
    }

    <#
    .SYNOPSIS
    是否为浮动版本范围
    #>
    [bool] IsFloating() {
        return $null -ne $this.FloatRange -and
               $this.FloatRange.FloatBehavior -ne [NuGetVersionFloatBehavior]::None
    }

    <#
    .SYNOPSIS
    上下界是否含预发布版本（MinVersion 或 MaxVersion 自身是预发布版）
    .DESCRIPTION
    对应官方 VersionRangeBase.HasPrereleaseBounds。
    若范围自身包含预发布边界，则允许匹配预发布版本。
    #>
    [bool] HasPrereleaseBounds() {
        return ($this.HasLowerBound() -and $this.MinVersion.IsPrerelease()) -or
               ($this.HasUpperBound() -and $this.MaxVersion.IsPrerelease())
    }

    <#
    .SYNOPSIS
    判断给定版本是否满足此范围约束

    .DESCRIPTION
    仅检查上下界约束。浮动范围不在此方法中检查（对应官方 VersionRangeBase.Satisfies）。
    浮动逻辑由 Find-BestMatch / IsBetter 使用。
    使用 VersionComparison.VersionRelease 模式比较（忽略构建元数据）。
    #>
    [bool] Satisfies([NuGetVersion] $version) {
        return $this.Satisfies($version, [VersionComparison]::VersionRelease)
    }

    <#
    .SYNOPSIS
    使用指定比较模式判断给定版本是否满足此范围约束（仅检查上下界）
    #>
    [bool] Satisfies([NuGetVersion] $version, [VersionComparison] $versionComparison) {
        if ($null -eq $version) { return $false }

        # 下界检查
        if ($this.HasLowerBound()) {
            $cmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MinVersion -ComparisonMode $versionComparison
            if ($this.IsMinInclusive) {
                if ($cmp -lt 0) { return $false }
            }
            else {
                if ($cmp -le 0) { return $false }
            }
        }

        # 上界检查
        if ($this.HasUpperBound()) {
            $cmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MaxVersion -ComparisonMode $versionComparison
            if ($this.IsMaxInclusive) {
                if ($cmp -gt 0) { return $false }
            }
            else {
                if ($cmp -ge 0) { return $false }
            }
        }

        # 注意：浮动检查不在 Satisfies 中处理（与官方行为一致）
        # 浮动逻辑由 VersionRange.IsBetter / Find-BestNuGetVersionMatch 使用

        return $true
    }

    <#
    .SYNOPSIS
    返回归一化的版本范围字符串
    #>
    [string] ToString() {
        return $this.ToNormalizedString()
    }

    <#
    .SYNOPSIS
    判断 considering 是否比 current 更适合此版本范围（对应官方 VersionRange.IsBetter）
    
    .DESCRIPTION
    遵循 NuGet 官方 IsBetter 逻辑：
    1. 检查 HasPrereleaseBounds 决定是否允许预发布版本
    2. 检查版本是否满足范围约束
    3. 浮动范围：根据 FloatRange.Satisfies 和 MinVersion 位置决定偏好
    4. 非浮动范围：偏好更低版本
    #>
    [bool] IsBetter([NuGetVersion] $current, [NuGetVersion] $considering) {
        if ($null -eq $considering) { return $false }
        if ($null -ne $current -and [object]::ReferenceEquals($current, $considering)) { return $false }

        # 若范围不含预发布边界且 considering 是预发布版且浮动行为不显式允许预发布 → 拒绝
        if (-not $this.HasPrereleaseBounds() -and $considering.IsPrerelease()) {
            $floatBehavior = if ($this.FloatRange) { $this.FloatRange.FloatBehavior } else { [NuGetVersionFloatBehavior]::None }
            $allowPrerelease = @(
                [NuGetVersionFloatBehavior]::Prerelease,
                [NuGetVersionFloatBehavior]::PrereleaseMajor,
                [NuGetVersionFloatBehavior]::PrereleaseMinor,
                [NuGetVersionFloatBehavior]::PrereleasePatch,
                [NuGetVersionFloatBehavior]::PrereleaseRevision,
                [NuGetVersionFloatBehavior]::AbsoluteLatest
            ) -contains $floatBehavior
            if (-not $allowPrerelease) {
                return $false
            }
        }

        # 版本必须满足范围约束
        if (-not $this.Satisfies($considering)) {
            return $false
        }

        # current 为 null 时，considering 是第一个有效候选
        if ($null -eq $current) {
            return $true
        }

        if ($this.IsFloating()) {
            $curInRange = $this.FloatRange.Satisfies($current)
            $conInRange = $this.FloatRange.Satisfies($considering)

            if ($curInRange -and -not $conInRange) {
                # current 在浮动范围内，保留 current
                return $false
            }
            elseif ($conInRange -and -not $curInRange) {
                # considering 在浮动范围内，替换
                return $true
            }
            elseif ($curInRange -and $conInRange) {
                # 两者都在范围内 → 偏好更高版本
                $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                return $cmp -lt 0
            }
            else {
                # 两者都不在浮动范围内
                $curBelowMin = (Compare-NugetVersionInternal -VersionA $current -VersionB $this.FloatRange.MinVersion -ComparisonMode ([VersionComparison]::VersionRelease)) -lt 0
                $conBelowMin = (Compare-NugetVersionInternal -VersionA $considering -VersionB $this.FloatRange.MinVersion -ComparisonMode ([VersionComparison]::VersionRelease)) -lt 0

                if ($curBelowMin -and -not $conBelowMin) {
                    # considering 高于 MinVersion，偏好它
                    return $true
                }
                elseif (-not $curBelowMin -and $conBelowMin) {
                    # current 高于 MinVersion，保留它
                    return $false
                }
                elseif (-not $curBelowMin -and -not $conBelowMin) {
                    # 两者都高于 MinVersion → 偏好更低版本（靠近范围）
                    $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                    return $cmp -gt 0
                }
                else {
                    # 两者都低于 MinVersion → 偏好更高版本（靠近范围）
                    $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                    return $cmp -lt 0
                }
            }
        }

        # 非浮动范围：偏好更低版本
        $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
        return $cmp -gt 0
    }

    <#
    .SYNOPSIS
    返回归一化的版本范围字符串

    .DESCRIPTION
    格式：[minVersion, maxVersion]
    浮动范围直接输出浮动字符串
    #>
    [string] ToNormalizedString() {
        if ($this.IsFloating()) {
            return $this.FloatRange.ToString()
        }

        if (-not $this.HasLowerBound() -and -not $this.HasUpperBound()) {
            return '(, )'
        }

        $leftBracket  = if ($this.IsMinInclusive) { '[' } else { '(' }
        $rightBracket = if ($this.IsMaxInclusive) { ']' } else { ')' }

        $minStr = if ($this.HasLowerBound()) { $this.MinVersion.NormalizedVersion } else { '' }
        $maxStr = if ($this.HasUpperBound()) { $this.MaxVersion.NormalizedVersion } else { '' }

        return "$leftBracket$minStr, $maxStr$rightBracket"
    }

    <#
    .SYNOPSIS
    返回旧版兼容的版本范围字符串（如 1.0 输出为 "1.0"）
    #>
    [string] ToLegacyString() {
        if ($this.IsFloating()) {
            return $this.FloatRange.ToString()
        }
        return $this.ToNormalizedString()
    }
}

#endregion

#region 版本解析与比较

<#
.SYNOPSIS
解析 NuGet 包版本号（遵循微软 NuGet 官方版本规范，返回 NuGetVersion 对象）

.DESCRIPTION
- 支持 NuGet 核心规则：1-4 段核心数字、v 前缀、版本归一化、SemVer 2.0 预发布/构建元数据
- 不符合规范的版本号直接抛出错误，无 IsValid 字段
- 返回 [NuGetVersion] 对象，可通过属性访问各字段
- 参考文档：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning?tabs=semver20sort#normalized-version-numbers

.PARAMETER VersionString
必选，NuGet 包版本字符串（如：v10.0.17763.1-preview、2.5.8、1.01.0-beta+git789）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "v10.0.17763.1-preview"

OriginalVersion   : v10.0.17763.1-preview
NormalizedVersion : 10.0.17763.1-preview
Major             : 10
Minor             : 0
Patch             : 17763
Revision          : 1
CoreSegments      : {10, 0, 17763, 1}
PreRelease        : preview
BuildMetadata     :
# 说明：解析带v前缀、4段核心数字、单级预发布标签的版本号

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "1.01.0-beta+git789012"

OriginalVersion   : 1.01.0-beta+git789012
NormalizedVersion : 1.1.0-beta
Major             : 1
Minor             : 1
Patch             : 0
Revision          : 0
CoreSegments      : {1, 1, 0, 0}
PreRelease        : beta
BuildMetadata     : git789012
# 说明：解析带前导零、预发布标签+构建元数据的版本号（前导零归一化后移除，构建元数据不出现在归一化版本号中）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "5"

OriginalVersion   : 5
NormalizedVersion : 5.0.0
Major             : 5
Minor             : 0
Patch             : 0
Revision          : 0
CoreSegments      : {5, 0, 0, 0}
PreRelease        :
BuildMetadata     :
# 说明：解析极简1段核心数字的版本号（自动补全为4段，归一化为3段）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "3.2.8-rc.2+20251226.git123"

OriginalVersion   : 3.2.8-rc.2+20251226.git123
NormalizedVersion : 3.2.8-rc.2
Major             : 3
Minor             : 2
Patch             : 8
Revision          : 0
CoreSegments      : {3, 2, 8, 0}
PreRelease        : rc.2
BuildMetadata     : 20251226.git123
# 说明：解析3段核心数字、多级预发布标签、复杂构建元数据的版本号

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "v2.5.0.0-alpha"

OriginalVersion   : v2.5.0.0-alpha
NormalizedVersion : 2.5.0-alpha
Major             : 2
Minor             : 5
Patch             : 0
Revision          : 0
CoreSegments      : {2, 5, 0, 0}
PreRelease        : alpha
BuildMetadata     :
# 说明：解析带v前缀、4段核心数字（第4段为0）的版本号（归一化为3段）
#>
function ConvertTo-NuGetVersion {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VersionString
    )

    process {
        return [NuGetVersion]::new($VersionString)
    }
}



<#
.SYNOPSIS
比较两个 NuGet 版本号（遵循 NuGet 官方 SemVer 2.0.0 排序规则）

.DESCRIPTION
比较两个 NuGet 版本号的优先级。输入可以是原始版本字符串（自动调用 ConvertTo-NuGetVersion 解析）
或 NuGetVersion 对象（兼容旧版哈希表）。

比较规则（参考：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning）：
1. 先比较核心段（Major, Minor, Patch, Revision）从左到右，数值大的优先。
2. 核心段相同时：
   - 稳定版（无 PreRelease） > 预发布版（有 PreRelease）。
   - 两个预发布版按点号分隔逐段比较：
     a. 纯数字段按数值升序比较（小的优先）。
     b. 纯数字段 < 非纯数字段（字母/混合段）。
     c. 两个非纯数字段按不区分大小写的字母顺序比较。
3. 构建元数据（BuildMetadata）不影响版本优先级。

.PARAMETER VersionA
必选，第一个版本字符串或 NuGetVersion 对象（兼容旧版哈希表）

.PARAMETER VersionB
必选，第二个版本字符串或 NuGetVersion 对象（兼容旧版哈希表）

.EXAMPLE
PS> Compare-NugetVersion -VersionA "1.0.1" -VersionB "1.0.1-beta"
1
# 说明：稳定版 1.0.1 优先级高于预发布版 1.0.1-beta

.EXAMPLE
PS> Compare-NugetVersion -VersionA "1.0.1-rc.10" -VersionB "1.0.1-rc.2"
1
# 说明：rc.10 > rc.2（点号分隔的纯数字按数值比较，10 > 2）

.EXAMPLE
PS> Compare-NugetVersion -VersionA "1.0.1-alpha10" -VersionB "1.0.1-alpha2"
-1
# 说明：alpha10 < alpha2（非点号分隔按字母顺序，'1' < '2'）

.EXAMPLE
PS> Compare-NugetVersion -VersionA "2.0.0" -VersionB "2.0.0.0"
0
# 说明：Revision=0 时归一化后等价

.EXAMPLE
PS> Compare-NugetVersion -VersionA "1.0.0+git.hash" -VersionB "1.0.0"
0
# 说明：构建元数据不影响比较，两者等价

.OUTPUTS
[int] - 1：VersionA > VersionB（VersionA 更新）
         0：VersionA = VersionB（相同优先级）
        -1：VersionA < VersionB（VersionB 更新）
#>
function Compare-NugetVersion {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionA,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionB,

        <#
        .SYNOPSIS
        版本比较模式
        #>
        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::Default
    )

    return Compare-NugetVersionInternal -VersionA $VersionA -VersionB $VersionB -ComparisonMode $ComparisonMode
}

<#
.SYNOPSIS
内部版本比较函数（被 VersionRange.Satisfies 等调用）

.DESCRIPTION
统一的版本比较实现，支持四种比较模式：
- Default: 比较核心段 + 预发布标签（忽略构建元数据）
- Version: 仅比较核心段（Major.Minor.Patch.Revision）
- VersionRelease: 同 Default，比较核心段 + 预发布标签
- VersionReleaseMetadata: 比较全部字段（含构建元数据）
#>
function Compare-NugetVersionInternal {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionA,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionB,

        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::Default
    )

    # 步骤1：比较核心段（Major → Minor → Patch → Revision），从左到右数值比较
    if ($VersionA.Major -gt $VersionB.Major) { return 1 }
    if ($VersionA.Major -lt $VersionB.Major) { return -1 }
    if ($VersionA.Minor -gt $VersionB.Minor) { return 1 }
    if ($VersionA.Minor -lt $VersionB.Minor) { return -1 }
    if ($VersionA.Patch -gt $VersionB.Patch) { return 1 }
    if ($VersionA.Patch -lt $VersionB.Patch) { return -1 }
    if ($VersionA.Revision -gt $VersionB.Revision) { return 1 }
    if ($VersionA.Revision -lt $VersionB.Revision) { return -1 }

    # 步骤2：Version 模式 → 到此结束
    if ($ComparisonMode -eq [VersionComparison]::Version) {
        return 0
    }

    # 步骤3：核心段相等，比较预发布标签
    $PreA = $VersionA.PreRelease
    $PreB = $VersionB.PreRelease

    # 3a. 都无预发布标签 → 相等（构建元数据不影响排序，除非 VersionReleaseMetadata）
    if (-not $PreA -and -not $PreB) {
        # VersionReleaseMetadata 模式：比较构建元数据
        if ($ComparisonMode -eq [VersionComparison]::VersionReleaseMetadata) {
            $MetaA = $VersionA.BuildMetadata
            $MetaB = $VersionB.BuildMetadata
            if (-not $MetaA -and -not $MetaB) { return 0 }
            if (-not $MetaA -and $MetaB) { return -1 }
            if ($MetaA -and -not $MetaB) { return 1 }
            return [string]::Compare($MetaA, $MetaB, [System.StringComparison]::OrdinalIgnoreCase)
        }
        return 0
    }

    # 3b. 一个有预发布，一个没有 → 无预发布的版本优先级更高
    if (-not $PreA -and $PreB) {
        return 1
    }
    if ($PreA -and -not $PreB) {
        return -1
    }

    # 3c. 两个都有预发布标签 → 逐段比较
    $PreSegmentsA = $PreA -split '\.'
    $PreSegmentsB = $PreB -split '\.'
    $MaxLen = [Math]::Max($PreSegmentsA.Count, $PreSegmentsB.Count)

    for ($i = 0; $i -lt $MaxLen; $i++) {
        # 某方段数不足时视为 $null
        $SegA = if ($i -lt $PreSegmentsA.Count) { $PreSegmentsA[$i] } else { $null }
        $SegB = if ($i -lt $PreSegmentsB.Count) { $PreSegmentsB[$i] } else { $null }

        # 规则：段数更多且前面均相等 → 段数多的优先级更高
        if ($null -eq $SegA -and $null -ne $SegB) {
            return -1
        }
        if ($null -ne $SegA -and $null -eq $SegB) {
            return 1
        }

        # 判断是否为纯数字段
        $IsNumA = $SegA -match '^\d+$'
        $IsNumB = $SegB -match '^\d+$'

        if ($IsNumA -and $IsNumB) {
            # 同是纯数字 → 数值比较（小的优先）
            $IntA = [int]$SegA
            $IntB = [int]$SegB
            if ($IntA -gt $IntB) { return 1 }
            if ($IntA -lt $IntB) { return -1 }
        }
        elseif ($IsNumA -and -not $IsNumB) {
            # 数字段 < 非数字段
            return -1
        }
        elseif (-not $IsNumA -and $IsNumB) {
            # 非数字段 > 数字段
            return 1
        }
        else {
            # 同是非数字段 → 不区分大小写的字母顺序比较
            $Cmp = [string]::Compare($SegA, $SegB, [System.StringComparison]::OrdinalIgnoreCase)
            if ($Cmp -gt 0) { return 1 }
            if ($Cmp -lt 0) { return -1 }
        }
    }

    # 全部预发布段相等 → 版本相同
    # VersionReleaseMetadata 模式：比较构建元数据
    if ($ComparisonMode -eq [VersionComparison]::VersionReleaseMetadata) {
        $MetaA = $VersionA.BuildMetadata
        $MetaB = $VersionB.BuildMetadata
        if (-not $MetaA -and -not $MetaB) { return 0 }
        if (-not $MetaA -and $MetaB) { return -1 }
        if ($MetaA -and -not $MetaB) { return 1 }
        return [string]::Compare($MetaA, $MetaB, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return 0
}

<#
.SYNOPSIS
尝试解析 NuGet 包版本号（非抛出异常版本，对应官方 TryParse）

.DESCRIPTION
尝试解析版本字符串。成功时返回 $true 并通过 [ref] 参数输出 NuGetVersion 对象；
失败时返回 $false，Version 参数保持 $null。

.PARAMETER VersionString
要解析的版本字符串

.PARAMETER Version
[ref] 引用参数，解析成功时输出 NuGetVersion 对象

.EXAMPLE
PS> $ver = $null
PS> Test-NuGetVersion -VersionString "1.2.3-beta" -Version ([ref]$ver)
True
PS> $ver.NormalizedVersion
1.2.3-beta

.EXAMPLE
PS> Test-NuGetVersion -VersionString "invalid" -Version ([ref]$null)
False
#>
function Test-NuGetVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VersionString,

        [Parameter(Mandatory = $false)]
        [ref]$Version
    )

    try {
        $result = [NuGetVersion]::new($VersionString)
        if ($Version) {
            $Version.Value = $result
        }
        return $true
    }
    catch {
        if ($Version) {
            $Version.Value = $null
        }
        return $false
    }
}

<#
.SYNOPSIS
解析或构造版本范围对象（对应官方 VersionRange.Parse）

.DESCRIPTION
支持以下输入格式：
1. 区间字符串："[1.0, 2.0]"、"(1.0, )"、"[1.0, 2.0)" 等
2. 浮动字符串："1.0.*"、"*"、"*-*" 等
3. 简单版本字符串："1.0" → [1.0, )

.PARAMETER RangeString
版本范围字符串

.EXAMPLE
PS> ConvertTo-VersionRange -RangeString "[1.0, 2.0)"

MinVersion      : 1.0.0
IsMinInclusive  : True
MaxVersion      : 2.0.0
IsMaxInclusive  : False
FloatRange      :

.EXAMPLE
PS> ConvertTo-VersionRange -RangeString "1.0.*"

MinVersion      : 1.0.0
IsMinInclusive  : True
MaxVersion      :
IsMaxInclusive  : False
FloatRange      : 1.0.*
IsFloating      : True

.EXAMPLE
PS> ConvertTo-VersionRange -RangeString "1.0"

MinVersion      : 1.0.0
IsMinInclusive  : True
MaxVersion      :
IsMaxInclusive  : False
# 说明：简单版本 → [1.0, )
#>
function ConvertTo-VersionRange {
    [CmdletBinding()]
    [OutputType([VersionRange])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RangeString
    )

    process {
        return [VersionRange]::new($RangeString)
    }
}

<#
.SYNOPSIS
测试给定版本是否满足版本范围约束（对应官方 VersionRange.Satisfies）

.DESCRIPTION
检查一个 NuGet 版本是否在指定的版本范围内。
支持 VersionComparison 参数控制比较模式。

.PARAMETER Version
必选，要测试的版本字符串或 NuGetVersion 对象

.PARAMETER VersionRange
必选，版本范围字符串或 VersionRange 对象

.PARAMETER ComparisonMode
可选，版本比较模式（默认 VersionRelease）

.EXAMPLE
PS> Test-NuGetVersionInRange -Version "1.5.0" -VersionRange "[1.0, 2.0)"
True

.EXAMPLE
PS> Test-NuGetVersionInRange -Version "2.0.0" -VersionRange "[1.0, 2.0)"
False
#>
function Test-NuGetVersionInRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [VersionRange]$VersionRange,

        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::VersionRelease
    )

    return $VersionRange.Satisfies($Version, $ComparisonMode)
}

<#
.SYNOPSIS
从版本列表中查找最佳匹配版本（对应官方 VersionExtensions.FindBestMatch）

.DESCRIPTION
给定一个版本范围（可含浮动），从候选版本列表中找出最佳匹配版本。
使用 VersionRange.IsBetter() 实现，与官方 NuGet 行为一致：
- 先按 HasPrereleaseBounds 决定是否允许预发布版本
- 再按版本范围约束过滤
- 浮动范围按 FloatRange.Satisfies 和相对位置选择最佳版本
- 非浮动范围选择最低满足条件的版本

.PARAMETER Versions
必选，候选版本号数组（NuGetVersion 对象数组）

.PARAMETER VersionRange
必选，目标版本范围（VersionRange 对象）

.EXAMPLE
PS> Find-BestNuGetVersionMatch -Versions @("1.0.0", "1.1.0", "2.0.0") -VersionRange "1.*"
1.1.0
# 说明：从候选版本中匹配 Minor 浮动 1.*，找到最高的 1.1.0

.EXAMPLE
PS> Find-BestNuGetVersionMatch -Versions @("1.0.0-beta", "1.0.0", "1.1.0") -VersionRange "1.0.*-*"
1.0.0-beta
# 说明：PrereleasePatch 浮动，优先匹配预发布版本
#>
function Find-BestNuGetVersionMatch {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion[]]$Versions,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [VersionRange]$VersionRange
    )

    # 对应官方 FindBestMatch：遍历候选版本，使用 IsBetter 选择最佳
    $bestMatch = $null
    foreach ($v in $Versions) {
        if ($VersionRange.IsBetter($bestMatch, $v)) {
            $bestMatch = $v
        }
    }

    return $bestMatch
}

#endregion
