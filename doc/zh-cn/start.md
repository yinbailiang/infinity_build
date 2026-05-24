# PowerShell 开发套件 — Infinity Build

Infinity Build 是一套为 PowerShell 7.0+ 环境设计的脚本开发与构建工具集，旨在提升 PowerShell 脚本的开发效率与工程化水平。

---

## 系统要求

- **PowerShell 版本**：7.0+
- **Git**（用于克隆仓库）

---

## 快速开始

### 1. 克隆仓库

打开 PowerShell，运行以下命令将项目克隆到本地：

```powershell
git clone https://github.com/yinbailiang/infinity_build.git
```

### 2. 进入项目目录

```powershell
Set-Location infinity_build
```

---

## API 文档

Infinity Build 由四个核心模块组成，每个模块提供独立的 PowerShell API：

### 模块概览

| 模块 | 文件 | 用途 |
|------|------|------|
| 日志库 | `infinity_log.ps1` | 多级别彩色日志输出、结构化日志记录 |
| 构建系统 | `infinity_build.ps1` | 模块解析、拓扑排序、资源打包、程序生成 |
| NuGet 管理 | `infinity_nuget.ps1` | 包搜索、下载、安装、卸载、更新 |
| 调试工具 | `infinity_dbg.ps1` | 错误捕获与源码行号映射 |

> 详细 API 文档请参阅：[日志库 API](api/log.md) | [构建模块 API](api/build.md) | [NuGet 管理 API](api/nuget.md) | [调试工具 API](api/dbg.md)

### 构建配置

Infinity Build 使用 JSON 配置文件驱动构建流程。配置文件结构如下：

```json
{
    "System": {
        "Name": "MyProject",
        "Mode": "Debug",
        "Version": "1.0.0",
        "CacheDir": ".infinity_build"
    },
    "Source": {
        "Files": ["src/**/*.ps1"]
    },
    "Resource": {
        "Type": "Builtin",
        "resources": [{ "assets/": "assets" }]
    },
    "PreDefineds": {
        "Default": true,
        "Defineds": [{ "AppName": "MyApp" }]
    },
    "Boot": {
        "EntryPoint": "Main",
        "Require": "Core"
    },
    "Output": "build/output.ps1"
}
```

> 完整配置说明请参阅：[构建配置指南](build-config.md)

### 快速示例

**示例 1：使用日志库**

```powershell
# 引入日志库
. ./infinity_log.ps1

# 创建日志服务器和客户端
$server = [LogServer]::new([LogType]::LogDebug, "MyApp")
$logger = [LogClient]::new($server)

# 记录日志
$logger.Info("应用启动")
$logger.Debug("调试信息")
$logger.Warn("警告信息")
$logger.Error("错误信息")

# 使用作用域
$logger.Scope("数据处理", {
    $logger.Info("正在处理...")
})
```

**示例 2：搜索 NuGet 包**

```powershell
. ./infinity_nuget.ps1

$source = New-NugetSource -Url "https://api.nuget.org/v3/index.json"
$results = Search-NugetPackage -Source $source -Query "Newtonsoft.Json" -Take 5
$results | Format-Table id, version
```

**示例 3：执行构建**

```powershell
.\infinity_build.ps1 -ConfigPath ".\myproject.json"
```

**示例 4：调试构建产物**

```powershell
.\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1"
```

---

## 获取帮助

如有使用问题或建议，请通过项目的 [Issues 页面](https://github.com/yinbailiang/infinity_build/issues) 进行反馈。

---

如果你觉得这个项目有帮助，欢迎点亮 ⭐ 支持！