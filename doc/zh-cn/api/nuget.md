# NuGet 管理 API — `infinity_nuget.ps1`

`infinity_nuget.ps1` 提供完整的 NuGet 包管理能力，包括包源解析、包搜索、版本管理、下载安装和本地包库管理。

---

## 类

### `NugetSource`

表示 NuGet 包源，存储包源的版本和服务端点信息。

#### 属性

| 属性 | 类型 | 说明 |
| - | - | - |
| `Version` | `string` | 包源的协议版本号 |
| `ServiceEndpoints` | `hashtable` | 服务端点字典，Key 为服务类型，Value 为端点 URL |

常见服务端点类型：

| Key | 说明 |
| - | - |
| `SearchQueryService` | 搜索服务 |
| `SearchQueryService/3.5.0` | 搜索服务（支持包类型筛选） |
| `PackageBaseAddress/3.0.0` | 包下载基础地址 |
| `RegistrationsBaseUrl` | 包注册信息 |

### `NugetPackageLibraryManifest`

表示本地包库清单。

| 属性 | 类型 | 说明 |
| - | - | - |
| `Packages` | `hashtable` | 包字典，Key 为包 ID（小写），Value 为版本信息字典 |

---

## 函数

### 包源管理

#### `New-NugetSource`

初始化 NuGet 包源，从索引 URL 获取服务端点。

```powershell
New-NugetSource -Url $Url
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Url` | `string` | 是 | NuGet 包源索引 URL，如 `https://api.nuget.org/v3/index.json` |

**返回**：`NugetSource`

**示例**：

```powershell
$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
$source.Version                     # 输出包源版本
$source.ServiceEndpoints.Keys       # 列出所有可用服务端点
```

---

### 包搜索与版本管理

#### `Search-NugetPackage`

在指定包源中搜索 NuGet 包。

```powershell
Search-NugetPackage -Source $Source -Query $Query [-Take $Take] [-Skip $Skip] [-Prerelease] [-PackageType $Type]
```

| 参数 | 类型 | 必选 | 默认值 | 说明 |
| - | - | - | - | - |
| `-Source` | `NugetSource` | 是 | — | 已初始化的包源对象 |
| `-Query` | `string` | 是 | — | 搜索关键词，支持管道输入 |
| `-Take` | `int` | 否 | `20` | 返回结果数量（1~1000） |
| `-Skip` | `int` | 否 | `0` | 分页偏移量（0~3000） |
| `-Prerelease` | `switch` | 否 | — | 是否包含预发布版本 |
| `-PackageType` | `string` | 否 | — | 包类型筛选（需源支持 3.5.0） |

**返回**：`hashtable[]` — 搜索结果数组，每个元素包含 `id`、`version`、`description` 等字段。

**示例**：

```powershell
# 基本搜索
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 10

# 管道搜索
"Microsoft.Extensions.DependencyInjection" | Search-NugetPackage -Source $source

# 带预发布版本
Search-NugetPackage -Source $source -Query "Serilog" -Prerelease
```

#### `ConvertTo-NuGetVersion`

解析并归一化 NuGet 版本号，遵循 [NuGet 官方版本规范](https://learn.microsoft.com/en-us/nuget/concepts/package-versioning)。

```powershell
ConvertTo-NuGetVersion -VersionString $Version
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-VersionString` | `string` | 是 | 版本号字符串，支持管道输入 |

**返回**：`hashtable`（有序字典），包含以下键：

| 键 | 类型 | 说明 |
| - | - | - |
| `OriginalVersion` | `string` | 原始输入版本号 |
| `NormalizedVersion` | `string` | NuGet 归一化版本号 |
| `Major` | `int` | 主版本号 |
| `Minor` | `int` | 次版本号 |
| `Patch` | `int` | 补丁版本号 |
| `Revision` | `int` | 修订版本号（无则为 0） |
| `CoreSegments` | `int[]` | 四段核心数字数组 |
| `PreRelease` | `string` | 预发布标签（无则为 `$null`） |
| `BuildMetadata` | `string` | 构建元数据（无则为 `$null`） |

**示例**：

```powershell
ConvertTo-NuGetVersion "v10.0.17763.1-preview"
# 输出: NormalizedVersion = 10.0.17763.1-preview

ConvertTo-NuGetVersion "1.01.0-beta+git789"
# 输出: NormalizedVersion = 1.1.0-beta+git789（前导零被移除）

ConvertTo-NuGetVersion "3.2.8-rc.2+20251226.git123"
# 输出: PreRelease = rc.2, BuildMetadata = 20251226.git123
```

#### `Get-NugetPackageVersions`

获取指定包的所有可用版本。

```powershell
Get-NugetPackageVersions -Source $Source -Id $Id [-Preview]
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Source` | `NugetSource` | 是 | 已初始化的包源对象 |
| `-Id` | `string` | 是 | 包 ID |
| `-Preview` | `switch` | 否 | 是否包含预发布版本，默认仅稳定版 |

**返回**：`hashtable[]` — 标准化后的版本信息数组。

**示例**：

```powershell
# 获取所有稳定版本
$versions = Get-NugetPackageVersions -Source $source -Id "Newtonsoft.Json"

# 含预发布版本
$allVersions = Get-NugetPackageVersions -Source $source -Id "Microsoft.AspNetCore" -Preview
```

---

### 包清单与内容

#### `Get-NugetPackagManifest`

获取 NuGet 包的清单文件（`.nuspec`），返回 XML 文档对象。

```powershell
Get-NugetPackagManifest -Source $Source -Id $Id -Version $Version
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Source` | `NugetSource` | 是 | 已初始化的包源对象 |
| `-Id` | `string` | 是 | 包 ID |
| `-Version` | `string` | 是 | 包版本号 |

**返回**：`xml` — nuspec 清单的 XML 文档对象。

**示例**：

```powershell
$manifest = Get-NugetPackagManifest -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
$manifest.package.metadata.id       # 包 ID
$manifest.package.metadata.version   # 版本号

# 查看依赖
$manifest | Select-Xml -XPath "//dependency" | Select-Object -ExpandProperty Node
```

#### `Get-NugetPackagContent`

下载 NuGet 包的二进制内容（`.nupkg` 文件）。

```powershell
Get-NugetPackagContent -Source $Source -Id $Id -Version $Version
```

**返回**：`byte[]` — 包文件的字节数组。

**示例**：

```powershell
$bytes = Get-NugetPackagContent -Source $source -Id "Newtonsoft.Json" -Version "13.0.1"
[System.IO.File]::WriteAllBytes("Newtonsoft.Json.13.0.1.nupkg", $bytes)
```

---

### 包库管理

#### `New-NugetPackageLibraryManifest`

在指定路径创建新的本地包库。

```powershell
New-NugetPackageLibraryManifest -Path $Path
```

**返回**：`string` — 创建后的包库完整路径。

#### `Save-NugetPackageLibraryManifest` / `Read-NugetPackageLibraryManifest`

保存/读取包库清单到/从 JSON 文件。

```powershell
Save-NugetPackageLibraryManifest -Path $Path -Manifest $Manifest
Read-NugetPackageLibraryManifest -Path $Path
```

#### `Install-NugetPackage`

下载并安装 NuGet 包到本地包库。

```powershell
Install-NugetPackage -Source $Source -Id $Id -Version $Version -LibraryPath $Path [-Force]
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Source` | `NugetSource` | 是 | 包源对象 |
| `-Id` | `string` | 是 | 包 ID |
| `-Version` | `string` | 是 | 包版本 |
| `-LibraryPath` | `string` | 是 | 本地包库路径 |
| `-Force` | `switch` | 否 | 强制重新安装（覆盖已有版本） |

**返回**：`string` — 安装后的包目录路径。

**包库目录结构**：

```
<LibraryPath>/
├── infinity_nuget_library.json    # 包库清单
├── <package-id>/
│   └── <version>/
│       ├── <id>.<version>.nupkg   # 原始包文件
│       └── ...                    # 解压后的包内容
```

#### `Uninstall-NugetPackage`

从本地包库卸载 NuGet 包。

```powershell
# 卸载指定版本
Uninstall-NugetPackage -Id $Id -Version $Version -LibraryPath $Path

# 卸载所有版本
Uninstall-NugetPackage -Id $Id -LibraryPath $Path -AllVersions
```

**返回**：`bool` — 卸载是否成功。

#### `Update-NugetPackage`

将指定包更新到最新版本。

```powershell
Update-NugetPackage -Source $Source -Id $Id -LibraryPath $Path [-IncludePrerelease]
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-IncludePrerelease` | `switch` | 否 | 包含预发布版本 |

**返回**：`string` — 更新后的包目录路径。

---

## 完整工作流示例

```powershell
. ./infinity_nuget.ps1

# 1. 连接包源
$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"

# 2. 搜索包
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 5
$results | Format-Table id, version -AutoSize

# 3. 查看可用版本
$versions = Get-NugetPackageVersions -Source $source -Id "Newtonsoft.Json"
$versions | Select-Object OriginalVersion, NormalizedVersion | Format-Table

# 4. 创建本地包库并安装
$libPath = New-NugetPackageLibraryManifest -Path ".\my_packages"
$pkgDir = Install-NugetPackage -Source $source -Id "Newtonsoft.Json" -Version "13.0.3" -LibraryPath $libPath

# 5. 查看包清单
$manifest = Get-NugetPackagManifest -Source $source -Id "Newtonsoft.Json" -Version "13.0.3"

# 6. 更新到最新版
$updatedDir = Update-NugetPackage -Source $source -Id "Newtonsoft.Json" -LibraryPath $libPath

# 7. 卸载旧版本
Uninstall-NugetPackage -Id "Newtonsoft.Json" -Version "13.0.1" -LibraryPath $libPath
```
