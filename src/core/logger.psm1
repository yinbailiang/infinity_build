##Module Core.Logger
##Import Std.Logger

<#
.NOTES
    Infinity Build 构建日志模块。
    基于 Std.Logger 创建面向构建系统的 LogServer/LogClient 实例。
#>

$Script:BuildLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityBuild")
$Script:BuildLogger = [LogClient]::new($Script:BuildLoggerServer)