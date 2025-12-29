# <center>Infinity Log API 文档</center>

## <center>概述</center>

`infinity_log.ps1` 是一个 PowerShell 日志库，提供多级别、彩色化的日志输出系统。支持日志级别控制、调用上下文追踪、执行时间测量等功能。

## <center>枚举类型</center>

### `LogType`
定义日志级别枚举，数值越低表示越严重。

<center>

|   枚举值   |数值|      描述       |  颜色  |
|------------|---|-----------------|-------|
| `LogErr`   | 0 | 错误级别(最高)   | 亮红色 |
| `LogWarn`  | 1 | 警告级别         | 亮黄色 |
| `LogInfo`  | 2 | 信息级别         | 亮青色 |
| `LogDebug` | 3 | 调试级别(最低)   | 亮蓝色 |

</center>

## <center>类结构</center>

### `LogServer`

<details> <summary>日志服务器，负责日志格式化和输出控制。</summary>

#### 构造函数:

**`LogServer([LogType] $Level)`**
创建一个指定日志级别的日志服务器。

**参数**:
- `$Level` (`LogType`): 日志级别，只输出该级别及以下的日志

**示例**:
```powershell
$server = [LogServer]::new([LogType]::LogInfo)
```

---

**`LogServer([LogType] $Level, [string] $AppName)`**
创建一个指定日志级别和应用名称的日志服务器。

**参数**:
- `$Level` (`LogType`): 日志级别
- `$AppName` (`string`): 应用名称，将显示在日志中（可选）

**示例**:
```powershell
$server = [LogServer]::new([LogType]::LogDebug, "MyApp")
```

---

#### 属性

| 属性名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `LogLevel` | `LogType` | 必需 | 当前日志级别，只输出数值小于等于此级别的日志 |
| `AppName` | `string` | `$null` | 应用名称标识（可选） |
| `EnableColors` | `bool` | `$true` | 是否启用彩色输出 |

---

#### 方法

**`FormatMessage([LogType] $Type, [string] $Text)`**
格式化日志消息。

**参数**:
- `$Type` (`LogType`): 日志类型
- `$Text` (`string`): 日志文本

**返回值**: `string` - 格式化后的日志消息

**格式**:
- 有应用名: `[时间戳][应用名][级别]消息`
- 无应用名: `[时间戳][级别]消息`

**示例**:
```powershell
$server.Write([LogType]::LogInfo, "操作开始")
```
**返回**: `[2024-01-15 10:30:00][MyApp][INFO-]操作开始`

---

**`Write([LogType] $Type, [string] $Text)`**
写入日志消息。

**参数**:
- `$Type` (`LogType`): 日志类型
- `$Text` (`string`): 日志文本

**行为**: 如果日志类型数值大于当前日志级别，则忽略该消息（数值越高表示级别越低）。

**示例**:
```powershell
$server.Write([LogType]::LogInfo, "操作开始")
```

---

**`WriteColored([LogType] $Type, [string] $Message)`**
**隐藏方法**: 使用ANSI颜色代码输出彩色日志。

**参数**:
- `$Type` (`LogType`): 日志类型
- `$Message` (`string`): 格式化后的消息

**颜色映射**:
- `LogErr`: 亮红色 (ANSI 91)
- `LogWarn`: 亮黄色 (ANSI 93)
- `LogInfo`: 亮青色 (ANSI 96)
- `LogDebug`: 亮蓝色 (ANSI 94)

</details>

### `LogClient`

<details> <summary>日志客户端，提供便捷的日志方法和上下文管理。</summary>

#### 构造函数

**`LogClient([LogServer] $Server)`**
使用指定的日志服务器创建客户端。

**参数**:
- `$Server` (`LogServer`): 日志服务器实例

**示例**:
```powershell
$client = [LogClient]::new($server)
```

---

**`LogClient([LogType] $Level)`**
创建带有新日志服务器的客户端。

**参数**:
- `$Level` (`LogType`): 日志级别

**示例**:
```powershell
$client = [LogClient]::new([LogType]::LogDebug)
```

---

#### 属性

| 属性名 | 类型 | 描述 |
|--------|------|------|
| `Server` | `LogServer` | 关联的日志服务器 |
| `Context` | `Stack<string>` | 上下文堆栈，记录当前执行上下文 |

---

#### 上下文方法

**`Scope([string] $ScopeName, [scriptblock] $ScriptBlock)`**
创建一个带上下文的执行作用域。

**参数**:
- `$ScopeName` (`string`): 作用域名称
- `$ScriptBlock` (`scriptblock`): 要执行的脚本块

**返回值**: `object` - 脚本块的执行结果

**行为**:
1. 将作用域名称推入上下文堆栈
2. 记录作用域开始日志
3. 执行脚本块
4. 记录作用域完成日志
5. 从上下文堆栈弹出作用域名称
6. 发生异常时记录错误并重新抛出

**示例**:
```powershell
$client.Scope("数据处理", {
    $data = Get-Content "data.json"
    return $data
})
```

---

**`MeasureScope([string] $ScopeName, [scriptblock] $ScriptBlock)`**
创建一个带时间测量的执行作用域。

**参数**:
- `$ScopeName` (`string`): 作用域名称
- `$ScriptBlock` (`scriptblock`): 要执行的脚本块

**返回值**: `object` - 脚本块的执行结果

**行为**: 与 `Scope` 方法类似，但额外记录执行耗时。

**示例**:
```powershell
$client.MeasureScope("数据处理", {
    Start-Sleep -Seconds 2
    return "完成"
})
# 输出: [2024-01-15 10:30:00][App][INFO-][数据处理] 耗时: 2.000s
```

---

**`StartScope([string] $ScopeName)`**
手动开始一个作用域。

**参数**:
- `$ScopeName` (`string`): 作用域名称

**行为**: 将作用域名称推入上下文堆栈并记录开始日志。需要配合 `EndScope` 使用。

**示例**:
```powershell
$client.StartScope("数据处理")
# ... 处理逻辑 ...
$client.EndScope()
```

---

**`EndScope()`**
手动结束当前作用域。

**行为**: 从上下文堆栈弹出作用域名称并记录完成日志。

**注意**: 必须与 `StartScope` 配对使用。

---

#### 日志便捷方法

以下方法自动处理上下文前缀，并委托给关联的 `LogServer`。

**`Error([string] $Message)`**
记录错误级别日志。

**参数**:
- `$Message` (`string`): 错误消息

**示例**:
```powershell
$client.Error("文件不存在: data.json")
```

---

**`Warn([string] $Message)`**
记录警告级别日志。

**参数**:
- `$Message` (`string`): 警告消息

**示例**:
```powershell
$client.Warn("使用默认配置")
```

---

**`Info([string] $Message)`**
记录信息级别日志。

**参数**:
- `$Message` (`string`): 信息消息

**示例**:
```powershell
$client.Info("处理完成")
```

---

**`Debug([string] $Message)`**
记录调试级别日志。

**参数**:
- `$Message` (`string`): 调试消息

**示例**:
```powershell
$client.Debug("变量值: $value")
```

---

**`WriteInternal([LogType] $Type, [string] $Message)`**
**隐藏方法**: 内部写入方法，自动添加上下文前缀。

</details>

## <center>日志格式</center>

### 格式说明
- 有应用名: `[时间戳][应用名][级别][上下文] 消息内容`
- 无应用名: `[时间戳][级别][上下文] 消息内容`

### 级别显示
```
ERROR   - 错误级别 (LogErr)
WARN-   - 警告级别 (LogWarn)
INFO-   - 信息级别 (LogInfo)
DEBUG   - 调试级别 (LogDebug)
```

### 示例输出
```
[2024-01-15 10:30:00][MyApp][INFO-] 应用程序启动
[2024-01-15 10:30:01][MyApp][INFO-][数据处理] 开始: 数据读取
[2024-01-15 10:30:01][MyApp][WARN-][数据处理] 使用默认配置
[2024-01-15 10:30:02][MyApp][DEBUG][数据处理] 读取了 100 行数据
[2024-01-15 10:30:02][MyApp][INFO-][数据处理] 完成: 数据读取
[2024-01-15 10:30:02][MyApp][INFO-][数据处理] 耗时: 1.234s
```

## <center>使用示例</center>

### 基本用法
```powershell
# 导入模块
. .\infinity_log.ps1

# 创建日志服务端
$server = [LogServer]::new([LogType]::LogInfo)

# 创建日志客户端
$logger = [LogClient]::new($server)
# 或者直接使用隐式的服务端创建
# $logger = [LogClient]::new([LogType]::LogInfo)

# 记录不同级别的日志
$logger.Info("应用程序启动")
$logger.Warn("配置未找到，使用默认值")
$logger.Error("无法连接到数据库")

# 使用作用域
$result = $logger.Scope("数据处理", {
    $logger.Info("处理开始")
    # ... 处理逻辑 ...
    return $data
})

# 带测量的作用域
$logger.MeasureScope("复杂计算", {
    # ... 耗时计算 ...
})
```

### 自定义应用名称
```powershell
# 创建自定义服务器
$server = [LogServer]::new([LogType]::LogDebug, "MyApplication")
$logger = [LogClient]::new($server)

# 使用客户端
$logger.Info("MyApplication启动")
# 输出: [2024-01-15 10:30:00][MyApplication][INFO-] MyApplication启动
```

### 嵌套上下文
```powershell
$logger.Scope("外部处理", {
    $logger.Info("开始外部处理")
    
    $logger.Scope("内部处理", {
        $logger.Info("开始内部处理")
        # 嵌套上下文下的日志
        $logger.Debug("调试信息")
    })
})
# 输出: [2024-01-15 10:30:00][App][INFO-][外部处理] 开始外部处理
# 输出: [2024-01-15 10:30:00][App][INFO-][外部处理.内部处理] 开始内部处理
# 输出: [2024-01-15 10:30:00][App][DEBUG][外部处理.内部处理] 调试信息
```

### 手动作用域管理
```powershell
$logger.StartScope("长时间运行任务")
try {
    # ... 长时间运行的处理 ...
    $logger.Info("处理步骤1完成")
    # ... 更多处理 ...
    $logger.Info("处理步骤2完成")
}
finally {
    $logger.EndScope()
}
```

## <center>高级配置</center>

### 禁用彩色输出
```powershell
$server = [LogServer]::new([LogType]::LogInfo, "MyApp")
$server.EnableColors = $false
$logger = [LogClient]::new($server)
```

### 动态调整日志级别
```powershell
$logger = [LogClient]::new([LogType]::LogInfo)

# 初始只显示Info及以下级别（数值小于等于2）
$logger.Debug("这条不会显示")  # 被过滤（Debug数值3 > Info数值2）

# 切换为Debug级别
$logger.Server.LogLevel = [LogType]::LogDebug
$logger.Debug("这条现在会显示")  # 正常输出
```

## <center>最佳实践</center>

1. **合理使用日志级别**:
   - `Error`: 用于不可恢复的错误（数值0）
   - `Warn`: 用于可恢复的问题或需要注意的情况（数值1）
   - `Info`: 用于关键业务步骤（数值2）
   - `Debug`: 用于详细的调试信息（数值3）

2. **使用作用域管理复杂流程**:
   ```powershell
   $logger.Scope("数据处理", {
       $logger.Scope("数据读取", { ... })
       $logger.Scope("数据清洗", { ... })
       $logger.Scope("数据保存", { ... })
   })
   ```

3. **测量性能关键部分**:
   ```powershell
   $logger.MeasureScope("性能敏感操作", {
       # 需要优化的代码
   })
   ```

4. **避免过度日志**:
   - 生产环境使用 `LogInfo` 或 `LogWarn` 级别
   - 开发环境使用 `LogDebug` 级别
   - 注意：级别数值越小表示越重要，`LogDebug` 是最高数值（3）

5. **异常处理**:
   - 在作用域内使用 try-catch 确保异常被适当记录
   - `Scope` 和 `MeasureScope` 方法会自动捕获并重新抛出异常

## <center>注意事项</center>

1. **日志级别逻辑**: 数值越低表示级别越高（越重要），只有数值小于等于 `LogLevel` 的日志才会被输出
2. **ANSI颜色支持**: 需要终端支持 ANSI 转义码，现代 PowerShell 和终端通常都支持
3. **作用域嵌套**: 确保每个 `StartScope` 都有对应的 `EndScope` 调用
4. **异常处理**: `Scope` 和 `MeasureScope` 会重新抛出异常，确保外部有适当的异常处理
5. **性能考虑**: 频繁的 `Debug` 日志在高性能场景下可能影响性能

## <center>故障排除</center>

### 日志不显示
1. 检查日志级别设置：确保日志类型数值小于等于当前日志级别
2. 确认 `EnableColors` 设置不影响内容输出
3. 检查 PowerShell 版本（需要支持 ANSI 颜色代码）

### 颜色不显示
1. 确保 `EnableColors` 为 `$true`
2. 检查终端是否支持 ANSI 转义码
3. 某些 PowerShell 主机可能需要特殊配置
4. 在 Windows 10+ 的 PowerShell 5.1 中可能需要设置 `$host.UI.RawUI` 支持

### 上下文嵌套问题
- 确保每个 `Scope` 调用都有对应的结束
- 避免在嵌套作用域中手动修改 `Context` 堆栈
- 使用 `StartScope`/`EndScope` 时确保成对调用

### 性能测量不准确
- `MeasureScope` 使用 `Stopwatch`，精度足够大多数场景
- 对于极短时间的操作，测量可能不够精确
- 考虑在多次运行后取平均值