##Module Core.Linker
##Import Core.Logger
##Import Core.Types

#region 程序段生成

<#
.SYNOPSIS
    将排序后的 InfinityModule 数组链接为最终的 InfinityProgramSegment。
.DESCRIPTION
    按顺序拼接各模块的 Code 行，并合并各模块的行号映射，
    生成输出行号 -> (源文件路径, 源行号) 的全局映射表。
#>
function New-InfinityProgramSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )
    
    $Script:BuildLogger.Info("生成程序段，包含 $($Modules.Count) 个模块")
    $ProgramSegment = [InfinityProgramSegment]@{
        Code         = [System.Collections.Generic.List[string]]::new()
        LineMappings = [System.Collections.Generic.Dictionary[int, System.Tuple[string, int]]]::new()
    }

    foreach ($Module in $Modules) {
        $Script:BuildLogger.Info("添加模块: $($Module.Name) ($($Module.Code.Count) 行)")
        $ModuleLineNum = 0
        foreach ($Line in $Module.Code) {
            $ModuleLineNum++
            $ProgramSegment.Code.Add($Line)
            if ($Module.LineMappings.ContainsKey($ModuleLineNum)) {
                $ProgramSegment.LineMappings[$ProgramSegment.Code.Count] = [System.Tuple[string, int]]::new($Module.SourceInfo.FullName, $Module.LineMappings[$ModuleLineNum])
            }
        }
    }

    $Script:BuildLogger.Info("程序段生成完成: $($ProgramSegment.Code.Count) 行代码, $($ProgramSegment.LineMappings.Count) 个行号映射")
    return $ProgramSegment
}

#endregion
