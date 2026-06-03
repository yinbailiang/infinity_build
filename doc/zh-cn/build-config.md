# 构建配置指南

本文档详细说明 `psproject.json` 构建配置文件的各项参数。

## 配置结构

`psproject.json` 是一个 JSON 格式的配置文件，顶层包含系统配置（`System`）和多个构建步骤。每个构建步骤对应一个构建器（Builder），按 JSON 中的定义顺序依次执行。

```json
{
    "System": { ... },
    "PreDefineds": { ... },
    "Source": { ... },
    "Std": { ... },
    "Resource": { ... },
    "Nuget": { ... },
    "Boot": { ... }
}
```

---

## System — 系统配置

定义项目元信息和构建行为。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| ---- | ---- | ---- | ------ | ---- |
| `Name` | string | 否 | 配置文件名（不含扩展名） | 项目名称，同时作为默认输出文件名 |
| `Version` | string | 否 | — | 项目版本号 |
| `Mode` | string | 否 | `"Debug"` | 构建模式：`Debug` 或 `Release` |
| `CacheDir` | string | 否 | `".infinity_build"` | 缓存目录路径（相对路径基于项目根目录） |

### 示例

```json
"System": {
    "Name": "my_tool",
    "Version": "2.1.0",
    "Mode": "Release",
    "CacheDir": ".build_cache"
}
```

---

## Output — 输出配置

控制输出文件的路径。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| ---- | ---- | ---- | ------ | ---- |
| （字符串值） | string | 否 | `"{Name}.ps1"` | 输出脚本的路径 |

### 示例

```json
"Output": "bin/my_tool.ps1"
```

---

## Source — 源文件构建器

收集并解析源模块文件。

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| `Files` | string[] | 是 | 源文件路径数组，格式为 `目录/文件模式`，如 `src/core/*.psm1`（仅单层目录匹配） |

### 示例

```json
"Source": {
    "Files": [
        "src/core/*.psm1",
        "src/builders/*.psm1",
        "src/main.psm1"
    ]
}
```

### 源文件预处理指令

源文件通过注释形式的预处理指令声明模块信息：

| 指令 | 格式 | 说明 |
| ---- | ---- | ---- |
| `##Module` | `##Module <Name>` | 声明模块名称，覆盖文件名作为模块名 |
| `##Import` | `##Import <ModuleName>` | 声明依赖模块，确保被依赖模块先于当前模块拼接 |
| `#infb: rm` | `#infb: rm` | 行末移除指令，标记该行在构建时被移除（用于调试代码） |

```powershell
##Module Core.Logger

function Write-Log {
    param([string]$Message)
    Write-Host "[LOG] $Message"
    #infb: rm
    Write-Host "DEBUG: verbose log" #infb: rm
}
```

---

## Std — 标准库构建器

引入 Infinity Build 内置标准库模块。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| ---- | ---- | ---- | ------ | ---- |
| `Enable` | bool | 否 | `false` | 是否启用标准库 |

标准库提供 NuGet 框架解析、NuGet 版本管理等基础功能。通过 `std/std.json` 配置文件控制包含哪些标准库模块。

### 示例

```json
"Std": {
    "Enable": true
}
```

---

## PreDefineds — 预定义变量构建器

在构建时注入编译期常量，生成 `Builtin.PreDefineds` 模块。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| ---- | ---- | ---- | ------ | ---- |
| `Default` | bool | 否 | `false` | 是否注入默认系统变量（`$BuildName` / `$BuildVersion` / `$BuildMode`） |
| `Defineds` | object[] | 否 | `[]` | 自定义预定义变量数组，每项为 `{ "key": "value" }` |

### 默认系统变量

当 `Default` 为 `true` 时，自动从 `System` 配置注入以下变量：

| 变量 | 类型 | 来源 | 说明 |
| ---- | ---- | ---- | ---- |
| `$BuildName` | string | `System.Name` | 项目名称 |
| `$BuildVersion` | string | `System.Version` | 项目版本号 |
| `$BuildMode` | string | `System.Mode` | 构建模式（`Debug` 或 `Release`） |

### 示例

```json
"PreDefineds": {
    "Default": true,
    "Defineds": [
        { "APP_NAME": "my_tool" },
        { "BUILD_TIME": "2026-01-01" }
    ]
}
```

---

## Resource — 资源构建器

将外部资源文件（图标、配置文件等）打包嵌入输出脚本。

| 字段 | 类型 | 必填 | 默认值 | 说明 |
| ---- | ---- | ---- | ------ | ---- |
| `Type` | string | 否 | `"Builtin"` | 资源类型：`Builtin`（内嵌到脚本）或 `External`（输出为独立 zip 文件） |
| `resources` | object[] | 否 | `[]` | 资源映射数组，每项为 `{ "source目录": "目标前缀" }` |
| `OutputDir` | string | 否 | 当前目录 | [仅 External] 外部资源输出目录 |
| `OutputName` | string | 否 | `"{Name}-resources.zip"` | [仅 External] 外部资源输出文件名 |

### 示例

```json
"Resource": {
    "Type": "Builtin",
    "resources": [
        { "res/icon.png": "assets/icon.png" },
        { "res/config.json": "config/default.json" }
    ]
}
```

---

## Nuget — NuGet 包构建器

管理 NuGet 包依赖，自动下载和引用包。

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| `PackagesPath` | string | 是 | NuGet 包库目录路径 |
| `Sources` | string[] | 是 | NuGet 源地址数组（取首个），如 `["https://api.nuget.org/v3/index.json"]` |
| `Packs` | object[] | 否 | NuGet 包列表，每项为 `{ "包ID": "版本号" }` |

### 示例

```json
"Nuget": {
    "PackagesPath": ".packages",
    "Sources": ["https://api.nuget.org/v3/index.json"],
    "Packs": [
        { "Newtonsoft.Json": "13.0.3" }
    ]
}
```

---

## Boot — 启动构建器

生成程序入口点，调用指定的入口函数。

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| `EntryPoint` | string | 是 | 入口函数名称 |
| `Require` | string | 否 | 入口函数所在的模块名称。指定后会自动剔除未被引用的模块 |

### 示例

```json
"Boot": {
    "EntryPoint": "Invoke-Main",
    "Require": "Main"
}
```

生成的启动代码大致为：

```powershell
# ... 所有模块代码 ...

# 执行入口（转发所有命令行参数）
Invoke-Main @args
```

---

## 完整配置示例

```json
{
    "System": {
        "Name": "my_app",
        "Version": "1.0.0",
        "Mode": "Release",
        "CacheDir": ".infinity_build"
    },
    "Output": "bin/my_app.ps1",
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "APP_NAME": "my_app" }
        ]
    },
    "Std": {
        "Enable": true
    },
    "Source": {
        "Files": [
            "src/core/*.psm1",
            "src/builders/*.psm1",
            "src/main.psm1"
        ]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [
            { "res/icon.png": "assets/icon.png" }
        ]
    },
    "Boot": {
        "EntryPoint": "Invoke-Main",
        "Require": "Main"
    }
}
```

---

## 文档导航

- [快速开始](start.md) — 五分钟上手指南
- [文档中心](../index.md) — 返回文档首页
