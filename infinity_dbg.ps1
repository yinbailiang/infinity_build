<#
.NOTES
    Name: infinity_dbg
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    PowerShell 工具用于调试 infinity_build 生成的带有调试信息的项目
.DESCRIPTION
    这个工具提供以下功能：
    1. 运行打包的项目
    2. 尝试捕获错误
    3. 映射错误位置
#>

#region 输入参数
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [string[]]$ArgumentList = @()
)
#endregion

#region 日志
. (Join-Path -Path $PSScriptRoot -ChildPath 'infinity_log.ps1')
$Script:DbgLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityDbg")
$Script:DbgLogger = [LogClient]::new($Script:DbgLoggerServer)
#endregion

#region 启动虚拟环境
if (-not $Env:InInfinityDbgEnv) {
    $Script:DbgLogger.Info("进入虚拟环境")
    if ($ArgumentList.Count -ne 0){
        pwsh -CommandWithArgs "`$Env:InInfinityDbgEnv = `$True; . $PSCommandPath @args" "-ScriptPath" $ScriptPath "-ArgumentList" $ArgumentList 
    }else{
        pwsh -CommandWithArgs "`$Env:InInfinityDbgEnv = `$True; . $PSCommandPath @args" "-ScriptPath" $ScriptPath 
    }
    exit
}
#endregion

#region 初始化
if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
    $Script:DbgLogger.Error("未找到程序: $ScriptPath")
    throw "未找到程序: $ScriptPath"
}
$Script = Get-Item -Path $ScriptPath
    
$ProgramPath = $Script.FullName
$ProgramDebugInfoPath = [System.IO.Path]::ChangeExtension($ProgramPath, ".debug.json")
    
# 提取程序名称用于日志显示
$ProgramName = $Script.Name
$Script:DbgLogger.Info("调试程序: $ProgramName")
    
$DebugInfo = $null
if (Test-Path -Path $ProgramDebugInfoPath -PathType Leaf) {
    try {
        $DebugInfo = Get-Content -Path $ProgramDebugInfoPath -Raw | ConvertFrom-Json -AsHashtable
        $Script:DbgLogger.Info("已加载调试信息: $ProgramDebugInfoPath")
    }
    catch {
        $Script:DbgLogger.Warn("无法解析调试信息文件，将无法获得行号映射: $ProgramDebugInfoPath")
        $Script:DbgLogger.Debug("错误信息: $_")
        $DebugInfo = $null
    }
}
else {
    $Script:DbgLogger.Warn("未找到程序调试信息，将无法获得行号映射: $ProgramDebugInfoPath")
}
#endregion

#region 主逻辑
try {
    $Script:DbgLogger.Info("开始执行程序")
        
    # 显示传入的参数
    if ($ArgumentList.Count -gt 0) {
        $Script:DbgLogger.Info("参数列表: $($ArgumentList -join ' ')")
    }
        
    # 执行脚本
    & $ProgramPath @ArgumentList
}
catch {
    $ErrorMessage = $_.Exception.Message
    # 先打印错误信息，然后打印映射过的堆栈信息
    $Script:DbgLogger.Error("执行时发生错误: $ErrorMessage")
        
    $StackTraceString = $_.ScriptStackTrace
    if (-not [string]::IsNullOrEmpty($StackTraceString)) {
        $Script:DbgLogger.Info("调用堆栈跟踪:")
        $StackTraceLines = $StackTraceString -split "\r?\n"
            
        foreach ($Line in $StackTraceLines) {
            # 打印原始堆栈行
            $Script:DbgLogger.Info($Line)
                
            # 尝试映射行号
            if ($Line -match 'at\s+<ScriptBlock>,\s+(.*?):\s+line\s+(\d+)') {
                $FilePath = $Matches[1]
                $LineNum = [int]$Matches[2]
                    
                # 检查是否是程序文件
                if ($FilePath -eq $ProgramPath -and $DebugInfo) {
                    # 查找映射关系
                    $Mapping = $DebugInfo | Where-Object { $_.OutputLine -eq $LineNum }
                    if ($Mapping) {
                        $SourceFile = $Mapping.SourceFile
                        $SourceLineNum = $Mapping.SourceLineNum
                        $Script:DbgLogger.Info("    -> at $($SourceFile): line $SourceLineNum")
                    }
                }
            }
        }
    }
}
finally {
    $Script:DbgLogger.Info("执行完毕")
}
#endregion