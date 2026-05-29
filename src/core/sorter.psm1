##Module Core.Sorter
##Import Core.Logger
##Import Core.Types

function Get-InfinityModuleOrdered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )

    $Script:BuildLogger.Info("对 $($Modules.Count) 个模块进行拓扑排序")
    
    # 创建模块名称到模块对象的映射
    $ModuleMap = [System.Collections.Generic.Dictionary[string, InfinityModule]]::new()
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    
    # 计算每个模块的入度（依赖数）
    $InDegree = [System.Collections.Generic.Dictionary[string, int]]::new()
    $AdjacencyList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]::new()
    
    foreach ($Module in $Modules) {
        $InDegree[$Module.Name] = 0
        $AdjacencyList[$Module.Name] = [System.Collections.Generic.List[string]]::new()
    }
    
    # 构建邻接表和计算入度
    foreach ($Module in $Modules) {
        foreach ($RequiredModuleName in $Module.Requires) {
            if (-not $ModuleMap.ContainsKey($RequiredModuleName)) {
                $Script:BuildLogger.Warn("模块 '$($Module.Name)' 依赖的模块 '$RequiredModuleName' 不在提供的模块列表中")
                continue
            }
            $AdjacencyList[$RequiredModuleName].Add($Module.Name)
            $InDegree[$Module.Name] += 1
        }
    }
    
    # 拓扑排序
    $SortedModules = [System.Collections.Generic.List[InfinityModule]]::new()
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    
    # 将所有入度为0的模块加入队列
    foreach ($ModuleName in $InDegree.Keys) {
        if ($InDegree[$ModuleName] -eq 0) {
            $Queue.Enqueue($ModuleName)
        }
    }
    
    # 处理队列
    while ($Queue.Count -gt 0) {
        $CurrentModuleName = $Queue.Dequeue()
        $SortedModules.Add($ModuleMap[$CurrentModuleName])
        
        # 减少所有依赖当前模块的模块的入度
        foreach ($DependentModuleName in $AdjacencyList[$CurrentModuleName]) {
            $InDegree[$DependentModuleName] -= 1
            if ($InDegree[$DependentModuleName] -eq 0) {
                $Queue.Enqueue($DependentModuleName)
            }
        }
    }
    
    # 检查是否有环
    if ($SortedModules.Count -ne $Modules.Count) {
        # 找出所有有剩余入度的模块（形成环的模块）
        $RemainingModules = @()
        foreach ($ModuleName in $InDegree.Keys) {
            if ($InDegree[$ModuleName] -gt 0) {
                $RemainingModules += $ModuleName
            }
        }
        $Script:BuildLogger.Error("检测到循环依赖！受影响的模块: $($RemainingModules -join ', ')")
        throw "检测到循环依赖！受影响的模块: $($RemainingModules -join ', ')"
    }

    $Script:BuildLogger.Info("拓扑排序完成，顺序: $($SortedModules.Name -join ' -> ')")
    return $SortedModules
}