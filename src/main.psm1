##Module Main
##Import Core
##Import Builder

function Invoke-Main {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = 'psproject.json',

        [Parameter(Mandatory = $false)]
        [hashtable]$ExtraConfig
    )

    $Script:BuildLogger.Info("PowerShell 版本: $PSVersion")

    $WorkFolder = (Get-Item -Path $ConfigPath).Directory
    $Script:BuildLogger.Info("工作目录: $WorkFolder")

    Push-Location $WorkFolder
    try{
        if (-not (Test-Path -Path $ConfigPath -PathType Leaf)){
            $Script:BuildLogger.Error("未找到配置文件: $ConfigPath")
            throw "未找到配置文件: $ConfigPath"
        }else{
            $Script:BuildLogger.Info("读取配置文件: $ConfigPath")
            $Script:BuildConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        }
            
        $Script:BuildSystem = if ($Script:BuildConfig.ContainsKey("System")) {
            $Script:BuildConfig["System"]
        } else { @{} }

        $Script:BuildName = if ($Script:BuildSystem.ContainsKey("Name")) {
            $Script:BuildSystem["Name"]
        } else {
            [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
        }


        # 确定缓存目录（优先使用 System.CacheDir）
        $Script:CacheFolder = if ($Script:BuildSystem.ContainsKey("CacheDir")) {
            $CacheDir = $Script:BuildSystem["CacheDir"]
            if (-not [System.IO.Path]::IsPathRooted($CacheDir)) {
                Join-Path (Get-Location) $CacheDir
            } else {
                $CacheDir
            }
        } else {
            Join-Path (Get-Location) ".infinity_build"
        }
        $Script:BuildLogger.Info("缓存目录: $CacheFolder")

        # 确保缓存目录存在
        if (-not (Test-Path -Path $CacheFolder -PathType Container)) {
            $Script:BuildLogger.Info("创建缓存目录: $CacheFolder")
            if (-not (New-Item -Path $CacheFolder -ItemType Directory -Force)) {
                $Script:BuildLogger.Error("无法创建缓存目录: $CacheFolder")
                throw "无法创建缓存目录: $CacheFolder"
            }
        }

        # 从顶层键解析构建步骤（排除 System 等元信息键）
        $BuildSteps = @{}
        $MetaKeys = @("System", "Output")
        foreach ($Key in $Script:BuildConfig.Keys) {
            if ($Key -notin $MetaKeys) {
                $BuildSteps[$Key] = $Script:BuildConfig[$Key]
            }
        }

        if ($BuildSteps.Count -eq 0) {
            $Script:BuildLogger.Error("未找到任何构建步骤")
            throw "未找到任何构建步骤"
        }

        $Script:BuildLogger.Info("构建步骤: $($BuildSteps.Keys -join ', ')")

        # 合并 ExtraConfig 到构建步骤（如果调用者提供了额外配置）
        if ($ExtraConfig) {
            $Script:BuildLogger.Info("应用额外配置: $($ExtraConfig.Keys -join ', ')")
            foreach ($Key in $ExtraConfig.Keys) {
                $BuildSteps[$Key] = $ExtraConfig[$Key]
            }
        }

        # 收集所有模块（顺序由后续拓扑排序决定，此处仅负责调用构建器）
        $AllModules = [System.Collections.Generic.List[InfinityModule]]::new()

        foreach ($StepName in $BuildSteps.Keys) {
            # 查表：跳过未注册的构建器
            if (-not $Script:ModuleBuilders.ContainsKey($StepName)) {
                $Script:BuildLogger.Warn("未注册的构建步骤: $StepName，已跳过")
                continue
            }

            $StepConfig = $BuildSteps[$StepName]

            $Script:BuildLogger.MeasureScope("构建步骤: $StepName", {
                # 统一查表调用
                $Result = & $Script:ModuleBuilders[$StepName] -Config $StepConfig
                if ($Result) {
                    foreach ($Module in $Result) {
                        $AllModules.Add($Module)
                    }
                }
            })
        }

        $Script:BuildLogger.Info("共生成 $($AllModules.Count) 个模块")

        if ($AllModules.Count -eq 0) {
            $Script:BuildLogger.Error("未生成任何模块，构建终止")
            throw "未生成任何模块，构建终止"
        }

        $Script:BuildLogger.Info("开始拓扑排序...")
        $SortedModules = Get-InfinityModuleOrdered -Modules $AllModules.ToArray()

        $ProgramSegment = New-InfinityProgramSegment -Modules $SortedModules

        $OutputPath = if ($Script:BuildConfig.ContainsKey("Output")) {
            $Script:BuildConfig["Output"]
        }
        elseif ($Script:BuildName) {
            "$($Script:BuildName).ps1"
        }
        else {
            "output.ps1"
        }

        if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
            $OutputPath = Join-Path (Get-Location) $OutputPath
        }

        $OutputDir = Split-Path $OutputPath -Parent
        if ($OutputDir -and -not (Test-Path $OutputDir)) {
            $null = New-Item -Path $OutputDir -ItemType Directory -Force
            $Script:BuildLogger.Info("创建输出目录: $OutputDir")
        }

        $Script:BuildLogger.Info("写入输出脚本: $OutputPath")
        $ProgramSegment.Code | Set-Content -Path $OutputPath -Encoding UTF8

        $DebugInfoPath = [System.IO.Path]::ChangeExtension($OutputPath, ".debug.json")
        $Script:BuildLogger.Info("写入调试信息: $DebugInfoPath")

        $DebugInfoList = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Key in ($ProgramSegment.LineMappings.Keys | Sort-Object)) {
            $Mapping = $ProgramSegment.LineMappings[$Key]
            $DebugInfoList.Add(@{
                OutputLine    = $Key
                SourceFile    = $Mapping.Item1
                SourceLineNum = $Mapping.Item2
            })
        }
        $DebugInfoList | ConvertTo-Json -Depth 2 -Compress | Set-Content -Path $DebugInfoPath -Encoding UTF8 -NoNewLine

        $OutputSize = (Get-Item $OutputPath).Length
        $Script:BuildLogger.Info("输出文件: $OutputPath ($([math]::Round($OutputSize / 1KB, 2)) KB)")
        $Script:BuildLogger.Info("调试文件: $DebugInfoPath")
    }
    finally{
        Pop-Location
    }
}
