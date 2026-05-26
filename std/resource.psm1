##Module Std.Resource
##Import Builtin.Resource

# ============================================================
# Std.Resource - 运行时资源提取与管理
#
# 支持两种资源模式：
#   Builtin 模式：资源以 Base64 嵌入脚本中，运行时解压
#   External 模式：资源以外部 ZIP 文件发布，运行时按名查找并解压
#
# 构建时注入的变量（来自 Builtin.Resource 模块）：
#   $BuiltinResourceZipHash    — SHA256 哈希（两种模式均有）
#   $BuiltinResourceZipContent — Base64 ZIP 字节（仅 Builtin 模式）
#   $BuiltinResourceZipName    — 外部 ZIP 文件名（仅 External 模式）
# ============================================================

#region 内部状态
$Script:ResourceInitialized = $false
$Script:ResourceRoot = $null
$Script:ResourceHashFile = $null

# 判断资源模式：有 Base64 内容为 Builtin，仅有文件名为 External
$Script:ResourceMode = if (Test-Path variable:Script:BuiltinResourceZipContent) {
    'Builtin'
} elseif (Test-Path variable:Script:BuiltinResourceZipName) {
    'External'
} else {
    $null
}
#endregion

#region Find-ResourceZip（External 模式辅助）
function Find-ResourceZip {
    [CmdletBinding()]
    param()

    # 搜索顺序：脚本同级目录 > 工作目录 > 脚本所在目录的父级
    $searchDirs = @()
    if ($PSCommandPath) {
        $searchDirs += Split-Path $PSCommandPath -Parent
    }
    $searchDirs += $PWD.Path
    if ($PSCommandPath) {
        $searchDirs += Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    }

    foreach ($dir in $searchDirs | Select-Object -Unique) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir $BuiltinResourceZipName
        if (Test-Path $candidate -PathType Leaf) {
            # 校验哈希
            $actualHash = (Get-FileHash -Path $candidate -Algorithm SHA256).Hash
            if ($actualHash -eq $BuiltinResourceZipHash) {
                return $candidate
            }
            Write-Warning "[Std.Resource] ZIP 文件哈希不匹配: $candidate (期望: $BuiltinResourceZipHash, 实际: $actualHash)"
        }
    }

    throw @"
[Std.Resource] 找不到外部资源 ZIP 文件 '$BuiltinResourceZipName'。
已搜索以下目录:
$($searchDirs -join "`n")
请确保资源 ZIP 文件与构建产物位于同一目录。
"@
}
#endregion

#region Initialize-Resource
<#
.SYNOPSIS
    解压资源文件到目标目录（自动识别 Builtin / External 模式）。

.DESCRIPTION
    Builtin 模式：从嵌入的 Base64 数据解压。
    External 模式：查找外部 ZIP 文件并校验哈希后解压。
    首次调用后缓存哈希，资源未变更则跳过解压。

.PARAMETER TargetDir
    资源解压目标目录。未指定时使用系统临时目录下的
    "<项目名>_resources" 子目录。

.PARAMETER Force
    强制重新解压，忽略已有缓存。

.EXAMPLE
    # 解压到默认临时目录
    Initialize-Resource

.EXAMPLE
    # 解压到指定目录并强制覆盖
    Initialize-Resource -TargetDir ".\assets" -Force
#>
function Initialize-Resource {
    [CmdletBinding()]
    param(
        [string]$TargetDir,
        [switch]$Force
    )

    if ($Script:ResourceInitialized -and -not $Force) {
        return $Script:ResourceRoot
    }

    # 检查资源模式
    if (-not $Script:ResourceMode) {
        throw @"
[Std.Resource] 未找到资源数据。
请确认:
  1. 构建配置中包含 Resource 构建步骤
  2. 资源配置了至少一个 resources 映射
  3. 构建产物中 Std.Resource 模块排在 Builtin.Resource 模块之后
"@
    }

    # 确定目标目录
    if (-not $TargetDir) {
        $AppId = if (Test-Path variable:Script:BuildName) { $BuildName } else { "app" }
        $TargetDir = Join-Path ([System.IO.Path]::GetTempPath()) "${AppId}_resources"
    }
    else {
        $TargetDir = Join-Path $PWD $TargetDir
    }

    $hashFile = Join-Path $TargetDir ".resource_hash"

    # 检查哈希缓存：资源未变化且目录存在则跳过
    if (-not $Force -and (Test-Path $hashFile) -and (Test-Path $TargetDir)) {
        $cachedHash = Get-Content $hashFile -Raw -ErrorAction SilentlyContinue
        if ($cachedHash -and (Test-Path variable:Script:BuiltinResourceZipHash)) {
            if ($cachedHash.Trim() -eq $BuiltinResourceZipHash) {
                $Script:ResourceInitialized = $true
                $Script:ResourceRoot = (Get-Item $TargetDir).FullName
                $Script:ResourceHashFile = $hashFile
                return $Script:ResourceRoot
            }
        }
    }

    # 准备目标目录
    if ($Force -and (Test-Path $TargetDir)) {
        Remove-Item $TargetDir -Recurse -Force -ErrorAction Stop
    }

    if (-not (Test-Path $TargetDir)) {
        $null = New-Item -Path $TargetDir -ItemType Directory -Force -ErrorAction Stop
    }

    # 根据模式获取 ZIP 字节流
    try {
        if ($Script:ResourceMode -eq 'Builtin') {
            $zipBytes = $BuiltinResourceZipContent
            $zipStream = [System.IO.MemoryStream]::new($zipBytes)
        }
        else {
            # External 模式：查找外部 ZIP 文件
            $zipPath = Find-ResourceZip
            $zipBytes = [System.IO.File]::ReadAllBytes($zipPath)
            $zipStream = [System.IO.MemoryStream]::new($zipBytes)
        }

        $zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Read)
        $extractDir = (Get-Item $TargetDir).FullName

        foreach ($entry in $zipArchive.Entries) {
            $destPath = Join-Path $extractDir $entry.FullName

            # 跳过目录条目（以 / 结尾）
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                if (-not (Test-Path $destPath)) {
                    $null = New-Item -Path $destPath -ItemType Directory -Force
                }
                continue
            }

            # 确保父目录存在
            $parentDir = Split-Path $destPath -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                $null = New-Item -Path $parentDir -ItemType Directory -Force
            }

            # 解压文件
            $entryStream = $entry.Open()
            $fileStream = [System.IO.File]::Open($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try {
                $entryStream.CopyTo($fileStream)
            }
            finally {
                $fileStream.Dispose()
                $entryStream.Dispose()
            }
        }

        $zipArchive.Dispose()
        $zipStream.Dispose()
    }
    catch {
        throw "[Std.Resource] 资源解压失败: $($_.Exception.Message)"
    }

    # 写入哈希缓存
    if (Test-Path variable:Script:BuiltinResourceZipHash) {
        $BuiltinResourceZipHash | Set-Content $hashFile -NoNewLine -ErrorAction SilentlyContinue
    }

    $Script:ResourceInitialized = $true
    $Script:ResourceRoot = $extractDir
    $Script:ResourceHashFile = $hashFile

    return $Script:ResourceRoot
}
#endregion

#region Get-ResourcePath
<#
.SYNOPSIS
    获取已解压资源的完整文件路径。

.DESCRIPTION
    根据资源包内的相对路径，返回解压后的完整路径。
    首次调用时会自动触发资源初始化（若尚未初始化）。

.PARAMETER RelativePath
    资源在包内的相对路径，如 "images/logo.png"。
    支持 / 和 \ 作为路径分隔符。

.EXAMPLE
    $logoPath = Get-ResourcePath "images/logo.png"
    $logoPath = Get-ResourcePath "config\settings.json"
#>
function Get-ResourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$RelativePath
    )

    begin {
        if (-not $Script:ResourceInitialized) {
            $null = Initialize-Resource
        }
    }

    process {
        $normalized = $RelativePath -replace '[/\\]', [System.IO.Path]::DirectorySeparatorChar
        $fullPath = Join-Path $Script:ResourceRoot $normalized

        if (-not (Test-Path $fullPath -PathType Leaf)) {
            throw "[Std.Resource] 资源文件不存在: $RelativePath"
        }

        return $fullPath
    }
}
#endregion

#region Get-ResourceText
<#
.SYNOPSIS
    读取资源文件为文本内容。

.DESCRIPTION
    以 UTF-8 编码读取资源文件全文。
    适用于 .json、.txt、.md、.csv 等文本文件。

.PARAMETER RelativePath
    资源在包内的相对路径。

.EXAMPLE
    $config = Get-ResourceText "config/app.json" | ConvertFrom-Json
    $readme  = Get-ResourceText "README.md"
#>
function Get-ResourceText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = Get-ResourcePath $RelativePath
    return Get-Content -Path $path -Raw -Encoding UTF8
}
#endregion

#region Get-ResourceBytes
<#
.SYNOPSIS
    读取资源文件为字节数组。

.DESCRIPTION
    以二进制方式读取资源文件。
    适用于 .png、.dll、.zip 等二进制文件。

.PARAMETER RelativePath
    资源在包内的相对路径。

.EXAMPLE
    $imageBytes = Get-ResourceBytes "assets/logo.png"
    [System.IO.File]::WriteAllBytes("$env:TEMP\logo.png", $imageBytes)
#>
function Get-ResourceBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = Get-ResourcePath $RelativePath
    return [System.IO.File]::ReadAllBytes($path)
}
#endregion

#region Clear-Resource
<#
.SYNOPSIS
    清理已解压的资源文件。

.DESCRIPTION
    删除资源解压目录及其所有内容，重置模块内部状态。
    下次调用 Initialize-Resource 将重新解压。

.EXAMPLE
    Clear-Resource
#>
function Clear-Resource {
    [CmdletBinding()]
    param()

    if ($Script:ResourceRoot -and (Test-Path $Script:ResourceRoot)) {
        Remove-Item $Script:ResourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $Script:ResourceInitialized = $false
    $Script:ResourceRoot = $null
    $Script:ResourceHashFile = $null
}
#endregion
