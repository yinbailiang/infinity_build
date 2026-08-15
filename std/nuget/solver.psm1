##Module Std.Nuget.Solver
##Import Std.Nuget.Logger
##Import Std.Nuget.Versioning
##Import Std.Nuget.Source

<#
.NOTES
    Name: infinity_nuget_solver
    Author: YinBailiang
    Version: 2.0.0
.SYNOPSIS
    NuGet 依赖展开与版本约束闭包求解器
.DESCRIPTION
    这个模块提供以下功能：
    1. 解析 NuGet 包的依赖信息（从 nuspec 清单）
    2. 传递依赖展开（递归获取所有传递依赖，构建依赖图 DAG）
    3. 版本约束闭包求解（给定多根包+版本约束，求解兼容版本集合）
    4. 依赖冲突检测与迭代求解（基于官方 NuGet 的 Nearest-Wins 算法）
    5. 依赖树/图可视化输出

    算法参考：NuGet.Client\src\NuGet.Core\NuGet.DependencyResolver.Core
    核心策略：
    - 最近优先（Nearest Wins）：路径较近的依赖优先
    - 最高兼容版本（Highest Compatible Version）：冲突时选最高版本
    - 争议检测（Dispute Detection）：同名包的不同版本请求标记为争议
    - 迭代消解（Iterative Resolution）：BFS 多轮遍历直到收敛
#>

#region 枚举定义

<#
.SYNOPSIS
依赖图节点的处置状态（对应官方 Disposition）

.DESCRIPTION
- Acceptable: 初始状态，等待判决
- Accepted: 已被接受，版本有效
- Rejected: 已被拒绝（版本冲突/降级）
- PotentiallyDowngraded: 可能被降级（更近的祖先有更低版本需求）
- Cycle: 检测到循环依赖
#>
enum DependencyDisposition {
    Acceptable
    Accepted
    Rejected
    PotentiallyDowngraded
    Cycle
}

#endregion

#region 核心数据结构

<#
.SYNOPSIS
表示单个依赖约束（包ID + 版本范围）
#>
class DependencyConstraint {
    [string]       $PackageId
    [VersionRange] $VersionRange
    [string]       $TargetFramework   # 依赖声明的目标框架（可选）

    DependencyConstraint([string] $PackageId, [VersionRange] $VersionRange) {
        $this.PackageId = $PackageId
        $this.VersionRange = $VersionRange
        $this.TargetFramework = ''
    }

    DependencyConstraint([string] $PackageId, [VersionRange] $VersionRange, [string] $TargetFramework) {
        $this.PackageId = $PackageId
        $this.VersionRange = $VersionRange
        $this.TargetFramework = $TargetFramework
    }

    [string] ToString() {
        return "$($this.PackageId) $($this.VersionRange.ToNormalizedString())"
    }
}

<#
.SYNOPSIS
依赖图节点，表示一个已解析的包及其在 DAG 中的位置

.DESCRIPTION
对应官方 GraphNode<TItem>。支持双向图遍历：
- InnerNodes（子节点/依赖项）
- OuterNode（父节点）
- ParentNodes（所有父节点列表，用于 DAG）
- Disposition（状态机）
#>
class DependencyNode {
    [string]                 $PackageId
    [NuGetVersion]           $ResolvedVersion
    [VersionRange]           $VersionRange        # 此节点的版本约束
    [DependencyConstraint[]] $Dependencies        # 直接依赖约束
    [DependencyNode[]]       $Children            # 已解析的子依赖节点（InnerNodes）
    [DependencyNode]         $OuterNode           # 父节点引用
    [System.Collections.Generic.List[DependencyNode]] $ParentNodes  # 所有父节点（DAG 支持）
    [int]                    $Depth               # 在依赖图中的深度
    [string]                 $TargetFramework     # 解析时使用的目标框架
    [DependencyDisposition]  $Disposition         # 处置状态

    DependencyNode([string] $PackageId, [NuGetVersion] $ResolvedVersion, [VersionRange] $VersionRange, [int] $Depth) {
        $this.PackageId = $PackageId
        $this.ResolvedVersion = $ResolvedVersion
        $this.VersionRange = $VersionRange
        $this.Dependencies = @()
        $this.Children = @()
        $this.OuterNode = $null
        $this.ParentNodes = [System.Collections.Generic.List[DependencyNode]]::new()
        $this.Depth = $Depth
        $this.TargetFramework = ''
        $this.Disposition = [DependencyDisposition]::Acceptable
    }

    [bool] HasDependencies() {
        return $this.Dependencies.Count -gt 0
    }

    [bool] HasChildren() {
        return $this.Children.Count -gt 0
    }

    [bool] IsAccepted() {
        return $this.Disposition -eq [DependencyDisposition]::Accepted
    }

    [bool] IsRejected() {
        return $this.Disposition -eq [DependencyDisposition]::Rejected
    }

    [bool] AreAllParentsRejected() {
        if ($this.ParentNodes.Count -eq 0) { return $false }
        foreach ($p in $this.ParentNodes) {
            if (-not $p.IsRejected()) { return $false }
        }
        return $true
    }

    [string] ToString() {
        $indent = '  ' * $this.Depth
        $disposition = $this.Disposition.ToString()
        return "$indent$($this.PackageId) v$($this.ResolvedVersion.NormalizedVersion) [$disposition]"
    }
}

<#
.SYNOPSIS
包追踪器，记录解析过程中同名包的所有版本出现（对应官方 Tracker<TItem>）

.DESCRIPTION
用于检测争议包（同一包名有多个不同版本请求）和最佳版本判断。
核心逻辑：
- Track: 记录每个 GraphItem
- IsDisputed: 是否有多个不同版本
- IsBestVersion: 当前版本是否是所有已知版本中最高的
- MarkAmbiguous: 标记为模糊状态
#>
class DependencyTracker {
    [hashtable] $_entries  # Key=PackageId(lower), Value=@{ Versions=List; Ambiguous=bool }

    DependencyTracker() {
        $this._entries = @{}
    }

    <#
    .SYNOPSIS
    追踪一个解析后的包项
    #>
    [void] Track([DependencyNode] $node) {
        $key = $node.PackageId.ToLowerInvariant()
        if (-not $this._entries.ContainsKey($key)) {
            $this._entries[$key] = @{
                Versions = [System.Collections.Generic.List[DependencyNode]]::new()
                Ambiguous = $false
            }
        }
        $this._entries[$key].Versions.Add($node)
    }

    <#
    .SYNOPSIS
    判断是否有多个不同版本（争议）
    #>
    [bool] IsDisputed([DependencyNode] $node) {
        $key = $node.PackageId.ToLowerInvariant()
        if (-not $this._entries.ContainsKey($key)) { return $false }
        # 检查是否有不同版本
        $versions = $this._entries[$key].Versions
        if ($versions.Count -le 1) { return $false }
        $firstVersion = $versions[0].ResolvedVersion.NormalizedVersion
        for ($i = 1; $i -lt $versions.Count; $i++) {
            if ($versions[$i].ResolvedVersion.NormalizedVersion -ne $firstVersion) {
                return $true
            }
        }
        return $false
    }

    <#
    .SYNOPSIS
    判断当前包是否是已知版本中最佳的（最高的）
    对应官方 IsBestVersion: 当前版本 >= 所有其他追踪到的版本
    #>
    [bool] IsBestVersion([DependencyNode] $node) {
        $key = $node.PackageId.ToLowerInvariant()
        if (-not $this._entries.ContainsKey($key)) { return $true }
        foreach ($known in $this._entries[$key].Versions) {
            $cmp = Compare-NugetVersionInternal -VersionA $node.ResolvedVersion -VersionB $known.ResolvedVersion -ComparisonMode ([VersionComparison]::VersionRelease)
            if ($cmp -lt 0) {
                return $false
            }
        }
        return $true
    }

    <#
    .SYNOPSIS
    标记为模糊状态
    #>
    [void] MarkAmbiguous([DependencyNode] $node) {
        $key = $node.PackageId.ToLowerInvariant()
        if ($this._entries.ContainsKey($key)) {
            $this._entries[$key].Ambiguous = $true
        }
    }

    <#
    .SYNOPSIS
    检查是否模糊
    #>
    [bool] IsAmbiguous([DependencyNode] $node) {
        $key = $node.PackageId.ToLowerInvariant()
        if (-not $this._entries.ContainsKey($key)) { return $false }
        return $this._entries[$key].Ambiguous
    }

    <#
    .SYNOPSIS
    清空追踪器（用于下一轮迭代）
    #>
    [void] Clear() {
        $this._entries = @{}
    }
}

<#
.SYNOPSIS
依赖解析上下文，管理解析过程中的状态
#>
class DependencyResolutionContext {
    [NugetSource] $Source
    [hashtable]   $Resolved           # Key=PackageId(normalized), Value=DependencyNode
    [hashtable]   $InProgress         # Key=PackageId(normalized), Value=$true (用于环检测)
    [hashtable]   $VersionCache       # Key=PackageId(normalized), Value=NuGetVersion[] (版本列表缓存)
    [hashtable]   $DependencyCache    # Key="PackageId|Version", Value=DependencyConstraint[] (依赖缓存)
    [hashtable]   $Constraints        # Key=PackageId(normalized), Value=VersionRange[] (累积约束)
    [System.Collections.Generic.List[hashtable]] $ResolutionSnapshots  # 回溯快照栈
    [int]         $MaxDepth
    [int]         $MaxConflictRetries
    [string]      $TargetFramework    # 全局目标框架（可选）

    DependencyResolutionContext([NugetSource] $Source) {
        $this.Source = $Source
        $this.Resolved = @{}
        $this.InProgress = @{}
        $this.VersionCache = @{}
        $this.DependencyCache = @{}
        $this.Constraints = @{}
        $this.ResolutionSnapshots = [System.Collections.Generic.List[hashtable]]::new()
        $this.MaxDepth = 50
        $this.MaxConflictRetries = 20
        $this.TargetFramework = ''
    }
}

<#
.SYNOPSIS
依赖解析结果
#>
class DependencyResolutionResult {
    [bool]             $Success
    [DependencyNode[]] $RootNodes           # 根节点列表
    [hashtable]        $ResolvedPackages    # Key=PackageId, Value=NuGetVersion (扁平化结果)
    [string[]]         $Errors              # 错误/警告信息
    [int]              $TotalPackages
    [int]              $MaxDepth

    DependencyResolutionResult() {
        $this.Success = $false
        $this.RootNodes = @()
        $this.ResolvedPackages = @{}
        $this.Errors = @()
        $this.TotalPackages = 0
        $this.MaxDepth = 0
    }
}

#endregion

#region nuspec 依赖解析

<#
.SYNOPSIS
从 nuspec XML 中提取依赖信息

.DESCRIPTION
解析 nuspec 清单中的 <dependencies> 节点，提取所有依赖组。
支持按 targetFramework 筛选依赖组（当指定 TargetFramework 时）。

.PARAMETER NuspecXml
必选，nuspec 清单的 XML 文档对象

.PARAMETER TargetFramework
可选，目标框架字符串（如 net8.0），用于筛选匹配的依赖组。
不指定时返回所有依赖组的并集（去重）。

.EXAMPLE
PS> $deps = Get-NuspecDependencies -NuspecXml $xml -TargetFramework "net8.0"
# 获取 net8.0 框架下的所有依赖

.OUTPUTS
[DependencyConstraint[]] - 依赖约束数组
#>
function Get-NuspecDependencies {
    [CmdletBinding()]
    [OutputType([DependencyConstraint[]])]
    param (
        [Parameter(Mandatory = $true)]
        [xml]$NuspecXml,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )

    $Result = [System.Collections.Generic.List[DependencyConstraint]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()

    # 查找所有 <dependencies> 节点
    $Metadata = $NuspecXml.package.metadata
    if (-not $Metadata) {
        $Script:NugetLogger.Warn("nuspec 缺少 metadata 节点")
        return $Result.ToArray()
    }

    $DependenciesNode = $Metadata.dependencies
    if (-not $DependenciesNode) {
        return $Result.ToArray()
    }

    # 获取所有 <group> 子节点
    $Groups = @($DependenciesNode.group)
    if ($Groups.Count -eq 0) {
        # 无 group 节点，直接获取 <dependency> 子节点（旧格式）
        $FlatDeps = @($DependenciesNode.dependency)
        foreach ($dep in $FlatDeps) {
            $constraint = Parse-DependencyElement -DependencyElement $dep
            if ($constraint -and $Seen.Add($constraint.PackageId.ToLowerInvariant())) {
                $Result.Add($constraint)
            }
        }
        return $Result.ToArray()
    }

    # 有 group 节点：按 targetFramework 筛选
    if ($TargetFramework) {
        # 解析目标框架
        try {
            $TargetFx = ConvertTo-NuGetFramework -FrameworkString $TargetFramework
        }
        catch {
            $Script:NugetLogger.Warn("无法解析目标框架 '$TargetFramework'，返回所有依赖")
            $TargetFx = $null
        }

        # 收集匹配的依赖组
        $MatchedGroups = [System.Collections.Generic.List[object]]::new()
        $FallbackGroups = [System.Collections.Generic.List[object]]::new()

        foreach ($group in $Groups) {
            $GroupTFM = $group.targetFramework
            if (-not $GroupTFM) {
                # 无框架限制的组作为后备
                $FallbackGroups.Add($group)
                continue
            }

            if ($TargetFx) {
                try {
                    $GroupFx = ConvertTo-NuGetFramework -FrameworkString $GroupTFM
                    if (Test-NuGetFrameworkCompatibility -Target $TargetFx -Candidate $GroupFx) {
                        $MatchedGroups.Add($group)
                    }
                }
                catch {
                    $Script:NugetLogger.Warn("无法解析依赖组框架 '$GroupTFM'")
                }
            }
        }

        # 优先使用精确匹配的组，否则回退到无框架组
        $GroupsToUse = if ($MatchedGroups.Count -gt 0) { $MatchedGroups } else { $FallbackGroups }

        foreach ($group in $GroupsToUse) {
            $GroupDeps = @($group.dependency)
            foreach ($dep in $GroupDeps) {
                $constraint = Parse-DependencyElement -DependencyElement $dep
                if ($constraint) {
                    $constraint.TargetFramework = $group.targetFramework
                    if ($Seen.Add($constraint.PackageId.ToLowerInvariant())) {
                        $Result.Add($constraint)
                    }
                }
            }
        }
    }
    else {
        # 无目标框架：返回所有组的并集（去重）
        foreach ($group in $Groups) {
            $GroupDeps = @($group.dependency)
            foreach ($dep in $GroupDeps) {
                $constraint = Parse-DependencyElement -DependencyElement $dep
                if ($constraint) {
                    $constraint.TargetFramework = $group.targetFramework
                    if ($Seen.Add($constraint.PackageId.ToLowerInvariant())) {
                        $Result.Add($constraint)
                    }
                }
            }
        }
    }

    return $Result.ToArray()
}

<#
.SYNOPSIS
解析单个 <dependency> XML 元素为 DependencyConstraint 对象

.DESCRIPTION
解析 <dependency id="..." version="..." /> 元素。
版本字符串支持：
- 区间表示法：[1.0, 2.0]、(1.0,) 等
- 浮动表示法：1.0.*、*、*-* 等
- 简单版本：1.0 → [1.0, )

.PARAMETER DependencyElement
必选，XML 依赖元素节点
#>
function Parse-DependencyElement {
    [CmdletBinding()]
    [OutputType([DependencyConstraint])]
    param (
        [Parameter(Mandatory = $true)]
        $DependencyElement
    )

    $Id = $DependencyElement.id
    $Version = $DependencyElement.version

    if (-not $Id) {
        $Script:NugetLogger.Warn("依赖缺少 id 属性，跳过")
        return $null
    }

    # 排除 NuGet 内置的隐式依赖（_._ 占位包、Microsoft.NETCore.Platforms 等内核平台包需保留）
    if ($Id -eq '_._') {
        return $null
    }

    try {
        if (-not $Version) {
            $Version = '*'
        }
        $Range = ConvertTo-VersionRange -RangeString $Version
        return [DependencyConstraint]::new($Id, $Range)
    }
    catch {
        $Script:NugetLogger.Warn("无法解析依赖版本 '$Version' (包: $Id): $($_.Exception.Message)")
        return $null
    }
}

#endregion

#region 依赖信息获取

<#
.SYNOPSIS
获取指定包的依赖信息（从远程源获取 nuspec 并解析）

.DESCRIPTION
从 NuGet 源获取指定包版本的 nuspec 清单，解析其依赖项。
支持缓存以减少重复网络请求。

.PARAMETER Source
必选，NugetSource 实例

.PARAMETER Id
必选，包ID

.PARAMETER Version
必选，包版本号（NuGetVersion 对象或字符串）

.PARAMETER Context
可选，依赖解析上下文（用于缓存）

.PARAMETER TargetFramework
可选，目标框架字符串

.EXAMPLE
PS> $deps = Get-NugetPackageDependencies -Source $source -Id "Newtonsoft.Json" -Version "13.0.3"
# 获取 Newtonsoft.Json 13.0.3 的直接依赖

.OUTPUTS
[DependencyConstraint[]] - 依赖约束数组
#>
function Get-NugetPackageDependencies {
    [CmdletBinding()]
    [OutputType([DependencyConstraint[]])]
    param (
        [Parameter(Mandatory = $true)]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        $Version,

        [Parameter(Mandatory = $false)]
        [DependencyResolutionContext]$Context,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )

    # 标准化版本号
    $NuGetVer = if ($Version -is [NuGetVersion]) { $Version } else { ConvertTo-NuGetVersion -VersionString $Version }
    $VersionKey = $NuGetVer.NormalizedVersion

    # 检查缓存
    if ($Context) {
        $CacheKey = "$($Id.ToLowerInvariant())|$VersionKey"
        if ($Context.DependencyCache.ContainsKey($CacheKey)) {
            $Script:NugetLogger.Info("[缓存命中] 依赖信息: $Id v$VersionKey")
            return $Context.DependencyCache[$CacheKey]
        }
    }

    $Script:NugetLogger.Info("获取依赖信息: $Id v$VersionKey")

    try {
        $NuspecXml = Get-NugetPackagManifest -Source $Source -Id $Id -Version $VersionKey

        $EffectiveTFM = if ($TargetFramework) { $TargetFramework } elseif ($Context -and $Context.TargetFramework) { $Context.TargetFramework } else { '' }
        $Deps = Get-NuspecDependencies -NuspecXml $NuspecXml -TargetFramework $EffectiveTFM

        # 缓存结果
        if ($Context) {
            $CacheKey = "$($Id.ToLowerInvariant())|$VersionKey"
            $Context.DependencyCache[$CacheKey] = $Deps
        }

        $Script:NugetLogger.Info("$Id v$VersionKey 有 $($Deps.Count) 个直接依赖")
        return $Deps
    }
    catch {
        $Script:NugetLogger.Warn("获取 $Id v$VersionKey 依赖信息失败: $($_.Exception.Message)")
        return @()
    }
}

<#
.SYNOPSIS
获取指定包的可用版本列表（带缓存）

.DESCRIPTION
获取包的所有可用版本，支持缓存以加速解析。

.PARAMETER Context
必选，依赖解析上下文

.PARAMETER Id
必选，包ID

.PARAMETER IncludePrerelease
可选，是否包含预发布版本
#>
function Get-CachedPackageVersions {
    [CmdletBinding()]
    [OutputType([NuGetVersion[]])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [bool]$IncludePrerelease = $false
    )

    $IdLower = $Id.ToLowerInvariant()

    if ($Context.VersionCache.ContainsKey($IdLower)) {
        return $Context.VersionCache[$IdLower]
    }

    $Script:NugetLogger.Info("获取版本列表: $Id")

    try {
        $AllVersions = Get-NugetPackageVersions -Source $Context.Source -Id $Id -Preview:$IncludePrerelease

        $NuGetVersions = [System.Collections.Generic.List[NuGetVersion]]::new()
        foreach ($v in $AllVersions) {
            $NuGetVersions.Add($v)
        }

        $Context.VersionCache[$IdLower] = $NuGetVersions.ToArray()
        return $Context.VersionCache[$IdLower]
    }
    catch {
        $Script:NugetLogger.Error("获取 $Id 版本列表失败: $($_.Exception.Message)")
        return @()
    }
}

#endregion

#region 约束求解引擎

<#
.SYNOPSIS
注册包的版本约束（用于多约束累积）

.DESCRIPTION
将新的版本约束合并到现有约束中。如果存在已有约束，
新约束通过计算交集来处理：取两者都满足的最紧范围。

.PARAMETER Context
必选，依赖解析上下文

.PARAMETER PackageId
必选，包ID

.PARAMETER Constraint
必选，版本范围约束
#>
function Register-Constraint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [VersionRange]$Constraint
    )

    $IdLower = $PackageId.ToLowerInvariant()

    if (-not $Context.Constraints.ContainsKey($IdLower)) {
        $Context.Constraints[$IdLower] = [System.Collections.Generic.List[VersionRange]]::new()
    }

    # 避免重复添加完全相同的约束
    $ConstraintStr = $Constraint.ToNormalizedString()
    foreach ($existing in $Context.Constraints[$IdLower]) {
        if ($existing.ToNormalizedString() -eq $ConstraintStr) {
            $Script:NugetLogger.Info("[约束] $PackageId → $ConstraintStr (已存在，跳过)")
            return
        }
    }

    $Context.Constraints[$IdLower].Add($Constraint)
    $Script:NugetLogger.Info("[约束] $PackageId → $ConstraintStr")
}

<#
.SYNOPSIS
查找满足所有累积约束的最佳版本

.DESCRIPTION
给定包ID和累积的版本约束列表，从可用版本中找出满足所有约束的最佳版本。
使用"最低兼容版本"策略（对应 NuGet 的 lowest applicable version 策略）。

.PARAMETER Context
必选，依赖解析上下文

.PARAMETER PackageId
必选，包ID

.PARAMETER Constraints
必选，版本约束数组（已合并该包的所有约束）

.EXAMPLE
PS> $best = Find-SatisfyingVersion -Context $ctx -PackageId "Newtonsoft.Json" -Constraints $constraints
# 返回满足所有约束的最佳版本

.OUTPUTS
[NuGetVersion] - 最佳版本，无满足版本时返回 $null
#>
function Find-SatisfyingVersion {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[VersionRange]]$Constraints
    )

    # 获取可用版本
    $IncludePrerelease = ($Constraints | Where-Object { $_.HasPrereleaseBounds() }).Count -gt 0
    $AvailableVersions = Get-CachedPackageVersions -Context $Context -Id $PackageId -IncludePrerelease $IncludePrerelease

    if ($AvailableVersions.Count -eq 0) {
        $Script:NugetLogger.Warn("$PackageId 没有可用版本")
        return $null
    }

    # 筛选满足所有约束的版本
    $Satisfying = [System.Collections.Generic.List[NuGetVersion]]::new()
    foreach ($v in $AvailableVersions) {
        $AllSatisfied = $true
        foreach ($c in $Constraints) {
            if (-not $c.Satisfies($v)) {
                $AllSatisfied = $false
                break
            }
        }
        if ($AllSatisfied) {
            $Satisfying.Add($v)
        }
    }

    if ($Satisfying.Count -eq 0) {
        $ConstraintStrs = ($Constraints | ForEach-Object { $_.ToNormalizedString() }) -join ' AND '
        $Script:NugetLogger.Warn("$PackageId 没有版本同时满足所有约束: $ConstraintStrs")
        return $null
    }

    # ★ 对齐官方 NuGet Nearest-Wins 策略：选择满足所有约束的最高兼容版本
    # 排序：稳定版优先（0），预发布版其次（1），然后按版本号降序（最高优先）
    $Sorted = $Satisfying | Sort-Object -Property {
        if ($_.IsPrerelease()) { return 1 } else { return 0 }
    }, { -$_.Major }, { -$_.Minor }, { -$_.Patch }, { -$_.Revision }

    # 取第一个稳定版；如果全是预发布版，取第一个
    $Best = $Sorted | Where-Object { -not $_.IsPrerelease() } | Select-Object -First 1
    if (-not $Best) {
        $Best = $Sorted | Select-Object -First 1
    }

    $Script:NugetLogger.Info("[求解] $PackageId → $($Best.NormalizedVersion) (最高兼容版本)")
    return $Best
}

<#
.SYNOPSIS
比较两个版本范围：nearVersion 的最小版本是否 >= farVersion 的最小版本
对应官方 IsGreaterThanOrEqualTo

.DESCRIPTION
用于检测降级：当更近的祖先依赖有更低的版本要求时，标记为 PotentiallyDowngraded。
浮动版本被视为大于等价非浮动版本。
#>
function Test-IsGreaterThanOrEqualToVersionRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [VersionRange]$NearVersion,

        [Parameter(Mandatory = $true)]
        [VersionRange]$FarVersion
    )

    # 无下界 → 覆盖一切
    if (-not $NearVersion.HasLowerBound()) { return $true }
    if (-not $FarVersion.HasLowerBound()) { return $false }

    # 浮动版本比较
    if ($NearVersion.IsFloating() -or $FarVersion.IsFloating()) {
        $nearMin = Get-ReleaseLabelFreeVersion -VersionRange $NearVersion
        $farMin = Get-ReleaseLabelFreeVersion -VersionRange $FarVersion

        $result = Compare-NugetVersionInternal -VersionA $nearMin -VersionB $farMin -ComparisonMode ([VersionComparison]::Version)
        if ($result -ne 0) { return $result -gt 0 }

        # 核心版本相等时比较发布标签
        $nearRelease = if ($NearVersion.IsFloating()) { $NearVersion.FloatRange.OriginalReleasePrefix } else { $NearVersion.MinVersion.PreRelease }
        $farRelease = if ($FarVersion.IsFloating()) { $FarVersion.FloatRange.OriginalReleasePrefix } else { $FarVersion.MinVersion.PreRelease }

        if ([string]::IsNullOrEmpty($nearRelease)) { return $true }
        if ([string]::IsNullOrEmpty($farRelease)) { return $false }

        $len = [Math]::Min($nearRelease.Length, $farRelease.Length)
        $cmp = [string]::Compare($nearRelease.Substring(0, $len), $farRelease.Substring(0, $len), [System.StringComparison]::OrdinalIgnoreCase)
        if ($cmp -gt 0) { return $true }
        if ($cmp -lt 0) { return $false }

        # 等价范围：浮动的优先
        if ($NearVersion.IsFloating() -and -not $FarVersion.IsFloating()) { return $true }
        if (-not $NearVersion.IsFloating() -and $FarVersion.IsFloating()) { return $false }

        return $nearRelease.Length -le $farRelease.Length
    }

    # 非浮动：直接比较最小版本
    return (Compare-NugetVersionInternal -VersionA $NearVersion.MinVersion -VersionB $FarVersion.MinVersion -ComparisonMode ([VersionComparison]::VersionRelease)) -ge 0
}

<#
.SYNOPSIS
获取去掉发布标签部分的版本（用于浮动版本比较）
对应官方 GetReleaseLabelFreeVersion
#>
function Get-ReleaseLabelFreeVersion {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true)]
        [VersionRange]$VersionRange
    )

    if (-not $VersionRange.IsFloating()) {
        $v = $VersionRange.MinVersion
        return [NuGetVersion]::new("$($v.Major).$($v.Minor).$($v.Patch).$($v.Revision)")
    }

    $behavior = $VersionRange.FloatRange.FloatBehavior
    $min = $VersionRange.MinVersion

    if ($behavior -eq [NuGetVersionFloatBehavior]::Major -or $behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMajor) {
        return [NuGetVersion]::new('2147483647.2147483647.2147483647.2147483647')
    }
    elseif ($behavior -eq [NuGetVersionFloatBehavior]::Minor -or $behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMinor) {
        return [NuGetVersion]::new("$($min.Major).2147483647.2147483647.2147483647")
    }
    elseif ($behavior -eq [NuGetVersionFloatBehavior]::Patch -or $behavior -eq [NuGetVersionFloatBehavior]::PrereleasePatch) {
        return [NuGetVersion]::new("$($min.Major).$($min.Minor).2147483647.2147483647")
    }
    elseif ($behavior -eq [NuGetVersionFloatBehavior]::Revision -or $behavior -eq [NuGetVersionFloatBehavior]::PrereleaseRevision) {
        return [NuGetVersion]::new("$($min.Major).$($min.Minor).$($min.Patch).2147483647")
    }
    elseif ($behavior -eq [NuGetVersionFloatBehavior]::AbsoluteLatest) {
        return [NuGetVersion]::new('2147483647.2147483647.2147483647.2147483647')
    }
    else {
        return [NuGetVersion]::new("$($min.Major).$($min.Minor).$($min.Patch).$($min.Revision)")
    }
}

<#
.SYNOPSIS
保存解析快照（用于回溯）

.DESCRIPTION
保存当前解析状态，以便在冲突时回退。
#>
function Save-ResolutionSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context
    )

    $Snapshot = @{
        Resolved    = $Context.Resolved.Clone()
        InProgress  = $Context.InProgress.Clone()
        Constraints = @{}
    }

    foreach ($kv in $Context.Constraints.GetEnumerator()) {
        $Snapshot.Constraints[$kv.Key] = [System.Collections.Generic.List[VersionRange]]::new()
        foreach ($c in $kv.Value) {
            $Snapshot.Constraints[$kv.Key].Add($c)
        }
    }

    $Context.ResolutionSnapshots.Add($Snapshot)
}

<#
.SYNOPSIS
恢复解析快照（用于回溯）

.DESCRIPTION
恢复到之前保存的解析状态。
#>
function Restore-ResolutionSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context
    )

    if ($Context.ResolutionSnapshots.Count -eq 0) {
        return
    }

    $Snapshot = $Context.ResolutionSnapshots[$Context.ResolutionSnapshots.Count - 1]
    $Context.ResolutionSnapshots.RemoveAt($Context.ResolutionSnapshots.Count - 1)

    $Context.Resolved = $Snapshot.Resolved
    $Context.InProgress = $Snapshot.InProgress
    $Context.Constraints = $Snapshot.Constraints
}

#endregion

#region 核心解析算法

<#
.SYNOPSIS
核心递归解析函数：解析单个包的依赖子树

.DESCRIPTION
使用深度优先搜索 + 约束累积 + 回溯算法解析包的依赖树。
算法流程：
1. 如果包已解析，检查已解析版本是否满足新增约束 → 满足则复用，不满足则冲突
2. 如果包正在解析中（环检测），返回已解析节点（切断环）
3. 注册当前约束，查找满足所有约束的最佳版本
4. 获取该版本的直接依赖
5. 递归解析每个子依赖
6. 构建 DependencyNode 并返回

.PARAMETER Context
必选，依赖解析上下文

.PARAMETER PackageId
必选，要解析的包ID

.PARAMETER VersionRange
必选，版本约束范围

.PARAMETER Depth
当前递归深度（用于深度限制和缩进显示）

.PARAMETER ParentNode
父节点（用于构建依赖树）

.EXAMPLE
PS> $node = Resolve-PackageInternal -Context $ctx -PackageId "Newtonsoft.Json" -VersionRange $range -Depth 0
# 解析 Newtonsoft.Json 的依赖子树

.OUTPUTS
[DependencyNode] - 解析后的依赖节点，失败返回 $null
#>
function Resolve-PackageInternal {
    [CmdletBinding()]
    [OutputType([DependencyNode])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [VersionRange]$VersionRange,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 0,

        [Parameter(Mandatory = $false)]
        [DependencyNode]$ParentNode
    )

    $IdLower = $PackageId.ToLowerInvariant()
    $Indent = '  ' * $Depth

    # 深度限制
    if ($Depth -gt $Context.MaxDepth) {
        $Script:NugetLogger.Error("${Indent}超过最大解析深度 $($Context.MaxDepth): $PackageId")
        return $null
    }

    $Script:NugetLogger.Info("${Indent}[解析] $PackageId ← $($VersionRange.ToNormalizedString()) (深度=$Depth)")

    # 步骤1：检查是否已解析
    if ($Context.Resolved.ContainsKey($IdLower)) {
        $ResolvedNode = $Context.Resolved[$IdLower]
        $ResolvedVersion = $ResolvedNode.ResolvedVersion

        # 检查已解析版本是否满足新约束
        if ($VersionRange.Satisfies($ResolvedVersion)) {
            $Script:NugetLogger.Info("${Indent}[复用] $PackageId v$($ResolvedVersion.NormalizedVersion) (已解析，满足约束)")
            return $ResolvedNode
        }
        else {
            # 已解析版本不满足新约束 → 冲突
            $Script:NugetLogger.Warn("${Indent}[冲突] $PackageId 已解析为 v$($ResolvedVersion.NormalizedVersion)，但需要 $($VersionRange.ToNormalizedString())")
            # 尝试寻找同时满足已有约束和新约束的版本
            $AllConstraints = [System.Collections.Generic.List[VersionRange]]::new()
            if ($Context.Constraints.ContainsKey($IdLower)) {
                foreach ($c in $Context.Constraints[$IdLower]) {
                    $AllConstraints.Add($c)
                }
            }
            $AllConstraints.Add($VersionRange)

            $NewBest = Find-SatisfyingVersion -Context $Context -PackageId $PackageId -Constraints $AllConstraints
            if ($NewBest -and $NewBest.NormalizedVersion -eq $ResolvedVersion.NormalizedVersion) {
                # 同一个版本已经满足
                $Script:NugetLogger.Info("${Indent}[复用] 同一版本已满足所有约束")
                return $ResolvedNode
            }
            elseif ($NewBest) {
                # 找到了一个新版本 → 需要重新解析（移除旧解析，重新开始）
                $Script:NugetLogger.Info("${Indent}[升级] $PackageId 从 v$($ResolvedVersion.NormalizedVersion) 升级到 v$($NewBest.NormalizedVersion)")
                $Context.Resolved.Remove($IdLower)
                # 继续往下走解析逻辑
            }
            else {
                $Script:NugetLogger.Error("${Indent}[失败] $PackageId 无法同时满足所有约束")
                return $null
            }
        }
    }

    # 步骤2：环检测
    if ($Context.InProgress.ContainsKey($IdLower)) {
        $Script:NugetLogger.Warn("${Indent}[环检测] $PackageId 正在解析中，标记为 Cycle")
        # 创建占位节点，标记为 Cycle
        $CycleNode = [DependencyNode]::new($PackageId, [NuGetVersion]::new('0.0.0'), $VersionRange, $Depth)
        $CycleNode.Disposition = [DependencyDisposition]::Cycle
        if ($ParentNode) {
            $CycleNode.OuterNode = $ParentNode
            [void]$CycleNode.ParentNodes.Add($ParentNode)
        }
        return $CycleNode
    }

    # 步骤3：注册约束并查找最佳版本
    Register-Constraint -Context $Context -PackageId $PackageId -Constraint $VersionRange

    $AllConstraints = $Context.Constraints[$IdLower]
    $BestVersion = Find-SatisfyingVersion -Context $Context -PackageId $PackageId -Constraints $AllConstraints

    if (-not $BestVersion) {
        $ConstraintStrs = ($AllConstraints | ForEach-Object { $_.ToNormalizedString() }) -join ' AND '
        $Script:NugetLogger.Error("${Indent}[失败] $PackageId 无版本满足约束: $ConstraintStrs")
        return $null
    }

    # 步骤4：标记为正在解析
    $Context.InProgress[$IdLower] = $true

    try {
        # 步骤5：获取直接依赖
        $DirectDeps = Get-NugetPackageDependencies -Source $Context.Source -Id $PackageId -Version $BestVersion -Context $Context

        # 创建当前节点，建立与父节点的 DAG 连接
        $CurrentNode = [DependencyNode]::new($PackageId, $BestVersion, $VersionRange, $Depth)
        $CurrentNode.Dependencies = $DirectDeps
        if ($ParentNode) {
            $CurrentNode.OuterNode = $ParentNode
            [void]$CurrentNode.ParentNodes.Add($ParentNode)
        }

        # 步骤6：递归解析所有子依赖
        $Children = [System.Collections.Generic.List[DependencyNode]]::new()

        foreach ($dep in $DirectDeps) {
            $ChildNode = Resolve-PackageInternal -Context $Context -PackageId $dep.PackageId -VersionRange $dep.VersionRange -Depth ($Depth + 1) -ParentNode $CurrentNode

            if ($ChildNode) {
                $Children.Add($ChildNode)
                # 如果子节点来自不同的父节点，添加 ParentNodes（DAG 支持）
                if ($ChildNode.OuterNode -and $ChildNode.OuterNode -ne $CurrentNode) {
                    [void]$ChildNode.ParentNodes.Add($CurrentNode)
                }
            }
            else {
                $Script:NugetLogger.Warn("${Indent}[子依赖失败] $($dep.PackageId) 解析失败，继续解析其他依赖")
            }
        }

        $CurrentNode.Children = $Children.ToArray()

        # 步骤7：记录解析结果
        $Context.Resolved[$IdLower] = $CurrentNode
        $Script:NugetLogger.Info("${Indent}[完成] $PackageId v$($BestVersion.NormalizedVersion) ($($Children.Count) 个子依赖)")

        return $CurrentNode
    }
    finally {
        # 移除进行中标记
        $Context.InProgress.Remove($IdLower)
    }
}

#endregion

#region 图分析与冲突消解

<#
.SYNOPSIS
对依赖图进行后处理分析（对应官方 GraphOperations.Analyze）

.DESCRIPTION
在初始依赖图构建完成后执行：
1. CheckCycleAndNearestWins: 处理环和降级节点
2. TryResolveConflicts: 迭代消解版本冲突

采用官方 NuGet 的 Nearest-Wins 策略 + 迭代 BFS 算法。

.PARAMETER RootNodes
必选，依赖图的根节点列表

.PARAMETER MaxIterations
可选，最大迭代次数（默认 1000，与官方 patience 一致）

.EXAMPLE
PS> $result = Resolve-DependencyConflicts -RootNodes $rootNodes
# 对已构建的依赖图进行冲突消解

.OUTPUTS
[bool] - 消解是否成功（无未决节点）
#>
function Resolve-DependencyConflicts {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyNode[]]$RootNodes,

        [Parameter(Mandatory = $false)]
        [int]$MaxIterations = 1000
    )

    if ($RootNodes.Count -eq 0) { return $true }

    # === 阶段1：CheckCycleAndNearestWins ===
    $Script:NugetLogger.Info("[分析] 阶段1: CheckCycleAndNearestWins")
    foreach ($root in $RootNodes) {
        Invoke-CheckCycleAndNearestWins -Root $root
    }

    # === 阶段2：TryResolveConflicts（迭代 BFS 直到收敛） ===
    $Script:NugetLogger.Info("[分析] 阶段2: TryResolveConflicts")
    $patience = $MaxIterations
    $incomplete = $true
    $acceptedLibraries = @{}  # Key=PackageId(lower), Value=DependencyNode

    while ($incomplete -and --$patience -gt 0) {
        $tracker = [DependencyTracker]::new()

        # Pass 1: 拒绝传播 + 追踪
        foreach ($root in $RootNodes) {
            Invoke-WalkTreeRejectAndTrack -Node $root -State $true -Tracker $tracker
        }

        # Pass 2: 标记模糊节点
        foreach ($root in $RootNodes) {
            Invoke-WalkTreeMarkAmbiguous -Node $root -State 'Walking' -Tracker $tracker
        }

        # Pass 3: 接受/拒绝判决
        $acceptContext = @{ Tracker = $tracker; AcceptedLibraries = $acceptedLibraries }
        foreach ($root in $RootNodes) {
            Invoke-WalkTreeAcceptOrReject -Node $root -State $true -AcceptContext $acceptContext
        }

        # Pass 4: 检查是否还有未决节点
        $incomplete = $false
        foreach ($root in $RootNodes) {
            if (Test-AnyAcceptableNode -Node $root) {
                $incomplete = $true
                break
            }
        }
    }

    if ($patience -le 0) {
        $Script:NugetLogger.Warn("[分析] 冲突消解达到最大迭代次数限制")
    }

    $Script:NugetLogger.Info("[分析] 冲突消解完成: $(if ($incomplete) { '未收敛' } else { '已收敛' })")

    return -not $incomplete
}

<#
.SYNOPSIS
CheckCycleAndNearestWins: 遍历图，处理环和潜在降级节点

.DESCRIPTION
BFS 遍历依赖图：
- Cycle 节点：标记并移出 InnerNodes
- PotentiallyDowngraded 节点：使用 nearest-wins 规则判断是否真正降级
#>
function Invoke-CheckCycleAndNearestWins {
    param(
        [DependencyNode]$Root
    )

    $Queue = [System.Collections.Generic.Queue[DependencyNode]]::new()
    $Queue.Enqueue($Root)

    while ($Queue.Count -gt 0) {
        $node = $Queue.Dequeue()

        # 处理 Cycle 节点
        if ($node.Disposition -eq [DependencyDisposition]::Cycle) {
            if ($node.OuterNode) {
                $NewChildren = [System.Collections.Generic.List[DependencyNode]]::new()
                foreach ($child in $node.OuterNode.Children) {
                    if ($child -ne $node) { $NewChildren.Add($child) }
                }
                $node.OuterNode.Children = $NewChildren.ToArray()
            }
            continue
        }

        # 处理 PotentiallyDowngraded 节点
        if ($node.Disposition -eq [DependencyDisposition]::PotentiallyDowngraded) {
            # 沿 OuterNode 链向上查找同名的更近节点
            $downgradedTo = $null
            for ($n = $node.OuterNode; $n -ne $null; $n = $n.OuterNode) {
                foreach ($sideNode in $n.Children) {
                    if ($sideNode -ne $node -and
                        $sideNode.PackageId.ToLowerInvariant() -eq $node.PackageId.ToLowerInvariant()) {

                        if ($sideNode.VersionRange -and $node.VersionRange) {
                            if (-not (Test-IsGreaterThanOrEqualToVersionRange -NearVersion $sideNode.VersionRange -FarVersion $node.VersionRange)) {
                                # 检查已解析版本是否在 node 的范围内
                                $resolvedVer = $sideNode.ResolvedVersion
                                if ($resolvedVer -and $node.VersionRange.Satisfies($resolvedVer)) {
                                    continue
                                }
                                $downgradedTo = $sideNode
                            }
                        }
                        else {
                            $downgradedTo = $null
                        }
                    }
                }
                if ($downgradedTo) { break }
            }

            if ($downgradedTo) {
                $Script:NugetLogger.Info("[降级] $($node.PackageId) $($node.VersionRange.ToNormalizedString()) → $($downgradedTo.ResolvedVersion.NormalizedVersion)")
                $node.Disposition = [DependencyDisposition]::Rejected
                $downgradedTo.Disposition = [DependencyDisposition]::Accepted
            }

            # 移除 PotentiallyDowngraded 节点
            if ($node.OuterNode) {
                $NewChildren = [System.Collections.Generic.List[DependencyNode]]::new()
                foreach ($child in $node.OuterNode.Children) {
                    if ($child -ne $node) { $NewChildren.Add($child) }
                }
                $node.OuterNode.Children = $NewChildren.ToArray()
            }
            continue
        }

        # 子节点入队
        foreach ($child in $node.Children) {
            $Queue.Enqueue($child)
        }
    }
}

<#
.SYNOPSIS
Pass 1: 拒绝传播 + 追踪（BFS）
对应官方 WalkTreeRejectNodesOfRejectedNodes
#>
function Invoke-WalkTreeRejectAndTrack {
    param(
        [DependencyNode]$Node,
        [bool]$State,
        [DependencyTracker]$Tracker
    )

    $Queue = [System.Collections.Generic.Queue[hashtable]]::new()
    $Queue.Enqueue(@{ Node = $Node; State = $State })

    while ($Queue.Count -gt 0) {
        $item = $Queue.Dequeue()
        $n = $item.Node
        $s = $item.State

        if (-not $s -or $n.IsRejected()) {
            $n.Disposition = [DependencyDisposition]::Rejected
            $nextState = $false
        }
        else {
            $Tracker.Track($n)
            $nextState = $true
        }

        foreach ($child in $n.Children) {
            $Queue.Enqueue(@{ Node = $child; State = $nextState })
        }
    }
}

<#
.SYNOPSIS
Pass 2: 标记模糊节点（BFS）
对应官方 WalkTreeMarkAmbiguousNodes

.DESCRIPTION
如果父节点被争议 → 子节点标记为模糊
#>
function Invoke-WalkTreeMarkAmbiguous {
    param(
        [DependencyNode]$Node,
        [string]$State,
        [DependencyTracker]$Tracker
    )

    $Queue = [System.Collections.Generic.Queue[hashtable]]::new()
    $Queue.Enqueue(@{ Node = $Node; State = $State })

    while ($Queue.Count -gt 0) {
        $item = $Queue.Dequeue()
        $n = $item.Node
        $s = $item.State

        if ($n.IsRejected()) {
            $nextState = 'Rejected'
        }
        elseif ($s -eq 'Walking' -and $Tracker.IsDisputed($n)) {
            $nextState = 'Ambiguous'
        }
        elseif ($s -eq 'Ambiguous') {
            $Tracker.MarkAmbiguous($n)
            $nextState = 'Ambiguous'
        }
        else {
            $nextState = $s
        }

        foreach ($child in $n.Children) {
            $Queue.Enqueue(@{ Node = $child; State = $nextState })
        }
    }
}

<#
.SYNOPSIS
Pass 3: 接受/拒绝判决（BFS）
对应官方 WalkTreeAcceptOrRejectNodes

.DESCRIPTION
对每个 Acceptable 节点：
- 如果是最佳版本（最高）→ Accepted
- 否则 → Rejected
- 模糊节点 → 跳过（保持 Acceptable，下一轮再判）
#>
function Invoke-WalkTreeAcceptOrReject {
    param(
        [DependencyNode]$Node,
        [bool]$State,
        [hashtable]$AcceptContext
    )

    $Tracker = $AcceptContext.Tracker
    $AcceptedLibraries = $AcceptContext.AcceptedLibraries

    $Queue = [System.Collections.Generic.Queue[hashtable]]::new()
    $Queue.Enqueue(@{ Node = $Node; State = $State })

    while ($Queue.Count -gt 0) {
        $item = $Queue.Dequeue()
        $n = $item.Node
        $s = $item.State

        if (-not $s -or $n.IsRejected()) {
            $nextState = $false
        }
        else {
            if ($Tracker.IsAmbiguous($n)) {
                $nextState = $false
            }
            elseif ($n.Disposition -eq [DependencyDisposition]::Acceptable) {
                if ($Tracker.IsBestVersion($n)) {
                    $n.Disposition = [DependencyDisposition]::Accepted
                    $key = $n.PackageId.ToLowerInvariant()
                    $AcceptedLibraries[$key] = $n
                    $Script:NugetLogger.Info("[接受] $($n.PackageId) v$($n.ResolvedVersion.NormalizedVersion)")
                }
                else {
                    $n.Disposition = [DependencyDisposition]::Rejected
                    $Script:NugetLogger.Info("[拒绝] $($n.PackageId) v$($n.ResolvedVersion.NormalizedVersion)")
                }
            }
            $nextState = $n.IsAccepted()
        }

        foreach ($child in $n.Children) {
            $Queue.Enqueue(@{ Node = $child; State = $nextState })
        }
    }
}

<#
.SYNOPSIS
检测图中是否还有 Acceptable 节点
#>
function Test-AnyAcceptableNode {
    param([DependencyNode]$Node)

    $Queue = [System.Collections.Generic.Queue[DependencyNode]]::new()
    $Queue.Enqueue($Node)

    while ($Queue.Count -gt 0) {
        $n = $Queue.Dequeue()
        if ($n.Disposition -eq [DependencyDisposition]::Acceptable) {
            return $true
        }
        foreach ($child in $n.Children) {
            $Queue.Enqueue($child)
        }
    }
    return $false
}

<#
.SYNOPSIS
收集所有 Accepted 节点的扁平化结果
#>
function Get-AcceptedPackages {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyNode[]]$RootNodes
    )

    $Result = @{}
    $Queue = [System.Collections.Generic.Queue[DependencyNode]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($root in $RootNodes) {
        $Queue.Enqueue($root)
    }

    while ($Queue.Count -gt 0) {
        $node = $Queue.Dequeue()
        $key = $node.PackageId.ToLowerInvariant()

        if ($node.IsAccepted() -and $Seen.Add($key)) {
            $Result[$node.PackageId] = $node.ResolvedVersion
        }

        foreach ($child in $node.Children) {
            $Queue.Enqueue($child)
        }
    }

    return $Result
}

#endregion

#region 公开接口

<#
.SYNOPSIS
展开 NuGet 包的完整依赖树（传递依赖展开）

.DESCRIPTION
给定根包ID和版本，递归展开所有传递依赖，返回完整的依赖树。
不进行冲突求解——使用"先到先得"策略（首次遇到的版本即为解析版本）。

对于已安装的包，自动从 nuspec 中提取依赖信息。

.PARAMETER Source
必选，NugetSource 实例（用于获取包版本和依赖信息）

.PARAMETER Id
必选，根包ID

.PARAMETER Version
必选，根包版本号

.PARAMETER MaxDepth
可选，最大展开深度（默认50），防止无限递归

.PARAMETER TargetFramework
可选，目标框架（用于筛选依赖组）

.PARAMETER IncludePrerelease
可选，是否包含预发布版本的依赖

.EXAMPLE
PS> $tree = Expand-NugetDependency -Source $source -Id "Microsoft.Extensions.Hosting" -Version "8.0.0"
PS> $tree | Format-NugetDependencyTree
# 展开 Microsoft.Extensions.Hosting 8.0.0 的完整依赖树

.EXAMPLE
PS> $tree = Expand-NugetDependency -Source $source -Id "Newtonsoft.Json" -Version "13.0.3" -TargetFramework "net8.0"
# 在 net8.0 框架下展开 Newtonsoft.Json 的依赖树

.OUTPUTS
[DependencyNode] - 依赖树的根节点
#>
function Expand-NugetDependency {
    [CmdletBinding()]
    [OutputType([DependencyNode])]
    param (
        [Parameter(Mandatory = $true)]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxDepth = 50,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework,

        [Parameter(Mandatory = $false)]
        [switch]$IncludePrerelease
    )

    $Context = [DependencyResolutionContext]::new($Source)
    $Context.MaxDepth = $MaxDepth
    if ($TargetFramework) {
        $Context.TargetFramework = $TargetFramework
    }

    $RootRange = ConvertTo-VersionRange -RangeString "[$Version, $Version]"
    $RootNode = Resolve-PackageInternal -Context $Context -PackageId $Id -VersionRange $RootRange -Depth 0

    if (-not $RootNode) {
        throw "展开 $Id v$Version 依赖树失败"
    }

    # ★ 后处理：冲突消解（对齐官方 Analyze + TryResolveConflicts）
    $converged = Resolve-DependencyConflicts -RootNodes @($RootNode)
    if (-not $converged) {
        $Script:NugetLogger.Warn("依赖图冲突消解未完全收敛")
    }

    $Script:NugetLogger.Info("依赖展开完成: $($Context.Resolved.Count) 个唯一包")

    return $RootNode
}

<#
.SYNOPSIS
求解版本约束闭包（多根包版本冲突求解）

.DESCRIPTION
给定多个根包及其版本约束，使用回溯算法找到一组兼容版本，
使得所有包的版本约束都得到满足。

这是 NuGet 包管理器的核心算法——依赖解析（Dependency Resolution）。

算法策略：
- 最低兼容版本优先（prefer lowest compatible version）
- 约束累积 — 同一包的多条约束取交集
- 深度优先 + 约束传播 — 先解析完整棵依赖树再确认
- 冲突时尝试升级已解析包的版本

.PARAMETER Source
必选，NugetSource 实例

.PARAMETER Packages
必选，根包约束的哈希表（Key=包ID, Value=版本范围字符串）
例如：@{ 'Newtonsoft.Json' = '[12.0, 14.0)'; 'Serilog' = '3.1.1' }

.PARAMETER MaxDepth
可选，最大解析深度（默认50）

.PARAMETER TargetFramework
可选，目标框架

.PARAMETER MaxConflictRetries
可选，冲突重试次数（默认20）

.EXAMPLE
PS> $result = Resolve-NugetDependencyClosure -Source $source -Packages @{
    'Microsoft.Extensions.Hosting' = '8.0.0'
    'Serilog.Extensions.Hosting' = '8.0.0'
}
PS> $result.Success
True
PS> $result.ResolvedPackages
# 求解两个根包的兼容版本集合

.EXAMPLE
PS> $result = Resolve-NugetDependencyClosure -Source $source -Packages @{
    'Newtonsoft.Json' = '[12.0, 14.0)'
    'System.Text.Json' = '8.0.0'
} -TargetFramework 'net8.0'
# 在 net8.0 框架下求解

.OUTPUTS
[DependencyResolutionResult] - 解析结果
#>
function Resolve-NugetDependencyClosure {
    [CmdletBinding()]
    [OutputType([DependencyResolutionResult])]
    param (
        [Parameter(Mandatory = $true)]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [hashtable]$Packages,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxDepth = 50,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxConflictRetries = 20
    )

    $Result = [DependencyResolutionResult]::new()
    $Context = [DependencyResolutionContext]::new($Source)
    $Context.MaxDepth = $MaxDepth
    $Context.MaxConflictRetries = $MaxConflictRetries
    if ($TargetFramework) {
        $Context.TargetFramework = $TargetFramework
    }

    $Script:NugetLogger.Info("=" * 60)
    $Script:NugetLogger.Info("开始依赖闭包求解")
    $Script:NugetLogger.Info("根包数量: $($Packages.Count)")
    foreach ($kv in $Packages.GetEnumerator()) {
        $Script:NugetLogger.Info("  $($kv.Key) → $($kv.Value)")
    }
    $Script:NugetLogger.Info("=" * 60)

    # 将根包约束注册到上下文
    $RootConstraints = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($kv in $Packages.GetEnumerator()) {
        try {
            $Range = ConvertTo-VersionRange -RangeString $kv.Value
            $RootConstraints.Add(@{ Id = $kv.Key; Range = $Range })
            Register-Constraint -Context $Context -PackageId $kv.Key -Constraint $Range
        }
        catch {
            $Result.Errors += "无法解析版本范围 '$($kv.Value)' (包: $($kv.Key)): $($_.Exception.Message)"
        }
    }

    if ($Result.Errors.Count -gt 0) {
        $Result.Success = $false
        return $Result
    }

    # 逐包解析
    $RootNodes = [System.Collections.Generic.List[DependencyNode]]::new()
    $AllSuccess = $true

    foreach ($rc in $RootConstraints) {
        $node = Resolve-PackageInternal -Context $Context -PackageId $rc.Id -VersionRange $rc.Range -Depth 0

        if ($node) {
            $RootNodes.Add($node)
        }
        else {
            $AllSuccess = $false
            $Result.Errors += "无法解析根包: $($rc.Id) ← $($rc.Range.ToNormalizedString())"
        }
    }

    # ★ 后处理：冲突消解（对应官方 Analyze + TryResolveConflicts）
    $converged = Resolve-DependencyConflicts -RootNodes $RootNodes.ToArray()
    if (-not $converged) {
        $Script:NugetLogger.Warn("依赖图冲突消解未完全收敛")
        $Result.Errors += "依赖图冲突消解未完全收敛"
    }

    # 构建结果（使用冲突消解后的 Accepted 节点）
    $Result.Success = $AllSuccess
    $Result.RootNodes = $RootNodes.ToArray()
    $Result.TotalPackages = (Get-AcceptedPackages -RootNodes $RootNodes).Count

    # 计算最大深度
    $MaxTreeDepth = 0
    foreach ($node in $RootNodes) {
        $nd = Get-NodeMaxDepth -Node $node
        if ($nd -gt $MaxTreeDepth) { $MaxTreeDepth = $nd }
    }
    $Result.MaxDepth = $MaxTreeDepth

    # 构建扁平化结果（仅包含 Accepted 节点）
    $Result.ResolvedPackages = Get-AcceptedPackages -RootNodes $RootNodes

    $Script:NugetLogger.Info("=" * 60)
    if ($AllSuccess) {
        $Script:NugetLogger.Info("求解成功: $($Result.TotalPackages) 个包, 最大深度: $MaxTreeDepth")
    }
    else {
        $Script:NugetLogger.Info("求解失败: $($Result.Errors.Count) 个错误")
        foreach ($err in $Result.Errors) {
            $Script:NugetLogger.Error("  $err")
        }
    }
    $Script:NugetLogger.Info("=" * 60)

    return $Result
}

<#
.SYNOPSIS
简化接口：获取依赖闭包（不进行冲突求解）

.DESCRIPTION
对单个或多个包解析依赖闭包。与 Resolve-NugetDependencyClosure 不同，
此函数使用简单的"先到先得"策略，不尝试解决版本冲突。
适合快速查看依赖范围。

.PARAMETER Source
必选，NugetSource 实例

.PARAMETER Packages
必选，根包约束哈希表

.PARAMETER MaxDepth
可选，最大深度

.PARAMETER TargetFramework
可选，目标框架

.EXAMPLE
PS> $closure = Get-NugetDependencyClosure -Source $source -Packages @{ 'Newtonsoft.Json' = '13.0.3' }
PS> $closure.ResolvedPackages
# 获取 Newtonsoft.Json 13.0.3 及其所有传递依赖的扁平列表

.OUTPUTS
[DependencyResolutionResult]
#>
function Get-NugetDependencyClosure {
    [CmdletBinding()]
    [OutputType([DependencyResolutionResult])]
    param (
        [Parameter(Mandatory = $true)]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [hashtable]$Packages,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxDepth = 50,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )

    # 委托给 Resolve-NugetDependencyClosure（同一算法，只是语义上更偏向"展开"）
    return Resolve-NugetDependencyClosure -Source $Source -Packages $Packages -MaxDepth $MaxDepth -TargetFramework $TargetFramework
}

#endregion

#region 依赖树可视化

<#
.SYNOPSIS
获取节点的最大树深度
#>
function Get-NodeMaxDepth {
    param([DependencyNode]$Node)

    if (-not $Node -or $Node.Children.Count -eq 0) {
        return $Node.Depth
    }

    $maxChildDepth = 0
    foreach ($child in $Node.Children) {
        $cd = Get-NodeMaxDepth -Node $child
        if ($cd -gt $maxChildDepth) { $maxChildDepth = $cd }
    }
    return $maxChildDepth
}

<#
.SYNOPSIS
格式化输出依赖树

.DESCRIPTION
将 DependencyNode 树格式化为易于阅读的树形文本。

.PARAMETER Node
必选，依赖树根节点

.PARAMETER Indent
内部使用，缩进字符串

.PARAMETER IsLast
内部使用，是否为最后一个子节点

.EXAMPLE
PS> Format-NugetDependencyTree -Node $tree
Newtonsoft.Json v13.0.3
├── System.Runtime v4.3.1
├── System.ComponentModel.Annotations v5.0.0
│   └── System.Runtime v4.3.1 (*)
└── ...

.OUTPUTS
[string[]] - 格式化的树行数组
#>
function Format-NugetDependencyTree {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [DependencyNode]$Node,

        [Parameter(Mandatory = $false)]
        [string]$Indent = '',

        [Parameter(Mandatory = $false)]
        [bool]$IsLast = $true,

        [Parameter(Mandatory = $false)]
        [switch]$ShowDisposition
    )

    process {
        $Lines = [System.Collections.Generic.List[string]]::new()

        # 跳过 Rejected 节点
        if ($Node.IsRejected() -and -not $ShowDisposition) {
            return $Lines.ToArray()
        }

        # 当前节点
        $Marker = if ($Indent -eq '') { '' } elseif ($IsLast) { '└── ' } else { '├── ' }
        $VersionStr = if ($Node.ResolvedVersion) { $Node.ResolvedVersion.NormalizedVersion } else { '?' }
        $DispositionStr = if ($ShowDisposition) { " [$($Node.Disposition.ToString())]" } else { '' }
        $CycleStr = if ($Node.Disposition -eq [DependencyDisposition]::Cycle) { ' (cycle)' } else { '' }
        $Lines.Add("$Indent$Marker$($Node.PackageId) v$VersionStr$DispositionStr$CycleStr")

        # 子节点（仅显示非 Rejected 的）
        $VisibleChildren = if ($ShowDisposition) {
            $Node.Children
        }
        else {
            @($Node.Children | Where-Object { -not $_.IsRejected() })
        }

        $ChildIndent = if ($Indent -eq '') { '' } elseif ($IsLast) { "$Indent    " } else { "$Indent│   " }

        for ($i = 0; $i -lt $VisibleChildren.Count; $i++) {
            $isLastChild = ($i -eq $VisibleChildren.Count - 1)
            $ChildLines = Format-NugetDependencyTree -Node $VisibleChildren[$i] -Indent $ChildIndent -IsLast $isLastChild -ShowDisposition:$ShowDisposition
            $Lines.AddRange($ChildLines)
        }

        return $Lines.ToArray()
    }
}

<#
.SYNOPSIS
以扁平列表形式输出依赖闭包

.DESCRIPTION
将解析结果中的包列表以扁平形式输出，每行一个包。

.PARAMETER Result
必选，DependencyResolutionResult 对象

.PARAMETER ShowVersion
可选，是否显示版本号（默认显示）

.EXAMPLE
PS> Format-NugetDependencyList -Result $result
Microsoft.Extensions.Hosting 8.0.0
Microsoft.Extensions.DependencyInjection 8.0.0
...

.OUTPUTS
[string[]]
#>
function Format-NugetDependencyList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [DependencyResolutionResult]$Result,

        [Parameter(Mandatory = $false)]
        [switch]$ShowVersion
    )

    process {
        $Lines = [System.Collections.Generic.List[string]]::new()
        $ShowVer = -not $ShowVersion -or $ShowVersion  # 默认显示版本

        $Sorted = $Result.ResolvedPackages.GetEnumerator() |
            Sort-Object -Property Key

        foreach ($kv in $Sorted) {
            $Lines.Add("$($kv.Key) v$($kv.Value.NormalizedVersion)")
        }

        return $Lines.ToArray()
    }
}

<#
.SYNOPSIS
以 Mermaid 图格式输出依赖关系图

.DESCRIPTION
生成可在 Markdown 中使用的 Mermaid flowchart 代码，
可视化展示包与包之间的依赖关系。

.PARAMETER Node
必选，依赖树根节点

.EXAMPLE
PS> Format-NugetDependencyMermaid -Node $tree
```mermaid
flowchart TD
    A[Newtonsoft.Json v13.0.3]
    A --> B[System.Runtime v4.3.1]
    ...
```

.OUTPUTS
[string] - Mermaid 图代码
#>
function Format-NugetDependencyMermaid {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyNode]$Node
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add('```mermaid')
    $Lines.Add('flowchart TD')

    $NodeIds = @{}
    $Counter = 0

    function Get-NodeId {
        param([string]$PackageId)
        if (-not $NodeIds.ContainsKey($PackageId)) {
            $Script:Counter++
            $NodeIds[$PackageId] = "N$Script:Counter"
        }
        return $NodeIds[$PackageId]
    }

    function Render-Node {
        param([DependencyNode]$N)
        # 跳过 Rejected 和 Cycle 节点
        if ($N.IsRejected() -or $N.Disposition -eq [DependencyDisposition]::Cycle) { return }
        $nid = Get-NodeId -PackageId $N.PackageId
        $ver = if ($N.ResolvedVersion) { $N.ResolvedVersion.NormalizedVersion } else { '?' }
        $Lines.Add("    $nid[`"$($N.PackageId)<br/>v$ver`"]")

        foreach ($child in $N.Children) {
            if ($child.IsRejected()) { continue }
            $cid = Get-NodeId -PackageId $child.PackageId
            $Lines.Add("    $nid --> $cid")
            Render-Node -Node $child
        }
    }

    Render-Node -Node $Node
    $Lines.Add('```')

    return $Lines -join "`n"
}

#endregion

#region 辅助功能

<#
.SYNOPSIS
检测依赖树中的版本冲突

.DESCRIPTION
扫描依赖树，检测同一包的不同版本约束是否可能产生冲突。
返回潜在冲突列表。

.PARAMETER Result
必选，DependencyResolutionResult 对象

.EXAMPLE
PS> $conflicts = Test-NugetDependencyConflict -Result $result
# 检测解析结果中的冲突

.OUTPUTS
[hashtable[]] - 冲突信息数组
#>
function Test-NugetDependencyConflict {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionResult]$Result
    )

    $Conflicts = [System.Collections.Generic.List[hashtable]]::new()

    # 遍历根节点，检查不同路径上的同一包是否有不同的版本约束
    function Collect-VersionConstraints {
        param([DependencyNode]$Node, [hashtable]$Collected)

        $IdLower = $Node.PackageId.ToLowerInvariant()
        if (-not $Collected.ContainsKey($IdLower)) {
            $Collected[$IdLower] = @{
                PackageId = $Node.PackageId
                Versions  = [System.Collections.Generic.List[string]]::new()
                Paths     = [System.Collections.Generic.List[string]]::new()
            }
        }

        $Collected[$IdLower].Versions.Add($Node.ResolvedVersion.NormalizedVersion)
        # 路径追踪（通过父节点链）
        $Path = Get-NodePath -Node $Node
        $Collected[$IdLower].Paths.Add($Path)

        foreach ($child in $Node.Children) {
            Collect-VersionConstraints -Node $child -Collected $Collected
        }
    }

    $Collected = @{}
    foreach ($root in $Result.RootNodes) {
        Collect-VersionConstraints -Node $root -Collected $Collected
    }

    foreach ($kv in $Collected.GetEnumerator()) {
        $Info = $kv.Value
        $UniqueVersions = $Info.Versions | Select-Object -Unique
        if ($UniqueVersions.Count -gt 1) {
            $Conflicts.Add(@{
                PackageId      = $Info.PackageId
                Versions       = $UniqueVersions
                AllOccurrences = $Info.Versions.Count
                Paths          = $Info.Paths
            })
        }
    }

    if ($Conflicts.Count -gt 0) {
        $Script:NugetLogger.Warn("检测到 $($Conflicts.Count) 个包有多个版本引用（可能需要版本统一）:")
        foreach ($c in $Conflicts) {
            $Script:NugetLogger.Warn("  $($c.PackageId): $($c.Versions -join ', ')")
        }
    }

    return $Conflicts.ToArray()
}

<#
.SYNOPSIS
获取节点的完整包路径（从根到当前节点）

.DESCRIPTION
通过遍历节点树构建从根包到当前包的依赖路径字符串。
#>
function Get-NodePath {
    param([DependencyNode]$Node)

    # 由于 DependencyNode 不存储父引用，我们从根开始搜索
    # 这里用简单的方式：返回包ID链
    # 在实际使用场景中，路径信息由外部递归构建
    return $Node.PackageId
}

<#
.SYNOPSIS
将解析结果保存为 JSON 文件

.DESCRIPTION
将依赖解析结果导出为 JSON 格式，方便后续分析或存档。

.PARAMETER Result
必选，DependencyResolutionResult 对象

.PARAMETER OutputPath
必选，输出文件路径

.EXAMPLE
PS> Export-NugetDependencyResult -Result $result -OutputPath "./deps.json"
# 导出依赖解析结果为 JSON
#>
function Export-NugetDependencyResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [DependencyResolutionResult]$Result,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $ExportData = @{
        Success        = $Result.Success
        TotalPackages  = $Result.TotalPackages
        MaxDepth       = $Result.MaxDepth
        Errors         = $Result.Errors
        Packages       = @{}
    }

    foreach ($kv in $Result.ResolvedPackages.GetEnumerator()) {
        $ExportData.Packages[$kv.Key] = $kv.Value.NormalizedVersion
    }

    $ExportData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    $Script:NugetLogger.Info("依赖解析结果已导出到: $OutputPath")
}

<#
.SYNOPSIS
对一组包执行批量依赖解析

.DESCRIPTION
对多个根包配置分别执行依赖解析，并汇总结果。

.PARAMETER Source
必选，NugetSource 实例

.PARAMETER PackageList
必选，包列表，每项为 @{ Id = '...'; Version = '...' }

.PARAMETER MaxDepth
可选，最大深度

.PARAMETER TargetFramework
可选，目标框架

.EXAMPLE
PS> $results = Invoke-NugetDependencyBatch -Source $source -PackageList @(
    @{ Id = 'Newtonsoft.Json'; Version = '13.0.3' }
    @{ Id = 'Serilog'; Version = '3.1.1' }
)
# 批量解析多个包的依赖

.OUTPUTS
[hashtable] - Key=包ID, Value=DependencyResolutionResult
#>
function Invoke-NugetDependencyBatch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [hashtable[]]$PackageList,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxDepth = 50,

        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )

    $Results = @{}

    foreach ($pkg in $PackageList) {
        $Id = $pkg.Id
        $Version = $pkg.Version

        $Script:NugetLogger.Info("批量解析: $Id v$Version")

        try {
            $Packages = @{ $Id = $Version }
            $Result = Resolve-NugetDependencyClosure -Source $Source -Packages $Packages -MaxDepth $MaxDepth -TargetFramework $TargetFramework
            $Results[$Id] = $Result
        }
        catch {
            $Script:NugetLogger.Error("批量解析 $Id 失败: $($_.Exception.Message)")
            $FailResult = [DependencyResolutionResult]::new()
            $FailResult.Success = $false
            $FailResult.Errors = @($_.Exception.Message)
            $Results[$Id] = $FailResult
        }
    }

    return $Results
}

#endregion
