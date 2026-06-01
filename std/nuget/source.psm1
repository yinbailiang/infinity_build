##Module Std.Nuget.Source
##Import Std.Nuget.Logger
##Import Std.Nuget.Versioning

<#
.NOTES
    Name: infinity_nuget_source
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    NuGet 包源交互模块
.DESCRIPTION
    这个模块提供以下功能：
    1. 初始化和管理 NuGet 包源连接
    2. 搜索 NuGet 包
    3. 解析和比较版本号
    4. 获取包版本列表
    5. 下载包清单和内容
#>

#region 源交互
<#
.SYNOPSIS
表示 NuGet 包源的核心类，用于解析包源的版本和服务端点信息

.DESCRIPTION
通过 NuGet 包源的根地址（如 https://api.nuget.org/v3/index.json）请求并解析包源元数据，
提取包源版本号和各服务端点（如 SearchQueryService、PackageBaseAddress 等），
为后续 NuGet 操作（如搜索包、下载包）提供基础信息。

.EXAMPLE
PS> $NugetSource =  New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> $NugetSource.Version  # 输出包源版本
PS> $NugetSource.ServiceEndpoints["SearchQueryService"]  # 输出搜索服务端点地址
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
PS> $Source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
# 使用 NuGet 包源的索引 Url, 初始化一个 NugetSource 对象

.INPUTS
[string] - Url 参数支持管道输入

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
        $RequestParams = @{
            Uri         = $Url
            Method      = "Get"
            TimeoutSec  = 30  # 设置请求超时时间
            ErrorAction = "Stop"
        }
        $Response = Invoke-WebRequest @RequestParams

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
            $StatusCode = $_.Exception.Response.StatusCode
            $StatusDesc = $_.Exception.Response.StatusDescription
            $Script:NugetLogger.Error("NuGet 包源请求失败: $Source | 状态码: $StatusCode | 描述: $StatusDesc")
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
PS> $Source = [NugetSource]::new("https://api.nuget.org/v3/index.json")
PS> Search-NugetPackage -Source $Source -Query "Newtonsoft.Json" -Take 10 -Prerelease
# 搜索 Newtonsoft.Json 包，返回10条结果，包含预发布版本

.EXAMPLE
PS> "Microsoft.Extensions.DependencyInjection" | Search-NugetPackage -Source $Source -Skip 0 -Take 5
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
PS> $Source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> Get-NugetPackageVersions -Source $Source -Id "Newtonsoft.Json"
# 获取 Newtonsoft.Json 包的所有稳定版本

.EXAMPLE
PS> Get-NugetPackageVersions -Source $Source -Id "Microsoft.AspNetCore" -Preview
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
        return $Versions | Where-Object { $Preview -or (-not $_.IsPrerelease()) }
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
PS> $Source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> $Manifest = Get-NugetPackagManifest -Source $Source -Id "Newtonsoft.Json" -Version "13.0.1"
PS> $Manifest.package.metadata.id
# 获取 Newtonsoft.Json 13.0.1 版本的清单并显示包ID

.EXAMPLE
PS> Get-NugetPackagManifest -Source $Source -Id "AutoMapper" -Version "12.0.1" | 
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
PS> $Source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
PS> $PackageBytes = Get-NugetPackagContent -Source $Source -Id "Newtonsoft.Json" -Version "13.0.1"
PS> Set-Content -Path "Newtonsoft.Json.13.0.1.nupkg" -Value $PackageBytes -AsByteStream
# 下载 Newtonsoft.Json 13.0.1 版本的 .nupkg 文件并保存到本地

.EXAMPLE
PS> $Content = Get-NugetPackagContent -Source $Source -Id "Serilog" -Version "3.1.1"
PS> $Content.Length / 1MB
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
#endregion