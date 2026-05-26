# 构建模块 API — `infinity_build.ps1`

`infinity_build.ps1` 是 Infinity Build 的核心模块，负责解析源文件、管理模块依赖、打包资源和生成最终的可执行脚本。

---

## 参数

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-ConfigPath` | `string` | 是 | 构建配置文件的 JSON 路径 |
| `-ExtraConfig` | `hashtable` | 否 | 额外的构建步骤配置，会合并到配置文件中的步骤 |

```powershell
.\infinity_build.ps1 -ConfigPath ".\myproject.json"
.\infinity_build.ps1 -ConfigPath ".\base.json" -ExtraConfig @{ Boot = @{ EntryPoint = "CustomMain" } }
```

---

## 类

### `InfinityModule`

表示一个已解析的代码模块。

| 属性 | 类型 | 说明 |
| - | - | - |
| `Name` | `string` | 模块名称 |
| `Requires` | `List[string]` | 依赖的模块名列表 |
| `Code` | `List[string]` | 模块代码行列表 |
| `SourceInfo` | `FileInfo` | 源文件信息 |
| `LineMappings` | `Dictionary[int, int]` | 输出行号 → 源文件行号映射 |

### `InfinityProgramSegment`

表示一个完整的程序段（由多个模块合并而成）。

| 属性 | 类型 | 说明 |
| - | - | - |
| `Code` | `List[string]` | 合并后的全部代码行 |
| `LineMappings` | `Dictionary[int, Tuple[string, int]]` | 输出行号 → (源文件路径, 源行号) 映射 |

### `ResourceFileInfo`

资源文件信息。

| 属性 | 类型 | 说明 |
| - | - | - |
| `FileInfo` | `FileInfo` | 文件系统信息 |
| `RelativePath` | `string` | 在资源包中的相对路径 |

### `ResourceFileHash`

资源文件哈希记录。

| 属性 | 类型 | 说明 |
| - | - | - |
| `RelativePath` | `string` | 资源包内的相对路径 |
| `Hash256` | `string` | 文件的 SHA256 哈希值 |

---

## 函数

### 文件处理

#### `Find-Files`

按 glob 模式查找文件。

```powershell
Find-Files -Filters $Filters [-Path $Path]
```

| 参数 | 类型 | 必选 | 默认值 | 说明 |
| - | - | - | - | - |
| `-Filters` | `string[]` | 是 | — | 文件过滤器数组，如 `@("src/*.ps1", "lib/**/*.psm1")` |
| `-Path` | `string` | 否 | 工作目录 | 搜索根目录 |

**返回**：`string[]` — 匹配文件的完整路径数组。

---

### 模块处理

#### `Get-InfinityModule`

解析单个源文件为 `InfinityModule` 对象。自动处理预处理指令（`#infb:` 和 `##`）。

```powershell
Get-InfinityModule -Path $Path
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Path` | `string` | 是 | 源文件路径 |

**返回**：`InfinityModule` — 解析后的模块对象。

**预处理指令：**

| 指令 | 说明 |
| - | - |
| `## Module <名称>` | 声明模块名（覆盖文件名） |
| `## Import <模块>` | 声明对其他模块的依赖 |
| `#infb: rm` | 构建时移除此行 |
| `#infb: debug` | 仅 Debug 模式保留 |
| `#infb: release` | 仅 Release 模式保留 |
| `#infb: replace <内容>` | 替换整行为指定内容 |

#### `Get-InfinityModuleOrdered`

对模块列表进行拓扑排序（按依赖关系），检测循环依赖。

```powershell
Get-InfinityModuleOrdered -Modules $Modules
```

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-Modules` | `InfinityModule[]` | 是 | 待排序的模块数组 |

**返回**：`InfinityModule[]` — 按依赖顺序排列的模块数组（被依赖者在前）。

**异常**：检测到循环依赖时抛出错误。

#### `New-InfinityProgramSegment`

将有序模块合并为程序段。

```powershell
New-InfinityProgramSegment -Modules $Modules
```

**返回**：`InfinityProgramSegment` — 合并后的程序段。

---

### 资源处理

#### `Get-ResourceSnapshot`

计算资源文件的 SHA256 快照。

```powershell
Get-ResourceSnapshot -ResourceFiles $ResourceFiles
```

**返回**：`ResourceFileHash[]` — 文件哈希数组。

#### `Compare-ResourceSnapshot`

比较新旧两个资源快照是否一致。

```powershell
Compare-ResourceSnapshot -NewSnapshot $New -OldSnapshot $Old
```

**返回**：`bool` — `$true` 表示一致，`$false` 表示有变化。

#### `Write-ResourceSnapshot` / `Read-ResourceSnapshot`

写入/读取资源快照到 JSON 文件，实现增量构建缓存。

```powershell
Write-ResourceSnapshot -Snapshot $Snapshot -Path $Path
Read-ResourceSnapshot -Path $Path
```

#### `Compress-ResourceFiles`

将资源文件压缩为 ZIP 包。

```powershell
Compress-ResourceFiles -ResourceFiles $Files -DestinationPath $Dest [-CompressionLevel $Level] [-Force]
```

| 参数 | 类型 | 默认值 | 说明 |
| - | - | - | - |
| `-CompressionLevel` | `CompressionLevel` | `Optimal` | 压缩级别 |
| `-Force` | `switch` | — | 覆盖已存在的 ZIP 文件 |

#### `Get-ResourceEmbedModule`

将 ZIP 文件转换为 Base64 嵌入模块（`Builtin.Resource`）。

```powershell
Get-ResourceEmbedModule -ZipFilePath $ZipPath
```

**返回**：`InfinityModule` — 包含资源数据的模块，含有 `$BuiltinResourceZipHash` 和 `$BuiltinResourceZipContent` 变量。

---

### 构建步骤（模块构建器）

构建系统通过**模块构建器字典**驱动，每个构建步骤对应一个构建器脚本块。

| 构建步骤 | 说明 |
| - | - |
| `Source` | 解析源文件为模块，拓扑排序 |
| `Std` | 解析标准库（`std/` 目录）模块 |
| `Resource` | 收集、增量打包资源文件 |
| `PreDefineds` | 生成预定义变量模块 |
| `Nuget` | 下载并管理 NuGet 包依赖 |
| `Boot` | 生成启动入口模块 |

#### `Add-PreDefinedVariable`

向预定义变量模块添加变量。

```powershell
Add-PreDefinedVariable -Module $Module -Name $Name -Value $Value
```

| 参数 | 类型 | 说明 |
| - | - | - |
| `-Value` | `string` / `int` / `bool` | 变量值，支持三种基本类型 |

---

## 输出产物

构建完成后生成两个文件：

| 文件 | 说明 |
| - | - |
| `<Output>.ps1` | 最终的合并脚本（可独立运行） |
| `<Output>.debug.json` | 调试映射文件，供 `infinity_dbg.ps1` 使用 |

调试映射文件格式：

```json
[
    { "OutputLine": 1, "SourceFile": "C:\\src\\core.ps1", "SourceLineNum": 5 },
    { "OutputLine": 2, "SourceFile": "C:\\src\\core.ps1", "SourceLineNum": 6 }
]
```

---

## 完整工作流示例

```powershell
# 1. 准备配置文件 myproject.json（参见构建配置指南）
# 2. 执行构建
.\infinity_build.ps1 -ConfigPath ".\myproject.json"

# 3. 运行构建产物
.\output.ps1

# 4. 或使用调试器运行
.\infinity_dbg.ps1 -ScriptPath ".\output.ps1"
```
