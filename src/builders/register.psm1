##Module Builder.Register

<#
.NOTES
    构建器注册表模块。
    初始化 $Script:ModuleBuilders 哈希表，作为构建步骤的调度中心。
    各构建器模块通过 $Script:ModuleBuilders['Key'] = { ... } 注册自身。
#>


$Script:ModuleBuilders = @{}