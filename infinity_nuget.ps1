<#
.NOTES
    Name: infinity_nuget
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    PowerShell 工具用于下载和管理 Nuget 包
.DESCRIPTION
    这个工具提供以下功能：
    1. 搜索 Nuget 包
    2. 下载和安装 Nuget 包
    3. 管理本地包缓存
    4. 更新已安装的包
    5. 管理包源
#>

#region 日志
. (Join-Path -Path $PSScriptRoot -ChildPath 'infinity_log.ps1')
$Script:NugetLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityNuget")
$Script:NugetLogger = [LogClient]::new($Script:NugetLoggerServer)
#endregion

<#
.SYNOPSIS
表示 NuGet 包源的核心类，用于解析包源的版本和服务端点信息

.DESCRIPTION
通过 NuGet 包源的根地址（如 https://api.nuget.org/v3/index.json）请求并解析包源元数据，
提取包源版本号和各服务端点（如 SearchQueryService、PackageBaseAddress 等），
为后续 NuGet 操作（如搜索包、下载包）提供基础信息。

.EXAMPLE
PS> $nugetSource = [NugetSource]::new("https://api.nuget.org/v3/index.json")
PS> $nugetSource.Version  # 输出包源版本
PS> $nugetSource.ServiceEndpoints["SearchQueryService"]  # 输出搜索服务端点地址
#>
class NugetSource {
    <#
    .SYNOPSIS
    NuGet 包源的版本号（来自包源元数据的 version 字段）
    #>
    [string]$Version = $null

    <#
    .SYNOPSIS
    NuGet 包源的服务端点字典，Key 为服务类型（如 SearchQueryService），Value 为端点 URL
    #>
    [hashtable]$ServiceEndpoints = @{}
}

<#
.SYNOPSIS
通过 NuGet 包源的索引 Url 初始化 NuGetSource

.DESCRIPTION
基于 NuGet 包源的索引 Url, 获取源支持的服务端点和版本

.PARAMETER Url
必选, NuGet 包源的索引 Url, 用于获取服务端点

.EXAMPLE
PS> $source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
# 使用 NuGet 包源的索引 Url, 初始化一个 NugetSource 对象

.INPUTS
[string] - Url 参数支持管道输入(搜索关键词)

.OUTPUTS
[NugetSource] - 表示 NuGet 包源的类
#>
function New-NugetSource {
    [CmdletBinding()]
    [OutputType([NugetSource])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url
    )

    $Source = [NugetSource]::new()
        
    try {
        # 发起包源元数据请求（设置超时+忽略SSL错误，提升健壮性）
        $requestParams = @{
            Uri         = $Url
            Method      = "Get"
            TimeoutSec  = 30  # 设置请求超时时间
            ErrorAction = "Stop"
        }
        $Response = Invoke-WebRequest @requestParams

        # 验证响应内容非空
        if (-not $Response.Content) {
            throw "NuGet 包源响应内容为空：$Source"
        }

        try {
            $Data = $Response.Content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $Script:NugetLogger.Error("NuGet 包源JSON解析失败：$Source，错误信息：$($_.Exception.Message)")
            throw
        }

        # 提取版本号（兼容字段缺失场景）
        $Source.Version = if ($Data.ContainsKey('version')) { $Data['version'] } else { "unknown" }

        # 提取服务端点（防御性检查：确保resources字段存在且为数组）
        if ($Data.ContainsKey('resources') -and $Data['resources'] -is [array]) {
            foreach ($Resource in $Data['resources']) {
                # 确保服务类型和ID字段存在
                if ($Resource.ContainsKey('@type') -and $Resource.ContainsKey('@id')) {
                    $Source.ServiceEndpoints[$Resource['@type']] = $Resource['@id'] -replace '/$', ''
                }
            }
        }
        else {
            $Script:NugetLogger.Warn("NuGet 包源未找到有效资源列表：$Source")
        }
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            $statusDesc = $_.Exception.Response.StatusDescription
            $Script:NugetLogger.Error("NuGet 包源请求失败: $Source | 状态码: $statusCode | 描述: $statusDesc")
        }
        else {
            $Script:NugetLogger.Error("NuGet 包源初始化失败: $Source | 错误: $($_.Exception.Message)")
        }
        throw
    }
    return $Source
}

<#
.SYNOPSIS
通过 NuGet 包源搜索指定的 NuGet 包

.DESCRIPTION
基于 NugetSource 实例的 SearchQueryService 端点, 发起包搜索请求

.PARAMETER Source
必选, NugetSource 类的实例(已经初始化的包源对象), 用于获取搜索服务端点

.PARAMETER Query
必选, 包搜索关键词（支持 NuGet 搜索语法, 如 "Newtonsoft.Json","Id:Microsoft.AspNetCore")
支持管道输入

.PARAMETER Take
可选, 单次搜索返回的包数量(分页大小), 默认值 20, 取值范围 1~1000

.PARAMETER Skip
可选, 跳过的包数量(分页偏移量), 默认值 0, 取值范围 0~3000

.PARAMETER Prerelease
可选, 是否包含预发布版本的包, 默认值仅返回稳定版

.EXAMPLE
PS> $source = [NugetSource]::new("https://api.nuget.org/v3/index.json")
PS> Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 10 -Prerelease
# 搜索 Newtonsoft.Json 包，返回10条结果，包含预发布版本

.EXAMPLE
PS> "Microsoft.Extensions.DependencyInjection" | Search-NugetPackage -Source $source -Skip 0 -Take 5
# 通过管道输入搜索关键词, 分页获取前5条稳定版结果

.INPUTS
[string] - Query 参数支持管道输入(搜索关键词)
[NugetSource] - Source 参数接受 NugetSource 实例

.OUTPUTS
[hashtable[]] - NuGet 包搜索结果数组
#>
function Search-NugetPackage {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [string]$PackageType,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)] # 使用 nuget.org 的官方默认限制
        [int]$Take = 20,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3000)] # 使用 nuget.org 的官方默认限制
        [int]$Skip = 0,

        [Parameter(Mandatory = $false)]
        [switch]$Prerelease
    )

    begin {
        if ($Source.ServiceEndpoints.ContainsKey("SearchQueryService/3.5.0")) {
            $SearchEndpoint = $Source.ServiceEndpoints["SearchQueryService/3.5.0"]
        }
        elseif ($Source.ServiceEndpoints.ContainsKey("SearchQueryService")) {
            if ($PackageType) {
                $Script:NugetLogger.Warn("包源不支持 SearchQueryService/3.5.0 无法筛选包类型")
                $PackageType = $null
            }
            $SearchEndpoint = $Source.ServiceEndpoints["SearchQueryService"]
        }
        else {
            throw "包源缺失 SearchQueryService 端点"
        }
    }

    process {
        try {
            $QueryParams = [System.Web.HttpUtility]::ParseQueryString([string]::Empty)
            $QueryParams.Add("q", [System.Web.HttpUtility]::UrlEncode($Query))
            $QueryParams.Add("take", $Take.ToString())
            $QueryParams.Add("skip", $Skip.ToString())
            $QueryParams.Add("prerelease", "$Prerelease".ToLower())
            if ($PackageType) {
                $QueryParams.Add("packageType", [System.Web.HttpUtility]::UrlEncode($PackageType))
            }

            # 拼接完整的搜索 URL（自动处理 & 分隔符，避免手动拼接错误）
            $Url = "$($SearchEndpoint)?$($QueryParams.ToString())"
            
            $Script:NugetLogger.Info("尝试请求 $Url")

            $RequestParams = @{
                Uri         = $Url
                Method      = "Get"
                TimeoutSec  = 30
                ErrorAction = "Stop"
            }
            $Response = Invoke-RestMethod @RequestParams

            if ($Response -and $Response.Data) {
                return $Response.Data
            }
            else {
                $Script:NugetLogger.Warn("NuGet 搜索无结果：Query=$Query | Source=$($SearchEndpoint)")
                return @()
            }
        }
        catch {
            $ErrorMsg = if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
                $ReasonPhrase = $_.Exception.Response.ReasonPhrase
                "NuGet 搜索请求失败 | URL: $Url | 状态码: $StatusCode | 原因: $ReasonPhrase"
            }
            else {
                "NuGet 搜索失败 | Query: $Query | 错误: $($_.Exception.Message)"
            }
            $Script:NugetLogger.Error($ErrorMsg)
            throw
        }
    }
}

<#
.SYNOPSIS
解析 NuGet 包版本号（遵循微软 NuGet 官方版本规范，含归一化逻辑，大写开头命名）

.DESCRIPTION
- 支持 NuGet 核心规则：1-4 段核心数字、v 前缀、版本归一化、SemVer 2.0 预发布/构建元数据
- 不符合规范的版本号直接抛出错误，无 IsValid 字段
- 所有变量/返回键均为大写开头命名风格
- 参考文档：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning?tabs=semver20sort#normalized-version-numbers

.PARAMETER VersionString
必选，NuGet 包版本字符串（如：v10.0.17763.1-preview、2.5.8、1.01.0-beta+git789）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "v10.0.17763.1-preview"
Name                           Value
----                           -----
OriginalVersion                v10.0.17763.1-preview
NormalizedVersion              10.0.17763.1-preview
Major                          10
Minor                          0
Patch                          17763
Revision                       1
CoreSegments                   {10, 0, 17763, 1}
PreRelease                     preview
BuildMetadata                  $null
# 说明：解析带v前缀、4段核心数字、单级预发布标签的版本号

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "1.01.0-beta+git789012"
Name                           Value
----                           -----
OriginalVersion                1.01.0-beta+git789012
NormalizedVersion              1.1.0-beta+git789012
Major                          1
Minor                          1
Patch                          0
Revision                       0
CoreSegments                   {1, 1, 0, 0}
PreRelease                     beta
BuildMetadata                  git789012
# 说明：解析带前导零、预发布标签+构建元数据的版本号（前导零归一化后移除）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "5"
Name                           Value
----                           -----
OriginalVersion                5
NormalizedVersion              5.0.0
Major                          5
Minor                          0
Patch                          0
Revision                       0
CoreSegments                   {5, 0, 0, 0}
PreRelease                     $null
BuildMetadata                  $null
# 说明：解析极简1段核心数字的版本号（自动补全为4段，归一化为3段）

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "3.2.8-rc.2+20251226.git123"
Name                           Value
----                           -----
OriginalVersion                3.2.8-rc.2+20251226.git123
NormalizedVersion              3.2.8-rc.2+20251226.git123
Major                          3
Minor                          2
Patch                          8
Revision                       0
CoreSegments                   {3, 2, 8, 0}
PreRelease                     rc.2
BuildMetadata                  20251226.git123
# 说明：解析3段核心数字、多级预发布标签、复杂构建元数据的版本号

.EXAMPLE
PS> ConvertTo-NuGetVersion -VersionString "v2.5.0.0-alpha"
Name                           Value
----                           -----
OriginalVersion                v2.5.0.0-alpha
NormalizedVersion              2.5.0-alpha
Major                          2
Minor                          5
Patch                          0
Revision                       0
CoreSegments                   {2, 5, 0, 0}
PreRelease                     alpha
BuildMetadata                  $null
# 说明：解析带v前缀、4段核心数字（第4段为0）的版本号（归一化为3段）
#>
function ConvertTo-NuGetVersion {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VersionString
    )

    begin {
        # NuGet 官方版本规范正则
        $NugetVersionRegex = '^(?:v)?(?<CoreSegments>\d+(?:\.\d+){0,3})(?:-(?<Prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<Buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
    }

    process {
        # 步骤1：清理输入
        $CleanVersion = $VersionString.Trim()

        # 步骤2：匹配 NuGet 版本正则
        if ($CleanVersion -match $NugetVersionRegex) {
            # 步骤3：拆分核心数字段并处理前导零（NuGet 归一化规则：移除前导零）
            $CoreSegments = $Matches['CoreSegments'] -split '\.' | ForEach-Object {
                if ($_ -eq '0') { 0 } else { [int]($_ -replace '^0+', '') }
            }

            # 步骤4：补全核心段到4段（NuGet 支持 1-4 段，缺省补 0）
            while ($CoreSegments.Count -lt 4) {
                $CoreSegments += 0
            }

            # 步骤5：生成 NuGet 归一化版本号
            $NormalizedCore = $CoreSegments[0..2] -join '.'
            if ($CoreSegments[3] -ne 0) {
                $NormalizedCore = $CoreSegments -join '.'
            }
            $NormalizedVersion = $NormalizedCore
            if ($matches.ContainsKey('Prerelease') -and $matches['Prerelease']) {
                $NormalizedVersion += "-$($matches['Prerelease'])"
            }
            if ($matches.ContainsKey('Buildmetadata') -and $matches['Buildmetadata']) {
                $NormalizedVersion += "+$($matches['Buildmetadata'])"
            }

            # 步骤6：构造返回哈希表
            $NugetVersionHash = [ordered]@{
                OriginalVersion   = $CleanVersion
                NormalizedVersion = $NormalizedVersion
                Major             = $CoreSegments[0]
                Minor             = $CoreSegments[1]
                Patch             = $CoreSegments[2]
                Revision          = $CoreSegments[3]
                CoreSegments      = $CoreSegments
                PreRelease        = if ($Matches.ContainsKey('Prerelease')) { $Matches['Prerelease'] } else { $null }
                BuildMetadata     = if ($Matches.ContainsKey('Buildmetadata')) { $Matches['Buildmetadata'] } else { $null }
            }

            return $NugetVersionHash
        }
        else {
            throw "无效的 NuGet 版本号 '$CleanVersion'：不符合 NuGet 官方版本规范（参考：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning）"
        }
    }
}

<#
.SYNOPSIS
获取指定 NuGet 包的所有可用版本列表

.DESCRIPTION
通过 PackageBaseAddress/3.0.0 服务端点获取指定 NuGet 包的所有可用版本，
支持过滤预发布版本。返回的版本信息已通过 ConvertTo-NuGetVersion 函数标准化。

.PARAMETER Source
必选，NugetSource 类的实例（已初始化的包源对象），用于获取包基础地址端点

.PARAMETER Id
必选，NuGet 包的唯一标识符（包名称）

.PARAMETER Preview
可选，是否包含预发布版本。默认仅返回稳定版本

.EXAMPLE
PS> $source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> Get-NugetPackageVersions -Source $source -Id "Newtonsoft.Json"
# 获取 Newtonsoft.Json 包的所有稳定版本

.EXAMPLE
PS> Get-NugetPackageVersions -Source $source -Id "Microsoft.AspNetCore" -Preview
# 获取 Microsoft.AspNetCore 包的所有版本（包括预发布版本）

.OUTPUTS
[hashtable[]] - 标准化后的 NuGet 版本信息数组，每个元素包含原始版本、归一化版本、核心段等信息
#>
function Get-NugetPackageVersions {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $false)]
        [switch]$Preview
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/index.json"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-RestMethod -Uri $Url -Method Get
        $Versions = $Response.versions | ConvertTo-NuGetVersion
        return $Versions | Where-Object { $Preview -or (-not $_['PreRelease']) }
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}

<#
.SYNOPSIS
获取指定 NuGet 包的清单文件（nuspec）

.DESCRIPTION
通过 PackageBaseAddress/3.0.0 服务端点下载指定版本 NuGet 包的 .nuspec 文件，
返回解析后的 XML 文档对象，包含包的元数据、依赖关系等信息。

.PARAMETER Source
必选，NugetSource 类的实例（已初始化的包源对象），用于获取包基础地址端点

.PARAMETER Id
必选，NuGet 包的唯一标识符（包名称）

.PARAMETER Version
必选，NuGet 包的具体版本号

.EXAMPLE
PS> $source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> $manifest = Get-NugetPackagManifest -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
PS> $manifest.package.metadata.id
# 获取 Newtonsoft.Json 13.0.1 版本的清单并显示包ID

.EXAMPLE
PS> Get-NugetPackagManifest -Source $source -Id "AutoMapper" -Version "12.0.1" | 
    Select-Xml -XPath "//dependency" | Select-Object -ExpandProperty Node
# 获取 AutoMapper 12.0.1 版本的依赖项列表

.OUTPUTS
[xml] - NuGet 包清单的 XML 文档对象
#>
function Get-NugetPackagManifest {
    [CmdletBinding()]
    [OutputType([xml])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    # GET {@id}/{LOWER_ID}/{LOWER_VERSION}/{LOWER_ID}.nuspec
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/$($Version.ToLowerInvariant())/$($Id.ToLowerInvariant()).nuspec"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-WebRequest -Uri $Url -Method Get
        return [xml]$Response.Content
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id-$Version 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}

<#
.SYNOPSIS
下载指定 NuGet 包的二进制内容（.nupkg 文件）

.DESCRIPTION
通过 PackageBaseAddress/3.0.0 服务端点下载指定版本 NuGet 包的 .nupkg 文件，
返回包含包完整内容的字节数组，可用于保存到本地文件或进一步处理。

.PARAMETER Source
必选，NugetSource 类的实例（已初始化的包源对象），用于获取包基础地址端点

.PARAMETER Id
必选，NuGet 包的唯一标识符（包名称）

.PARAMETER Version
必选，NuGet 包的具体版本号

.EXAMPLE
PS> $source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> $packageBytes = Get-NugetPackagContent -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
PS> Set-Content -Path "Newtonsoft.Json.13.0.1.nupkg" -Value $packageBytes -AsByteStream
# 下载 Newtonsoft.Json 13.0.1 版本的 .nupkg 文件并保存到本地

.EXAMPLE
PS> $content = Get-NugetPackagContent -Source $source -Id "Serilog" -Version "3.1.1"
PS> $content.Length / 1MB
# 获取 Serilog 3.1.1 包的大小（以 MB 为单位）

.OUTPUTS
[byte[]] - NuGet 包文件的字节数组
#>
function Get-NugetPackagContent {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    # GET {@id}/{LOWER_ID}/{LOWER_VERSION}/{LOWER_ID}.{LOWER_VERSION}.nupkg
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/$($Version.ToLowerInvariant())/$($Id.ToLowerInvariant()).$($Version.ToLowerInvariant()).nupkg"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-WebRequest -Uri $Url -Method Get
        return [byte[]]$Response.Content
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id-$Version 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}

$Script:NugetLogger.Scope("加载配置", {
        $Script:ConfigPath = Join-Path -Path $PSScriptRoot 'configs' 'infinity_nuget_config.json'
        $Script:NugetLogger.Info("配置文件: $($Script:ConfigPath)")
        $Script:Config = Get-Content -Path $Script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable;
        $Script:NugetLogger.Info("配置: $($Script:Config | ConvertTo-Json -Depth 3)")
    })

<#
.SYNOPSIS
表示 NuGet 包库的核心类，用于记录包库中的包和包的版本
#>
class NugetPackageLibraryManifest {
    <#
    .SYNOPSIS
    NuGet 包库的包字典，Key 为包Id，Value 为包 Versuion
    #>
    [hashtable]$Packages = @{}
}

$Script:NugetPackageLibraryManifestFileName = "infinity_nuget_library.json"

function Save-NugetPackageLibraryManifest {

}

function Read-NugetPackagLibraryManifest {

    
}

function New-NugetPackageLibraryManifest {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $Item = New-Item -Path $Path -ItemType Directory
        $Path = $Item.FullName
    }
    else {
        $Item = Get-Item -Path $Path
        $Path = $Item.FullName
    }
    $Script:NugetLogger.Info("Nuget 包库文件夹: $($Path)")

    $PackageLibrary = [NugetPackageLibrary]::new()

    $PackageLibrary | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path (Join-Path $Path $Script:NugetPackageLibraryConfigFileName)

    return $Path
}

$LibraryPath = New-NugetPackageLibraryManifest -Path $Script:Config["PackagesPath"]
$LibraryManifest = Read-NugetPackagLibraryManifest -Path $LibraryPath