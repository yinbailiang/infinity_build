# 日志库 API — `infinity_log.ps1`

`infinity_log.ps1` 是 Infinity Build 的日志子系统，提供多级别、带时间戳和彩色输出的结构化日志记录能力。

---

## 枚举

### `LogType`

定义日志级别。数值越大，级别越高（Debug 包含所有日志）。

| 名称 | 值 | 说明 |
| - | - | - |
| `LogErr` | `0` | 错误级别 |
| `LogWarn` | `1` | 警告级别 |
| `LogInfo` | `2` | 信息级别 |
| `LogDebug` | `3` | 调试级别（最详细） |

---

## 类

### `LogServer`

日志服务器，负责格式化并输出日志消息。控制日志级别、应用名称和颜色输出。

#### 构造函数

```powershell
[LogServer]::new([LogType]$Level)
[LogServer]::new([LogType]$Level, [string]$AppName)
```

| 参数 | 类型 | 说明 |
| - | - | - |
| `$Level` | `LogType` | 日志级别阈值，高于此级别的消息将被忽略 |
| `$AppName` | `string` | 可选，应用名称，将显示在日志前缀中 |

#### 属性

| 属性 | 类型 | 默认值 | 说明 |
| - | - | - | - |
| `LogLevel` | `LogType` | 构造时指定 | 当前日志级别 |
| `AppName` | `string` | `$null` | 应用名称 |
| `EnableColors` | `bool` | `$true` | 是否启用彩色输出 |

#### 方法

| 方法 | 返回 | 说明 |
| - | - | - |
| `FormatMessage([LogType]$Type, [string]$Text)` | `string` | 格式化日志消息 |
| `Write([LogType]$Type, [string]$Text)` | `void` | 写入日志（自动过滤级别） |

#### 日志输出颜色

| 级别 | 颜色 |
| - | - |
| `LogErr` | 亮红色 |
| `LogWarn` | 亮黄色 |
| `LogInfo` | 亮青色 |
| `LogDebug` | 亮蓝色 |

---

### `LogClient`

日志客户端，提供带**作用域上下文**的便捷日志方法。

#### 构造函数

```powershell
[LogClient]::new([LogServer]$Server)
[LogClient]::new([LogType]$Level)
```

| 参数 | 类型 | 说明 |
| - | - | - |
| `$Server` | `LogServer` | 关联的日志服务器实例 |
| `$Level` | `LogType` | 直接以指定级别创建内建 LogServer |

#### 属性

| 属性 | 类型 | 说明 |
| - | - | - |
| `Server` | `LogServer` | 关联的日志服务器 |
| `Context` | `Stack[string]` | 当前作用域栈（先进后出） |

#### 方法

##### 日志写入方法

| 方法 | 说明 |
| - | - |
| `Error([string]$Message)` | 写入错误日志 |
| `Warn([string]$Message)` | 写入警告日志 |
| `Info([string]$Message)` | 写入信息日志 |
| `Debug([string]$Message)` | 写入调试日志 |

##### 作用域方法

```powershell
# 执行代码块并自动包裹作用域（含错误处理）
[object] Scope([string]$ScopeName, [scriptblock]$ScriptBlock)

# 执行代码块并自动包裹作用域（含耗时统计）
[object] MeasureScope([string]$ScopeName, [scriptblock]$ScriptBlock)

# 手动开始一个作用域
[void] StartScope([string]$ScopeName)

# 手动结束最近的作用域
[void] EndScope()
```

> `Scope` 和 `MeasureScope` 会在执行前后自动打印 "开始" 和 "完成" 日志。
> `MeasureScope` 额外输出执行耗时（精确到毫秒）。
> 若 `ScriptBlock` 抛出异常，会自动捕获并重新抛出，同时记录错误日志。

---

## 输出格式

```
[2026-05-24 10:30:45][AppName][INFO-] 应用启动
[2026-05-24 10:30:45][AppName][INFO-] [Data.Load] 开始: 加载配置
[2026-05-24 10:30:45][AppName][INFO-] [Data.Load] 完成: 加载配置
[2026-05-24 10:30:45][AppName][ERROR] [Data.Load] 配置文件不存在
```

- 时间戳格式：`yyyy-MM-dd HH:mm:ss`
- 作用域前缀：`[Scope1.Scope2...]`

---

## 使用示例

### 基本用法

```powershell
. ./infinity_log.ps1

$server = [LogServer]::new([LogType]::LogDebug, "MyApp")
$log = [LogClient]::new($server)

$log.Info("服务启动中...")
$log.Debug("配置值: port=8080")
$log.Warn("磁盘空间不足")
$log.Error("连接数据库失败")
```

### 作用域用法

```powershell
$log.Scope("初始化", {
    $log.Info("加载模块...")
    # ... 初始化代码 ...
})

# 带耗时统计
$result = $log.MeasureScope("数据处理", {
    Start-Sleep -Seconds 2
    return "处理完成"
})
# 输出: 完成: 数据处理
# 输出: 耗时: 2.015s

# 手动作用域
$log.StartScope("阶段一")
$log.Info("执行中...")
$log.EndScope()
```

### 仅显示错误和警告

```powershell
$server = [LogServer]::new([LogType]::LogWarn, "Monitor")
$log = [LogClient]::new($server)

$log.Info("这行不会输出")   # 级别高于 LogWarn，被过滤
$log.Warn("这行会输出")     # 级别等于 LogWarn，通过
$log.Error("这行也会输出")  # 级别低于 LogWarn，通过
```

### 禁用彩色输出

```powershell
$server = [LogServer]::new([LogType]::LogDebug, "CI")
$server.EnableColors = $false
$log = [LogClient]::new($server)
```

---

## 模块加载保护

`infinity_log.ps1` 通过 `$Script:LogLoaded` 变量防止重复加载。被其他模块（如 `infinity_build.ps1`、`infinity_nuget.ps1`）引用时，会自动跳过类型重定义，避免错误。

```powershell
# 在其他脚本中安全引用
if (-not $Script:LogLoaded) {
    . (Join-Path $PSScriptRoot 'infinity_log.ps1')
}
```
