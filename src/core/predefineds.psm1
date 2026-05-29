##Module Core.PreDefineds
##Import Core.Types

#region 预定义变量辅助函数

function Add-PreDefinedVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [InfinityModule]$Module,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        $Value
    )
    
    if ($Value -is [string]) {
        $Module.Code.Add("`$$Name = '$($Value.Replace("'","''"))'")
    }
    elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        $Module.Code.Add("`$$Name = $($Value.ToString())")
    }
    elseif ($Value -is [bool]) {
        $Module.Code.Add("`$$Name = `$" + ($Value ? "true" : "false"))
    }
    else {
        $Script:BuildLogger.Error("不支持的预定义变量类型: $Name -> $($Value.GetType())")
        throw "不支持的预定义变量类型: $Name -> $($Value.GetType())"
    }
}

#endregion
