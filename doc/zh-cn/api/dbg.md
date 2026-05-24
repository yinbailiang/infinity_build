# 调试工具 API — `infinity_dbg.ps1`

`infinity_dbg.ps1` 是 Infinity Build 的调试器，用于运行 `infinity_build.ps1` 生成的带调试信息的构建产物。当程序出错时，它能将合并脚本中的行号映射回原始源文件的行号。

---

## 参数

| 参数 | 类型 | 必选 | 说明 |
| - | - | - | - |
| `-ScriptPath` | `string` | 是 | 要调试的脚本文件路径（即构建产物的 `.ps1` 文件） |

```powershell
.\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1"
```

> 传递给被调试脚本的额外参数会自动透传：
> ```powershell
> .\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1" -Mode "Production" -Verbose
> ```

---

## 工作原理

### 调试映射文件

调试器依赖构建过程生成的 `.debug.json` 文件。该文件与构建产物位于同一目录，文件名规则为：

```
<脚本名称>.debug.json
```

例如 `output.ps1` 对应的调试文件为 `output.debug.json`。

**映射文件格式**：

```json
[
    {
        "OutputLine": 15,
        "SourceFile": "C:\\project\\src\\core.ps1",
        "SourceLineNum": 42
    },
    {
        "OutputLine": 16,
        "SourceFile": "C:\\project\\src\\core.ps1",
        "SourceLineNum": 43
    }
]
```

- `OutputLine`：合并后输出脚本中的行号
- `SourceFile`：原始源文件的完整路径
- `SourceLineNum`：原始源文件中的行号

### 错误处理流程

1. 执行目标脚本（`.` source 方式，在当前作用域运行）
2. 若脚本正常执行完毕，调试器报告"执行完毕"
3. 若脚本抛出异常：
   - 打印错误消息
   - 打印调用堆栈跟踪
   - 对每个堆栈帧，尝试将输出行号映射回源文件行号
   - 在原始堆栈信息下方打印 `-> at <源文件>: line <源行号>` 映射结果

### 无调试信息的情况

如果找不到 `.debug.json` 文件或解析失败，调试器仍会正常执行脚本并捕获错误，但无法提供源文件行号映射。调试器会发出警告提示。

---

## 输出示例

### 正常执行

```
[2026-05-24 10:30:45][InfinityDbg][INFO-] 调试程序: output.ps1
[2026-05-24 10:30:45][InfinityDbg][INFO-] 已加载调试信息: ...\output.debug.json
[2026-05-24 10:30:45][InfinityDbg][INFO-] 开始执行程序
...（被调试程序的正常输出）...
[2026-05-24 10:30:46][InfinityDbg][INFO-] 执行完毕
```

### 错误执行（含映射）

```
[2026-05-24 10:30:45][InfinityDbg][INFO-] 调试程序: output.ps1
[2026-05-24 10:30:45][InfinityDbg][INFO-] 已加载调试信息: ...\output.debug.json
[2026-05-24 10:30:45][InfinityDbg][INFO-] 开始执行程序
[2026-05-24 10:30:45][InfinityDbg][ERROR] 执行时发生错误: 无法找到文件 'config.json'
[2026-05-24 10:30:45][InfinityDbg][INFO-] 调用堆栈跟踪:
[2026-05-24 10:30:45][InfinityDbg][INFO-] at <ScriptBlock>, C:\build\output.ps1: line 45
[2026-05-24 10:30:45][InfinityDbg][INFO-]     -> at C:\project\src\loader.ps1: line 128
[2026-05-24 10:30:45][InfinityDbg][INFO-] at <ScriptBlock>, C:\build\output.ps1: line 12
[2026-05-24 10:30:45][InfinityDbg][INFO-]     -> at C:\project\src\main.ps1: line 15
```

---

## 与构建流程的集成

```powershell
# 步骤 1：构建项目（生成 output.ps1 + output.debug.json）
.\infinity_build.ps1 -ConfigPath ".\myproject.json"

# 步骤 2：使用调试器运行
.\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1"

# 步骤 3：（可选）带参数调试
.\infinity_dbg.ps1 -ScriptPath ".\build\output.ps1" --verbose --config "prod.json"
```

---

## 日志配置

调试器内部使用 `infinity_log.ps1`，日志级别固定为 `LogDebug`，应用名称为 `InfinityDbg`。可以通过 `$Script:DbgLoggerServer.LogLevel` 调整日志详细程度：

```powershell
# 在引入调试器前调整（需要直接修改脚本或使用点源引入）
$Script:DbgLoggerServer.LogLevel = [LogType]::LogInfo  # 仅显示信息和错误
```

---

## 注意事项

1. **依赖声明**：调试器通过点源（`.`）方式执行脚本，因此脚本中的变量和函数会保留在当前作用域
2. **映射精度**：仅能映射已通过 `Get-InfinityModule` 解析的代码行。纯注释行、空白行和 `#infb: rm` 移除的行在输出中不存在，无法映射
3. **嵌套错误**：如果被调试脚本本身又调用了其他脚本，那些外部脚本的错误无法映射
4. **性能**：调试器以正常速度执行脚本，无额外性能开销（仅在异常时解析堆栈）
