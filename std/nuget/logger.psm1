##Module Std.Nuget.Logger
##Import Std.Logger

#region 日志
$Script:NugetLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityNuget")
$Script:NugetLogger = [LogClient]::new($Script:NugetLoggerServer)
#endregion