# 根据参数执行脚本并利用调试信息映射错误信息
param (
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter()]
    [System.Object[]]$ArgumentList = @(),
    [Parameter()]
    [switch]$ReBuild
)

if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    Write-Host "[InfinityDbg] 未找到配置文件: $ConfigPath" -ForegroundColor Red
    throw "未找到配置文件: $ConfigPath"
}
$Config = Get-Content -Path $ConfigPath | ConvertFrom-Json

if ($ReBuild) {
    Write-Host "[InfinityDbg] 重新构建"
    & (Join-Path $PSScriptRoot 'infinity_build.ps1') -ConfigPath $ConfigPath
    Write-Host "[InfinityDbg] 重新构建完成"
}

$ProgramName = if ($Config.Name) {
    $Config.Name
}
else {
    "infinity_program"
}

$ProgramPath = Join-Path $PWD "$($ProgramName).ps1"
$ProgramDebugInfoPath = Join-Path $PWD "$($ProgramName).debug.json"

if(-not (Test-Path -Path $ProgramPath -PathType Leaf)){
    Write-Host "[InfinityDbg] 未找到程序: $ProgramPath" -ForegroundColor Red
    throw "[InfinityDbg] 未找到程序: $ProgramPath"
}

$DebugInfo = if(Test-Path -Path $ProgramDebugInfoPath -PathType Leaf){
    Get-Content -Path $ProgramDebugInfoPath | ConvertFrom-Json
}
else{
    Write-Host "[InfinityDbg] 未找到程序调试信息，将无法获得行号映射"
    $null
}

try {
    Write-Host "[InfinityDbg] 开始执行"
    & $ProgramPath $ArgumentList
}
catch {
    $ErrorMessage = $_.Exception.Message
    # 先打印错误信息，然后打印映射过的堆栈信息
    Write-Host "[InfinityDbg] Error: $ErrorMessage" -ForegroundColor Red
    $StackTraceString = $_.ScriptStackTrace
    $StackTraceLines = $StackTraceString -split "\r?\n"
    foreach ($Line in $StackTraceLines) {
        Write-Host $Line -ForegroundColor Cyan
        if ($Line -match 'at\s+(\S+),\s+(.*?):\s+line\s+(\d+)' ) {
            $FunctionName = $Matches[1]
            $FilePath = $Matches[2]
            $LineNum = [int]$Matches[3]
            if ($FilePath -eq $ProgramPath) {
                $Mapping = $DebugInfo | Where-Object { $_.OutputLine -eq $LineNum }
                if ($Mapping) {
                    $SourceFile = $Mapping.SourceFile
                    $SourceLineNum = $Mapping.SourceLineNum
                    Write-Host "   -> $SourceFile`: line $SourceLineNum" -ForegroundColor Yellow
                    continue
                }
            }
        }
    }
}
Write-Host "[InfinityDbg] 执行完毕"