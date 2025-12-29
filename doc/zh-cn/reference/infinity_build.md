# Infinity Build API 文档

## 概述

`infinity_build.ps1` 是一个 PowerShell 构建工具，用于管理和打包 PowerShell 项目。它支持模块依赖解析、资源文件打包和代码合并等功能。

## 命令行参数

### `-ConfigPath`
- **类型**: `string`
- **必需**: 是
- **描述**: 构建配置文件（JSON格式）的路径。该文件定义了项目的构建配置。

### `-Clean`
- **类型**: `switch`
- **必需**: 否
- **描述**: 清理构建缓存目录。

## 日志函数

### `Write-BuildLog`
输出构建信息日志。

**参数**:
- `Message` (string): 要输出的消息

**示例**:
```powershell
Write-BuildLog -Message "开始构建..."
```

### `Write-BuildWarning`
输出构建警告日志。

**参数**:
- `Message` (string): 要输出的警告消息

**示例**:
```powershell
Write-BuildWarning -Message "未找到依赖模块"
```

### `Write-BuildError`
输出构建错误日志。

**参数**:
- `Message` (string): 要输出的错误消息

**示例**:
```powershell
Write-BuildError -Message "构建失败"
```

## 文件处理函数

### `Find-Files`
查找匹配指定过滤器的文件。

**参数**:
- `Filters` (string[]): 文件过滤器数组
- `Path` (string, 可选): 搜索路径，默认为工作目录

**返回值**: `string[]` - 找到的文件路径数组

**示例**:
```powershell
$files = Find-Files -Filters @("*.ps1", "*.psm1") -Path ".\src"
```

## 模块处理

### `InfinityModule` 类
表示一个 PowerShell 模块。

**属性**:
- `Name` (string): 模块名称
- `Requires` (List\<string\>): 依赖的模块名称列表
- `Code` (List\<string\>): 模块代码行列表
- `SourceInfo` (FileInfo): 源文件信息
- `LineMappings` (Dictionary\<int, int\>): 代码行映射（合并后行号 -> 源文件行号）

### `Get-InfinityModule`
从文件读取并解析 PowerShell 模块。

**参数**:
- `Path` (string): 模块文件路径

**返回值**: `InfinityModule` - 解析后的模块对象

**示例**:
```powershell
$module = Get-InfinityModule -Path ".\src\module.ps1"
```

### `Get-InfinityModuleOrdered`
对模块进行拓扑排序，解析依赖关系。

**参数**:
- `Modules` (InfinityModule[]): 模块数组

**返回值**: `InfinityModule[]` - 排序后的模块数组

**示例**:
```powershell
$ordered = Get-InfinityModuleOrdered -Modules $modules
```

### `InfinityProgramSegment` 类
表示合并后的程序段。

**属性**:
- `Code` (List\<string\>): 合并后的代码行列表
- `LineMappings` (Dictionary\<int, Tuple\<string, int\>\>): 行号映射（合并后行号 -> (源文件, 源文件行号)）

### `New-InfinityProgramSegment`
从排序后的模块创建程序段。

**参数**:
- `Modules` (InfinityModule[]): 排序后的模块数组

**返回值**: `InfinityProgramSegment` - 合并后的程序段

**示例**:
```powershell
$segment = New-InfinityProgramSegment -Modules $orderedModules
```

## 资源处理

### `ResourceFileInfo` 类
表示资源文件信息。

**属性**:
- `FileInfo` (FileInfo): 文件系统信息
- `RelativePath` (string): 相对于资源根目录的路径

### `ResourceFileHash` 类
表示资源文件哈希信息。

**属性**:
- `RelativePath` (string): 文件相对路径
- `Hash256` (string): SHA256 哈希值

### `Find-ResourceFiles`
查找资源目录下的所有文件。

**参数**:
- `Path` (string): 资源根目录路径

**返回值**: `ResourceFileInfo[]` - 资源文件信息数组

**示例**:
```powershell
$resources = Find-ResourceFiles -Path ".\resources"
```

### `Get-ResourceSnapshot`
获取资源文件快照（哈希信息）。

**参数**:
- `ResourceFiles` (ResourceFileInfo[]): 资源文件数组

**返回值**: `ResourceFileHash[]` - 资源文件哈希数组

**示例**:
```powershell
$snapshot = Get-ResourceSnapshot -ResourceFiles $resources
```

### `Compare-ResourceSnapshot`
比较两个资源快照。

**参数**:
- `NewSnapshot` (ResourceFileHash[]): 新快照
- `OldSnapshot` (ResourceFileHash[]): 旧快照

**返回值**: `bool` - 快照是否相同

**示例**:
```powershell
$isSame = Compare-ResourceSnapshot -NewSnapshot $new -OldSnapshot $old
```

### `Write-ResourceSnapshot`
将资源快照保存到文件。

**参数**:
- `Snapshot` (ResourceFileHash[]): 资源快照
- `Path` (string): 保存路径

**示例**:
```powershell
Write-ResourceSnapshot -Snapshot $snapshot -Path ".\snapshot.json"
```

### `Read-ResourceSnapshot`
从文件读取资源快照。

**参数**:
- `Path` (string): 快照文件路径

**返回值**: `ResourceFileHash[]` - 读取的资源快照

**示例**:
```powershell
$snapshot = Read-ResourceSnapshot -Path ".\snapshot.json"
```

### `Compress-ResourceFiles`
将资源文件压缩为 ZIP 文件。

**参数**:
- `ResourceFiles` (ResourceFileInfo[]): 资源文件数组
- `DestinationPath` (string): 目标 ZIP 文件路径
- `CompressionLevel` (CompressionLevel, 可选): 压缩级别，默认为 Optimal
- `Force` (switch, 可选): 强制覆盖现有文件

**示例**:
```powershell
Compress-ResourceFiles -ResourceFiles $resources -DestinationPath ".\resource.zip"
```

### `Get-ResourceEmbedModule`
创建资源嵌入模块。

**参数**:
- `ZipFilePath` (string): ZIP 文件路径

**返回值**: `InfinityModule` - 资源嵌入模块

**示例**:
```powershell
$resourceModule = Get-ResourceEmbedModule -ZipFilePath ".\resource.zip"
```

## 构建器模块函数

### `Build-InfinityModules`
构建并排序所有模块。

**参数**:
- `SourceConfig` (hashtable): 源代码配置

**返回值**: `InfinityModule[]` - 排序后的模块数组

**配置格式**:
```json
{
  "Source": {
    "Files": ["*.ps1", "*.psm1"]
  }
}
```

### `Build-ResourceEmbedModule`
构建资源嵌入模块。

**参数**:
- `ResourceConfig` (hashtable): 资源配置
- `Clean` (switch, 可选): 清理缓存

**返回值**: `InfinityModule` - 资源嵌入模块

**配置格式**:
```json
{
  "Resource": {
    "RootDir": "./resources"
  }
}
```

### `Build-PreDefinedsModule`
构建预定义变量模块。

**参数**:
- `Config` (hashtable): 预定义变量配置

**返回值**: `InfinityModule` - 预定义变量模块

**配置格式**:
```json
{
  "PreDefineds": {
    "AppName": "MyApp",
    "Version": "1.0.0",
    "Debug": true
  }
}
```

## 构建配置文件格式

完整的构建配置文件示例：

```json
{
  "Name": "myapp",
  "Mode": {
    "DevMode": "Debug"
  },
  "Source": {
    "Files": ["src/*.ps1"]
  },
  "Resource": {
    "RootDir": "./resources"
  },
  "PreDefineds": {
    "AppName": "MyApp",
    "Version": "1.0.0",
    "Debug": true
  }
}
```

## 模块文件格式

模块文件支持特殊的注释指令：

```powershell
## Module MyModule
## Import OtherModule

# 普通注释
function Get-Data {
    # 函数代码
}
```

**支持的指令**:
- `## Module <Name>`: 定义模块名称
- `## Import <ModuleName>`: 声明依赖模块

## 构建流程

1. **初始化**: 检查 PowerShell 版本，创建缓存目录
2. **读取配置**: 从 JSON 文件加载构建配置
3. **构建模块**: 按顺序构建所有模块
   - 预定义变量模块（如果配置）
   - 资源嵌入模块（如果配置）
   - 源代码模块（按依赖关系排序）
   - 主启动模块
4. **合并代码**: 将所有模块代码合并为单个文件
5. **生成输出**: 生成最终的 PowerShell 脚本文件
6. **调试信息**: 在 Debug 模式下生成调试信息文件

## 输出文件

- `<ProgramName>.ps1`: 合并后的 PowerShell 脚本
- `<ProgramName>.debug.json`（Debug模式下）: 调试信息，包含行号映射

## 缓存机制

工具使用 `.buildcache` 目录缓存：
- 资源快照 (`resource_snapshot.json`)
- 压缩的资源文件 (`resource.zip`)

使用 `-Clean` 参数可以清理缓存。

## 错误处理

工具使用异常机制处理错误：
- 版本不兼容时抛出异常
- 文件不存在时抛出异常
- 循环依赖检测抛出异常
- 构建失败时抛出异常

## 使用示例

```powershell
# 正常构建
.\infinity_build.ps1 -ConfigPath "build.json"

# 清理缓存后构建
.\infinity_build.ps1 -ConfigPath "build.json" -Clean
```

## 注意事项

1. 需要 PowerShell 7.0 或更高版本
2. 模块文件中的 `## Import` 指令必须引用实际存在的模块
3. 资源目录可以是任何有效的文件系统路径
4. 预定义变量支持字符串、整数和布尔类型
5. 模块名称在项目中必须唯一