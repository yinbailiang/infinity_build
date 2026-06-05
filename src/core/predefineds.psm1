##Module Core.PreDefineds
##Import Core.Types

#region 预定义变量辅助函数

<#
.SYNOPSIS
    向 InfinityModule 中添加一个编译期预定义变量。
.DESCRIPTION
    根据值的类型（string / int / long / double / bool）生成对应的
    PowerShell 变量赋值语句，追加到模块的 Code 列表中。
    字符串值自动转义单引号，不支持的类型将抛出异常。
#>
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
