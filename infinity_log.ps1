<#
.NOTES
    Name: infinity_log.ps1
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    Infinity Build 的日志库
.DESCRIPTION
    这个模块提供功能完善的日志系统，包含以下特性：
    1. 多级别日志输出：Debug, Info, Warning, Error
    2. 控制台彩色输出
    4. 时间戳和调用者信息
    5. 灵活的日志配置
    6. 结构化日志记录
#>
enum LogType {
    LogErr = 0      # 错误
    LogWarn = 1     # 警告
    LogInfo = 2     # 信息
    LogDebug = 3    # 调试
}

class LogServer {
    [LogType]$LogLevel
    [string]$AppName = $null
    [bool]$EnableColors = $true
    
    LogServer([LogType]$Level) {
        $this.LogLevel = $Level
    }
    LogServer([LogType]$Level, [string]$AppName) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
    }
    
    [string]FormatMessage([LogType]$Type, [string]$Text) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelName = switch ($Type) {
            ([LogType]::LogErr) { "ERROR" }
            ([LogType]::LogWarn) { "WARN-" }
            ([LogType]::LogInfo) { "INFO-" }
            ([LogType]::LogDebug) { "DEBUG" }
        }
        if ($this.AppName) {
            return "[$timestamp][$($this.AppName)][$levelName]$Text"
        }
        else {
            return "[$timestamp][$levelName]$Text"
        }
    }
    
    [void]Write([LogType]$Type, [string]$Text) {
        if ([int]$Type -gt [int]$this.LogLevel) {
            return
        }
        
        $message = $this.FormatMessage($Type, $Text)
        
        if ($this.EnableColors) {
            $this.WriteColored($Type, $message)
        }
        else {
            Write-Host $message
        }
    }
    
    hidden [void]WriteColored([LogType]$Type, [string]$Message) {
        $colorCode = switch ($Type) {
            ([LogType]::LogErr) { "91" }  # 亮红色
            ([LogType]::LogWarn) { "93" }  # 亮黄色
            ([LogType]::LogInfo) { "96" }  # 亮青色
            ([LogType]::LogDebug) { "94" }  # 亮蓝色
        }
        
        Write-Host "`u{001b}[${colorCode}m$Message`u{001b}[0m"
    }
}

class LogClient {
    [LogServer]$Server
    [System.Collections.Generic.Stack[string]]$Context = @()
    
    LogClient([LogServer]$Server) {
        $this.Server = $Server
    }
    LogClient([LogType]$Level) {
        $this.Server = [LogServer]::new($Level)
    }
    
    [object]Scope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")

        try {
            $Result = & $ScriptBlock
            $this.Info("完成: $ScopeName")
            return $Result
        }
        catch {
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }
    [object]MeasureScope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $Result = & $ScriptBlock
            $Stopwatch.Stop()
            $this.Info("完成: $ScopeName")
            $this.Info("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            return $Result
        }
        catch {
            $Stopwatch.Stop()
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            $this.Warn("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }

    [void]StartScope([string]$ScopeName) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
    }
    [void]EndScope() {
        $this.Info("完成: $($this.Context.Pop())")
    }
    
    # 写入日志的便捷方法
    [void]Error([string]$Message) {
        $this.WriteInternal([LogType]::LogErr, $Message)
    }
    [void]Warn([string]$Message) {
        $this.WriteInternal([LogType]::LogWarn, $Message)
    }
    [void]Info([string]$Message) {
        $this.WriteInternal([LogType]::LogInfo, $Message)
    }
    [void]Debug([string]$Message) {
        $this.WriteInternal([LogType]::LogDebug, $Message)
    }

    hidden [void]WriteInternal([LogType]$Type, [string]$Message) {
        $ContextPrefix = $this.BuildContextPrefix()
        $Lines = $Message -split "\r?\n"
        foreach ($Line in $Lines) {
            $this.Server.Write($Type, "$ContextPrefix $Line")
        }
    }

    hidden [string]BuildContextPrefix() {
        if ($this.Context.Count -ne 0) {
            $ContextArray = $this.Context.ToArray()
            [array]::Reverse($ContextArray)
            return "[$($ContextArray -join '.')]" 
        }
        return ""
    }
}