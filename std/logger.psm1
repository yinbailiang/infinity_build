##Module Std.Logger

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

class LogColorTable {
    [string]$ErrorColor
    [string]$WarnColor
    [string]$InfoColor
    [string]$DebugColor

    LogColorTable([string]$Error_C, [string]$Warn, [string]$Info, [string]$Debug) {
        $this.ErrorColor = $Error_C
        $this.WarnColor = $Warn
        $this.InfoColor = $Info
        $this.DebugColor = $Debug
    }

    [string]GetColor([LogType]$Type) {
        switch ($Type) {
            ([LogType]::LogErr)  { return $this.ErrorColor }
            ([LogType]::LogWarn) { return $this.WarnColor }
            ([LogType]::LogInfo) { return $this.InfoColor }
            ([LogType]::LogDebug) { return $this.DebugColor }
            default              {  }
        }
        return ""
    }

    # 预设：默认（亮色系，适合深色终端背景）
    static [LogColorTable] GetDefault() {
        return [LogColorTable]::new("91", "93", "96", "94")
    }
    # 预设：暗色终端优化（亮红/亮黄/亮白/暗灰）
    static [LogColorTable] GetDark() {
        return [LogColorTable]::new("91", "93", "97", "90")
    }
    # 预设：亮色终端优化（暗红/暗黄/黑/暗白，适合白色背景）
    static [LogColorTable] GetLight() {
        return [LogColorTable]::new("31", "33", "30", "37")
    }
    # 预设：高对比度（背景色块，无障碍友好）
    static [LogColorTable] GetHighContrast() {
        return [LogColorTable]::new("97;41", "30;43", "97;44", "37;40")
    }
}

class LogServer {
    [LogType]$LogLevel
    [string]$AppName = $null
    [bool]$EnableColors = $true
    [LogColorTable]$ColorTable = [LogColorTable]::GetDefault()
    
    LogServer([LogType]$Level) {
        $this.LogLevel = $Level
    }
    LogServer([LogType]$Level, [string]$AppName) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
    }
    LogServer([LogType]$Level, [string]$AppName, [LogColorTable]$ColorTable) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
        $this.ColorTable = $ColorTable
    }
    LogServer([LogType]$Level, [LogColorTable]$ColorTable) {
        $this.LogLevel = $Level
        $this.ColorTable = $ColorTable
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
        $colorCode = $this.ColorTable.GetColor($Type)
        if ([string]::IsNullOrEmpty($colorCode)) {
            Write-Host $Message
        }
        else {
            Write-Host "`u{001b}[${colorCode}m$Message`u{001b}[0m"
        }
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
    LogClient([LogType]$Level, [LogColorTable]$ColorTable) {
        $this.Server = [LogServer]::new($Level, $ColorTable)
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
    [void]Warning([string]$Message) {
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