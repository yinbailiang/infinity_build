# ============================================================
# Infinity System - 环境初始化脚本
# 提供临时命令行别名，方便快速调用各工具脚本
# 用法: . .\init_env.ps1
# ============================================================

#region 路径初始化
$Script:InfinityRoot = $PSScriptRoot
#endregion

#region 临时命令行别名

# infinity_build.ps1 - 项目构建
function inf_build {
    & (Join-Path $Script:InfinityRoot 'infinity_build.ps1') @args
}

# infinity_dbg.ps1 - 调试工具
function inf_dbg {
    & (Join-Path $Script:InfinityRoot 'infinity_dbg.ps1') @args
}

#endregion

#region 输出提示
Write-Host "Infinity System 环境已初始化" -ForegroundColor Green
Write-Host "可用别名:" -ForegroundColor Cyan
Write-Host "  inf_build  - 项目构建" -ForegroundColor White
Write-Host "  inf_dbg    - 调试工具" -ForegroundColor White
#endregion
