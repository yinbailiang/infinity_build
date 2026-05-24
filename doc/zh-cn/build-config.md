# 构建配置指南

Infinity Build 使用 JSON 配置文件来驱动整个构建流程。本文档详细说明配置文件的每一项参数。

---

## 配置文件结构

配置文件是一个顶层的 JSON 对象，包含 `System` 元信息节和若干构建步骤。每个顶层键（除 `System` 外）对应一个**构建步骤**。

```json
{
    "System": { ... },
    "Source": { ... },
    "Resource": { ... },
    "PreDefineds": { ... },
    "Nuget": { ... },
    "Boot": { ... },
    "Output": "build/output.ps1"
}
```

---

## System 节（项目元信息）

| 字段 | 类型 | 必选 | 默认值 | 说明 |
| - | - | - | - | - |
| `Name` | `string` | 否 | 配置文件名 | 项目名称，影响输出文件命名及内置变量 |
| `Version` | `string` | 否 | — | 项目版本号，可通过 `$BuildVersion` 访问 |
| `Mode` | `string` | 否 | `"Debug"` | 构建模式：`"Debug"`（详细日志），`"Release"` |
| `CacheDir` | `string` | 否 | `".infinity_build"` | 缓存目录，相对路径基于配置文件所在目录 |

```json
"System": {
    "Name": "MyProject",
    "Version": "1.0.0",
    "Mode": "Debug",
    "CacheDir": ".infinity_build"
}
```

---

## Source 构建步骤（源代码处理）

解析指定的 PowerShell 源文件为模块，进行拓扑排序。

| 字段 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `Files` | `string[]` | 是 | 源文件 glob 模式列表，如 `["src/**/*.ps1"]` |

```json
"Source": {
    "Files": [
        "src/core/*.ps1",
        "src/utils/*.ps1",
        "src/main.ps1"
    ]
}
```

### 源码中的预处理指令

源码支持以下行内构建标签 `#infb:`：

| 指令 | 说明 |
| - | - |
| `#infb: rm` | 在构建输出中移除此行 |
| `#infb: debug` | 仅在 Debug 模式保留此行 |
| `#infb: release` | 仅在 Release 模式保留此行 |
| `#infb: replace <内容>` | 将此行替换为指定内容 |

源码还支持以下块级预处理指令 `##`：

| 指令 | 说明 |
| - | - |
| `## Module <名称>` | 声明模块名称 |
| `## Import <模块名>` | 声明模块依赖 |

---

## Resource 构建步骤（资源处理）

打包静态资源文件。

| 字段 | 类型 | 必选 | 默认值 | 说明 |
| - | - | - | - | - |
| `Type` | `string` | 否 | `"Builtin"` | 资源类型：`"Builtin"`（嵌入脚本），`"External"`（输出 ZIP） |
| `resources` | `hashtable[]` | 是 | — | 源目录到目标路径的映射数组 |
| `OutputDir` | `string` | 否 | 工作目录 | 外部资源输出目录（仅 `Type=External` 时有效） |
| `OutputName` | `string` | 否 | `<Name>-resources.zip` | 外部资源输出文件名 |

**内置模式示例：**

```json
"Resource": {
    "Type": "Builtin",
    "resources": [
        { "assets/images/": "images" },
        { "assets/config/": "config" }
    ]
}
```

**外部模式示例：**

```json
"Resource": {
    "Type": "External",
    "OutputDir": "build",
    "OutputName": "game-resources.zip",
    "resources": [
        { "assets/": "" }
    ]
}
```

---

## PreDefineds 构建步骤（预定义变量）

在构建输出中注入预定义变量。

| 字段 | 类型 | 必选 | 默认值 | 说明 |
| - | - | - | - | - |
| `Default` | `bool` | 否 | `false` | 是否注入默认系统变量（`$BuildName`, `$BuildVersion`, `$BuildMode`） |
| `Defineds` | `hashtable[]` | 否 | `[]` | 自定义变量数组，支持 `string`、`int`、`bool` 类型 |

```json
"PreDefineds": {
    "Default": true,
    "Defineds": [
        { "AppName": "我的应用" },
        { "MaxRetries": 3 },
        { "EnableFeatureX": true }
    ]
}
```

---

## Nuget 构建步骤（NuGet 依赖管理）

自动下载和管理 NuGet 包依赖。

| 字段 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `Sources` | `string[]` | 是 | NuGet 包源 URL 列表（使用第一个源） |
| `Packs` | `hashtable[]` | 是 | 要安装的包列表，每个元素为 `{ "包ID": "版本号" }` 对象。版本号填写 `"Latest"` 表示始终获取最新版本 |
| `PackagesPath` | `string` | 是 | 包库本地存储路径 |

```json
"Nuget": {
    "Sources": ["https://api.nuget.org/v3/index.json"],
    "Packs": [
        { "Newtonsoft.Json": "13.0.3" },
        { "Serilog": "Latest" }
    ],
    "PackagesPath": "packages"
}
```

---

## Boot 构建步骤（启动入口）

生成程序入口点，调用指定函数。

| 字段 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `EntryPoint` | `string` | 是 | 入口函数名 |
| `Require` | `string` | 否 | 声明对某个模块的依赖 |

```json
"Boot": {
    "EntryPoint": "Main",
    "Require": "Core"
}
```

---

## Output

指定构建输出文件的路径。相对路径基于配置文件所在目录。

| 类型 | 必选 | 说明 |
| - | - | - |
| `string` | 否 | 输出 `.ps1` 文件路径，默认为 `<Name>.ps1` |

```json
"Output": "build/myapp.ps1"
```

---

## ExtraConfig（编程接口扩展）

通过 `-ExtraConfig` 参数可以在调用 `infinity_build.ps1` 时动态注入额外的构建步骤配置：

```powershell
.\infinity_build.ps1 -ConfigPath ".\base.json" -ExtraConfig @{
    "Boot" = @{
        "EntryPoint" = "CustomMain"
    }
}
```

ExtraConfig 中的键会覆盖或追加到配置文件的构建步骤中。

---

## 完整配置示例

```json
{
    "System": {
        "Name": "MyTool",
        "Version": "2.0.0",
        "Mode": "Release",
        "CacheDir": ".build_cache"
    },
    "Source": {
        "Files": ["src/**/*.ps1"]
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "ToolName": "MyTool" },
            { "LogRetentionDays": 30 }
        ]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [
            { "config/": "config" },
            { "templates/": "templates" }
        ]
    },
    "Boot": {
        "EntryPoint": "Start-Tool",
        "Require": "Core"
    },
    "Output": "dist/MyTool.ps1"
}
```
