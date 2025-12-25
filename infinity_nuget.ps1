<#
.NOTES
    Name: infinity_nuget
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    PowerShell 工具用于下载和管理 Nuget 包
.DESCRIPTION
    这个工具提供以下功能：
    1. 搜索 Nuget 包
    2. 下载和安装 Nuget 包
    3. 管理本地包缓存
    4. 更新已安装的包
    5. 管理包源
#>

$Script:ConfigPath = Join-Path -Path $PSScriptRoot 'configs' 'infinity_nuget_config.json'
$Script:Config = Get-Content -Path $Script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable;

class NugetSource{

    NugetSource([string]$Source){
        
    }
}