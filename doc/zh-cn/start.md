# 快速开始

Infinity Build 是一个为 PowerShell 设计的程序开发套件，可将模块化的 `.psm1` 源文件编译为单一可执行脚本。

## 项目概述

Infinity Build 通过 `psproject.json` 配置文件描述构建流程，将分散的 PowerShell 模块源文件按依赖顺序合并、去注释、压缩，最终生成独立的 `.ps1` 输出脚本。

### 核心特性

- **模块化构建** — 源文件通过 `##Module` / `##Import` 预处理指令声明模块名与依赖关系
- **拓扑排序** — 自动解析模块依赖，确保正确的代码拼接顺序
- **注释剥离** — 移除注释与空白行，减小输出体积
- **源映射** — 生成 `.debug.json` 调试文件，将输出行号映射回源文件位置
- **多构建器** — 支持 Source、Std、PreDefineds、Resource、NuGet、Boot 等构建步骤
- **行移除指令** — 支持 `#infb: rm` 指令标记需要移除的调试/测试代码行

## 环境要求

- **PowerShell 7.0+**（推荐）
- 操作系统：Windows / Linux / macOS

## 快速入门

### 1. 准备项目结构

```Text
my-project/
├── psproject.json          # 构建配置文件
├── src/
│   ├── core/
│   │   ├── __init__.psm1
│   │   ├── utils.psm1
│   │   └── logger.psm1
│   ├── builders/
│   │   ├── __init__.psm1
│   │   └── mybuilder.psm1
│   └── main.psm1
└── res/                    # 可选：资源文件
```

### 2. 编写构建配置 `psproject.json`

```json
{
    "System": {
        "Name": "my_project",
        "Version": "1.0.0",
        "Mode": "Release",
        "CacheDir": ".infinity_build"
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [
            { "APP_NAME": "my_project" },
            { "APP_VERSION": "1.0.0" }
        ]
    },
    "Source": {
        "Files": [
            "src/core/*.psm1",
            "src/builders/*.psm1",
            "src/main.psm1"
        ]
    },
    "Boot": {
        "EntryPoint": "Invoke-Main",
        "Require": "Main"
    }
}
```

### 3. 编写源模块

源模块使用 `##Module` 声明模块名，`##Import` 声明依赖：

```powershell
##Module Main
##Import Core.Utils
##Import Core.Logger

function Invoke-Main {
    param(
        [string]$Name = "World"
    )
    Write-Host "Hello, $Name!"
    #infb: rm
    Write-Host "DEBUG: 这行在发布构建中会被移除" #infb: rm
}
```

### 4. 执行构建

```powershell
./infinity_build.ps1
```

构建成功后，输出文件位于项目根目录：

- `my_project.ps1` — 合并后的独立脚本
- `my_project.debug.json` — 行号映射调试文件

## 文档导航

- [构建配置指南](build-config.md) — 深入了解 `psproject.json` 各配置项
- [文档中心](../index.md) — 返回文档首页
