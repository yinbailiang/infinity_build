##Module Core.Finder
##Import Core.Logger

#region 文件处理

function Find-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Filters,
        
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location)
    )
    
    $Script:BuildLogger.Debug("查找文件: 路径=$Path, 过滤器=$($Filters -join ', ')")
    $FoundFiles = [System.Collections.Generic.List[string]]::new()
    
    foreach ($Filter in $Filters) {
        # 解析路径模式：将 "src/*.psm1" 拆分为目录 "src" 和文件过滤器 "*.psm1"
        $LastSep = [Math]::Max($Filter.LastIndexOf('/'), $Filter.LastIndexOf('\'))
        if ($LastSep -ge 0) {
            $SubDir = $Filter.Substring(0, $LastSep)
            $FileFilter = $Filter.Substring($LastSep + 1)
            $SearchPath = Join-Path $Path $SubDir
        }
        else {
            $FileFilter = $Filter
            $SearchPath = $Path
        }
        
        $Script:BuildLogger.Debug("  搜索路径: $SearchPath, 文件过滤器: $FileFilter")
        $Files = Get-ChildItem -Path $SearchPath -Filter $FileFilter -File -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            $FoundFiles.Add($File.FullName)
        }
    }
    
    $Script:BuildLogger.Debug("找到 $($FoundFiles.Count) 个文件")
    return $FoundFiles.ToArray()
}

#endregion
