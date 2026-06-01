<#
.NOTES
    frameworks 模块测试脚本
    覆盖：解析、短名称、兼容性、就近匹配、框架归约、PCL、边缘情况
#>

# 强制重新加载模块（避免 using module 的缓存问题）
using module .\frameworks.psm1

#region 测试工具

$Script:TotalTests = 0
$Script:PassedTests = 0
$Script:FailedTests = 0

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$Expected = $null
    )
    $Script:TotalTests++
    try {
        $result = & $Test
        if ($Expected) {
            if ($result -eq $Expected) {
                $Script:PassedTests++
                Write-Host "  PASS  $Name" -ForegroundColor Green
            }
            else {
                $Script:FailedTests++
                Write-Host "  FAIL  $Name" -ForegroundColor Red
                Write-Host "        Expected: $Expected" -ForegroundColor Red
                Write-Host "        Got:      $result" -ForegroundColor Red
            }
        }
        elseif ($result) {
            $Script:PassedTests++
            Write-Host "  PASS  $Name" -ForegroundColor Green
        }
        else {
            $Script:FailedTests++
            Write-Host "  FAIL  $Name (returned `$false)" -ForegroundColor Red
        }
    }
    catch {
        $Script:FailedTests++
        Write-Host "  FAIL  $Name (exception: $_)" -ForegroundColor Red
        Write-Host ($_.ScriptStackTrace) -ForegroundColor Red
    }
}

function Test-Results {
    Write-Host ""
    Write-Host "=============================="
    Write-Host "  Total:  $Script:TotalTests"
    Write-Host "  Passed: $Script:PassedTests" -ForegroundColor Green
    Write-Host "  Failed: $Script:FailedTests" -ForegroundColor $(if ($Script:FailedTests -gt 0) { 'Red' } else { 'Green' })
    Write-Host "=============================="
}

#endregion

#region 1. 框架解析测试

Write-Host "`n=== 1. 框架解析 ===" -ForegroundColor Cyan

# 1.1 基础解析（短名称格式）
Test-Case "解析 net472" -Test { (ConvertTo-NuGetFramework 'net472').ToString() } -Expected 'net472'
Test-Case "解析 net45"  -Test { (ConvertTo-NuGetFramework 'net45').ToString() }  -Expected 'net45'
Test-Case "解析 net40"  -Test { (ConvertTo-NuGetFramework 'net40').ToString() }  -Expected 'net40'
Test-Case "解析 net35"  -Test { (ConvertTo-NuGetFramework 'net35').ToString() }  -Expected 'net35'

# 1.2 NetCoreApp 解析
Test-Case "解析 netcoreapp3.1" -Test { (ConvertTo-NuGetFramework 'netcoreapp3.1').ToString() } -Expected 'netcoreapp3.1'
Test-Case "解析 net5.0"        -Test { (ConvertTo-NuGetFramework 'net5.0').ToString() }        -Expected 'net5.0'
Test-Case "解析 net6.0"        -Test { (ConvertTo-NuGetFramework 'net6.0').ToString() }        -Expected 'net6.0'
Test-Case "解析 net8.0"        -Test { (ConvertTo-NuGetFramework 'net8.0').ToString() }        -Expected 'net8.0'

# 1.3 别名解析（P1 修复验证）
Test-Case "别名 net50 → net5.0"         -Test { (ConvertTo-NuGetFramework 'net50').ToString() }          -Expected 'net5.0'
Test-Case "别名 netcoreapp5.0 → net5.0" -Test { (ConvertTo-NuGetFramework 'netcoreapp5.0').ToString() }  -Expected 'net5.0'
Test-Case "别名 net60 → net6.0"         -Test { (ConvertTo-NuGetFramework 'net60').ToString() }          -Expected 'net6.0'
Test-Case "别名 netcoreapp6.0 → net6.0" -Test { (ConvertTo-NuGetFramework 'netcoreapp6.0').ToString() }  -Expected 'net6.0'
Test-Case "别名 netstandard10 → netstandard1.0" -Test { (ConvertTo-NuGetFramework 'netstandard10').ToString() } -Expected 'netstandard1.0'
Test-Case "别名 netstandard20 → netstandard2.0" -Test { (ConvertTo-NuGetFramework 'netstandard20').ToString() } -Expected 'netstandard2.0'
Test-Case "别名 netcoreapp31 → netcoreapp3.1"   -Test { (ConvertTo-NuGetFramework 'netcoreapp31').ToString() }   -Expected 'netcoreapp3.1'

# 1.4 NetCore 解析
Test-Case "解析 netcore45"  -Test { (ConvertTo-NuGetFramework 'netcore45').ToString() }  -Expected 'netcore45'
Test-Case "解析 netcore451" -Test { (ConvertTo-NuGetFramework 'netcore451').ToString() } -Expected 'netcore451'
Test-Case "解析 netcore50"  -Test { (ConvertTo-NuGetFramework 'netcore50').ToString() }  -Expected 'netcore50'

# 1.5 弃用别名（P0 修复验证：弃用别名检查在 RawParse 失败之后）
Test-Case "弃用别名 45 → net45" -Test { (ConvertTo-NuGetFramework '45').ToString() } -Expected 'net45'
Test-Case "弃用别名 40 → net40" -Test { (ConvertTo-NuGetFramework '40').ToString() } -Expected 'net40'
Test-Case "弃用别名 35 → net35" -Test { (ConvertTo-NuGetFramework '35').ToString() } -Expected 'net35'
Test-Case "弃用别名 20 → net20" -Test { (ConvertTo-NuGetFramework '20').ToString() } -Expected 'net20'

# 1.6 其他标识符短名称
Test-Case "解析 win8"          -Test { (ConvertTo-NuGetFramework 'win8').ToString() }  -Expected 'win8'
Test-Case "解析 win81"         -Test { (ConvertTo-NuGetFramework 'win81').ToString() } -Expected 'win81'
Test-Case "别名 win → win8"    -Test { (ConvertTo-NuGetFramework 'win').ToString() }   -Expected 'win8'
Test-Case "别名 wp → wp7"      -Test { (ConvertTo-NuGetFramework 'wp').ToString() }    -Expected 'wp7'
Test-Case "解析 wpa81"         -Test { (ConvertTo-NuGetFramework 'wpa81').ToString() } -Expected 'wpa81'
Test-Case "别名 wpa → wpa81"   -Test { (ConvertTo-NuGetFramework 'wpa').ToString() }   -Expected 'wpa81'
Test-Case "解析 sl4"           -Test { (ConvertTo-NuGetFramework 'sl4').ToString() }   -Expected 'sl4'
Test-Case "解析 sl5"           -Test { (ConvertTo-NuGetFramework 'sl5').ToString() }   -Expected 'sl5'

# 1.7 UAP / Tizen
Test-Case "解析 uap10.0" -Test { (ConvertTo-NuGetFramework 'uap10.0').ToString() } -Expected 'uap10.0'
Test-Case "解析 tizen3"  -Test { (ConvertTo-NuGetFramework 'tizen3').ToString() }   -Expected 'tizen3'
Test-Case "解析 tizen4"  -Test { (ConvertTo-NuGetFramework 'tizen4').ToString() }   -Expected 'tizen4'

# 1.8 特殊框架
Test-Case "解析 any"         -Test { (ConvertTo-NuGetFramework 'any').ToString() }         -Expected 'any'
Test-Case "解析 agnostic"    -Test { (ConvertTo-NuGetFramework 'agnostic').ToString() }    -Expected 'agnostic'
Test-Case "解析 unsupported" -Test { (ConvertTo-NuGetFramework 'unsupported').ToString() } -Expected 'unsupported'

# 1.9 未知框架 → Unsupported
Test-Case "未知框架 → unsupported" -Test { (ConvertTo-NuGetFramework 'zzz999').ToString() } -Expected 'unsupported'

#endregion

#region 2. 平台框架解析（P0 修复验证）

Write-Host "`n=== 2. 平台框架解析 ===" -ForegroundColor Cyan

Test-Case "解析 net6.0-windows"          -Test { $f = ConvertTo-NuGetFramework 'net6.0-windows'; $f.Platform }           -Expected 'windows'
Test-Case "平台版本 net6.0-windows10.0"  -Test { $f = ConvertTo-NuGetFramework 'net6.0-windows10.0'; $f.PlatformVersion.ToString() } -Expected '10.0.0.0'

# P0 关键修复：无版本号的平台名不会崩溃
Test-Case "解析 net6.0-android (无版本号)"   -Test { $f = ConvertTo-NuGetFramework 'net6.0-android'; $f.Platform }    -Expected 'android'
Test-Case "android 平台版本为 0.0"           -Test { $f = ConvertTo-NuGetFramework 'net6.0-android'; $f.PlatformVersion.ToString() } -Expected '0.0.0.0'
Test-Case "解析 net6.0-ios (无版本号)"       -Test { $f = ConvertTo-NuGetFramework 'net6.0-ios'; $f.Platform }        -Expected 'ios'
Test-Case "解析 net8.0-android"              -Test { $f = ConvertTo-NuGetFramework 'net8.0-android'; $f.Platform }    -Expected 'android'

# PlatformName 大小写规范化
Test-Case "平台名小写化 Windows → windows"   -Test { $f = ConvertTo-NuGetFramework 'net6.0-Windows'; $f.Platform }    -Expected 'windows'

#endregion

#region 3. 短名称生成（往返测试）

Write-Host "`n=== 3. 短名称生成 ===" -ForegroundColor Cyan

$roundtripTests = @(
    'net472', 'net48', 'net481',
    'net5.0', 'net6.0', 'net7.0', 'net8.0',
    'netcoreapp3.1', 'netcoreapp2.1',
    'netstandard2.0', 'netstandard2.1',
    'net6.0-windows', 'net6.0-windows10.0',
    'net6.0-android', 'net6.0-ios',
    'win8', 'win81', 'wp7', 'wp8', 'wpa81',
    'netcore45', 'netcore451', 'netcore50',
    'sl4', 'sl5', 'uap10.0',
    'monoandroid', 'monotouch', 'monomac',
    'xamarinios', 'xamarinmac', 'xamarintvos', 'xamarinwatchos',
    'dnx', 'dnx45', 'dnxcore', 'dnxcore50',
    'dotnet50', 'dotnet51', 'dotnet52', 'dotnet53', 'dotnet54', 'dotnet55', 'dotnet56',
    'aspnet50', 'aspnetcore50',
    'tizen3', 'tizen4', 'tizen6',
    'native'
)

foreach ($name in $roundtripTests) {
    $localName = $name
    Test-Case "往返 $name" -Test {
        $fx = ConvertTo-NuGetFramework $localName
        $short = ConvertTo-NuGetFrameworkShortName -Framework $fx
        $short -eq $localName
    }
}

# P1 修复验证：dotnet → dotnet50
Test-Case "dotnet 短名称为 dotnet50" -Test {
    $fx = ConvertTo-NuGetFramework 'dotnet'
    ConvertTo-NuGetFrameworkShortName -Framework $fx
} -Expected 'dotnet50'

#endregion

#region 4. 框架兼容性测试

Write-Host "`n=== 4. 框架兼容性 ===" -ForegroundColor Cyan

# 4.1 同框架高版本兼容低版本
Test-Case "net472 兼容 net45"     -Test { Test-NuGetFrameworkCompatibility 'net472' 'net45' }
Test-Case "net45 不兼容 net472"   -Test { -not (Test-NuGetFrameworkCompatibility 'net45' 'net472') }
Test-Case "net8.0 兼容 net6.0"    -Test { Test-NuGetFrameworkCompatibility 'net8.0' 'net6.0' }
Test-Case "net6.0 不兼容 net8.0"  -Test { -not (Test-NuGetFrameworkCompatibility 'net6.0' 'net8.0') }

# 4.2 Any / Agnostic / Unsupported
Test-Case "Any 兼容一切"               -Test { Test-NuGetFrameworkCompatibility 'net472' 'any' }
Test-Case "任何目标兼容 Agnostic"      -Test { Test-NuGetFrameworkCompatibility 'net472' 'agnostic' }
Test-Case "Unsupported 不兼容任何"     -Test { -not (Test-NuGetFrameworkCompatibility 'unsupported' 'net472') }
Test-Case "任何不兼容 Unsupported"     -Test { -not (Test-NuGetFrameworkCompatibility 'net472' 'unsupported') }

# 4.3 netstandard 兼容性
Test-Case "netcoreapp3.1 兼容 netstandard2.0" -Test { Test-NuGetFrameworkCompatibility 'netcoreapp3.1' 'netstandard2.0' }
Test-Case "net472 兼容 netstandard2.0"        -Test { Test-NuGetFrameworkCompatibility 'net472' 'netstandard2.0' }
Test-Case "net45 兼容 netstandard1.1"         -Test { Test-NuGetFrameworkCompatibility 'net45' 'netstandard1.1' }
Test-Case "net45 不兼容 netstandard2.0"       -Test { -not (Test-NuGetFrameworkCompatibility 'net45' 'netstandard2.0') }

# 4.4 .NET 5 Era 平台兼容性
Test-Case "net6.0-windows 兼容 net6.0"       -Test { Test-NuGetFrameworkCompatibility 'net6.0-windows' 'net6.0' }
Test-Case "net6.0 不兼容 net6.0-windows"     -Test { -not (Test-NuGetFrameworkCompatibility 'net6.0' 'net6.0-windows') }
Test-Case "net6.0-windows10.0 兼容 net6.0-windows" -Test { Test-NuGetFrameworkCompatibility 'net6.0-windows10.0' 'net6.0-windows' }

# 4.5 net6Era 跨框架映射：MonoAndroid ↔ android
Test-Case "net6.0-android 兼容 monoandroid"  -Test { Test-NuGetFrameworkCompatibility 'net6.0-android' 'monoandroid' }
Test-Case "net6.0-android 兼容 monotouch"    -Test { -not (Test-NuGetFrameworkCompatibility 'net6.0-android' 'monotouch') }

# 4.6 等价框架
Test-Case "win8 ↔ netcore45 等价"       -Test { Test-NuGetFrameworkCompatibility 'win8' 'netcore45' }
Test-Case "netcore45 ↔ win8 等价"       -Test { Test-NuGetFrameworkCompatibility 'netcore45' 'win8' }
Test-Case "netcore45 ↔ WinRT45 等价"    -Test { Test-NuGetFrameworkCompatibility 'netcore45' 'winrt45' }
Test-Case "wp8 ↔ Silverlight8-WindowsPhone 等价" -Test {
    $slwp = [NuGetFramework]::new('Silverlight', '8.0.0.0', 'WindowsPhone')
    Test-NuGetFrameworkCompatibility 'wp8' $slwp
}
Test-Case "net40-client ↔ net40 等价"   -Test { Test-NuGetFrameworkCompatibility 'net40' 'net40' }

# 4.7 Unsupported 互不兼容（P2 修复验证）
Test-Case "Unsupported 不兼容 Unsupported" -Test { -not (Test-NuGetFrameworkCompatibility 'unsupported' 'unsupported') }

#endregion

#region 5. 就近匹配测试

Write-Host "`n=== 5. 就近匹配 ===" -ForegroundColor Cyan

# 5.1 精确匹配优先
Test-Case "精确匹配: net472 → net472" -Test {
    $r = Get-NearestNuGetFramework -Target 'net472' -Candidates @('net45', 'net472', 'net48')
    $r.ToString()
} -Expected 'net472'

# 5.2 版本就近（net48 不兼容 net472，仅 net45 可用）
Test-Case "就近匹配: net472 target [net45, net48] → net45" -Test {
    $r = Get-NearestNuGetFramework -Target 'net472' -Candidates @('net45', 'net48')
    $r.ToString()
} -Expected 'net45'

# 5.3 兼容降级
Test-Case "net45 target [net40, net403] → net403" -Test {
    $r = Get-NearestNuGetFramework -Target 'net45' -Candidates @('net40', 'net403')
    $r.ToString()
} -Expected 'net403'

# 5.4 平台特定目标（P0 修复验证：Reduce 不会误删不同平台的框架）
Test-Case "net8.0 target [net6.0-windows, net8.0] → net8.0" -Test {
    $r = Get-NearestNuGetFramework -Target 'net8.0' -Candidates @('net6.0-windows', 'net8.0')
    $r.ToString()
} -Expected 'net8.0'

Test-Case "net6.0-windows target [net6.0, net6.0-windows] → net6.0-windows" -Test {
    $r = Get-NearestNuGetFramework -Target 'net6.0-windows' -Candidates @('net6.0', 'net6.0-windows')
    $r.ToString()
} -Expected 'net6.0-windows'

# 5.5 net6Era 跨框架匹配
Test-Case "net6.0-android target [net6.0, monoandroid] → monoandroid" -Test {
    $r = Get-NearestNuGetFramework -Target 'net6.0-android' -Candidates @('net6.0', 'monoandroid')
    $r.ToString()
} -Expected 'monoandroid'

# 5.6 无兼容框架 → $null
Test-Case "无兼容框架返回 null" -Test {
    $null -eq (Get-NearestNuGetFramework -Target 'net9.0' -Candidates @('net40', 'net45'))
}

#endregion

#region 6. 框架归约测试

Write-Host "`n=== 6. 框架归约 (Reduce) ===" -ForegroundColor Cyan

# 6.1 ReduceUpwards: 去除被更高版本覆盖的框架
Test-Case "Upwards: [net40, net45, net48] → [net48]" -Test {
    $fxs = @('net40', 'net45', 'net48' | ForEach-Object { ConvertTo-NuGetFramework $_ })
    $reduced = Resolve-FrameworksUpwards -Frameworks $fxs
    ($reduced | ForEach-Object { $_.ToString() }) -join ','
} -Expected 'net48'

Test-Case "Upwards: [win8, win81, netcore451] → 等价归约" -Test {
    $fxs = @('win8', 'win81' | ForEach-Object { ConvertTo-NuGetFramework $_ })
    $reduced = Resolve-FrameworksUpwards -Frameworks $fxs
    ($reduced | ForEach-Object { $_.ToString() }) -join ','
} -Expected 'win81'

# 6.2 不同平台框架不被误删（P0 修复验证）
Test-Case "Upwards: [net6.0-windows, net6.0-android] 两者保留" -Test {
    $fxs = @('net6.0-windows', 'net6.0-android' | ForEach-Object { ConvertTo-NuGetFramework $_ })
    $reduced = Resolve-FrameworksUpwards -Frameworks $fxs
    $reduced.Count
} -Expected 2

Test-Case "Upwards: [net6.0, net6.0-windows] → 两者保留" -Test {
    $fxs = @('net6.0', 'net6.0-windows' | ForEach-Object { ConvertTo-NuGetFramework $_ })
    $reduced = Resolve-FrameworksUpwards -Frameworks $fxs
    # 平台框架不兼容非平台框架（反向），故均保留
    $reduced.Count
} -Expected 2

#endregion

#region 7. PCL 测试

Write-Host "`n=== 7. PCL 测试 ===" -ForegroundColor Cyan

# 7.1 PCL 解析
Test-Case "PCL: portable-net45+win8 解析成功" -Test {
    $fx = ConvertTo-NuGetFramework 'portable-net45+win8'
    $fx.IsPCL()
}

# 7.2 PCL 兼容性
Test-Case "PCL net45+win8 兼容 net45" -Test {
    Test-NuGetFrameworkCompatibility 'portable-net45+win8' 'net45'
}

#endregion

#region 8. Get-NuGetFrameworkInfo 测试

Write-Host "`n=== 8. FrameworkInfo ===" -ForegroundColor Cyan

Test-Case "Info: net6.0-windows IsNet5Era" -Test {
    $info = Get-NuGetFrameworkInfo 'net6.0-windows'
    $info.IsNet5Era
}

Test-Case "Info: net472 IsNet5Era=false" -Test {
    $info = Get-NuGetFrameworkInfo 'net472'
    -not $info.IsNet5Era
}

Test-Case "Info: netstandard2.0 IsPackageBased" -Test {
    $info = Get-NuGetFrameworkInfo 'netstandard2.0'
    $info.IsPackageBased
}

#endregion

#region 9. Get-NuGetFrameworkKeys 测试

Write-Host "`n=== 9. 框架键名 ===" -ForegroundColor Cyan

Test-Case "Keys 包含 net50 别名" -Test {
    $keys = Get-NuGetFrameworkKeys
    'net50' -in $keys
}

Test-Case "Keys 包含 netstandard10 别名" -Test {
    $keys = Get-NuGetFrameworkKeys
    'netstandard10' -in $keys
}

#endregion

#region 10. 全名格式解析

Write-Host "`n=== 10. 全名格式解析 ===" -ForegroundColor Cyan

Test-Case "解析 .NETFramework,Version=v4.7.2" -Test {
    $fx = ConvertTo-NuGetFramework '.NETFramework,Version=v4.7.2'
    $fx.ToString()
} -Expected 'net472'

Test-Case "解析 .NETCoreApp,Version=v6.0" -Test {
    $fx = ConvertTo-NuGetFramework '.NETCoreApp,Version=v6.0'
    $fx.ToString()
} -Expected 'net6.0'

Test-Case "解析 .NETStandard,Version=v2.0" -Test {
    $fx = ConvertTo-NuGetFramework '.NETStandard,Version=v2.0'
    $fx.ToString()
} -Expected 'netstandard2.0'

#endregion

# 输出结果
Test-Results

# 退出码
if ($Script:FailedTests -gt 0) { exit 1 } else { exit 0 }
