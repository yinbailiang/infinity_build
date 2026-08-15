<#
.NOTES
    solver 模块测试脚本
    覆盖：依赖约束类、nuspec解析、依赖展开、闭包求解、可视化输出
#>

# 模块导入
using module ..\logger.psm1
using module .\logger.psm1
using module .\versioning.psm1
using module .\source.psm1
using module .\frameworks.psm1
using module .\solver.psm1

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

#region 1. DependencyConstraint 类测试

Write-Host "`n=== 1. DependencyConstraint 类 ===" -ForegroundColor Cyan

Test-Case "创建 DependencyConstraint" -Test {
    $Range = ConvertTo-VersionRange -RangeString '[1.0, 2.0)'
    $Constraint = [DependencyConstraint]::new('Test.Package', $Range)
    return ($Constraint.PackageId -eq 'Test.Package' -and
            $Constraint.VersionRange.IsMinInclusive -eq $true -and
            $Constraint.VersionRange.IsMaxInclusive -eq $false)
}

Test-Case "DependencyConstraint ToString" -Test {
    $Range = ConvertTo-VersionRange -RangeString '[1.0, 2.0)'
    $Constraint = [DependencyConstraint]::new('Test.Package', $Range)
    return $Constraint.ToString().StartsWith('Test.Package')
}

Test-Case "DependencyConstraint 带 TargetFramework" -Test {
    $Range = ConvertTo-VersionRange -RangeString '1.0'
    $Constraint = [DependencyConstraint]::new('Test.Package', $Range, 'net8.0')
    return ($Constraint.TargetFramework -eq 'net8.0')
}

#endregion

#region 2. DependencyNode 类测试

Write-Host "`n=== 2. DependencyNode 类 ===" -ForegroundColor Cyan

Test-Case "创建 DependencyNode" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Node = [DependencyNode]::new('Test.Package', $Version, $Range, 0)
    return ($Node.PackageId -eq 'Test.Package' -and
            $Node.ResolvedVersion.NormalizedVersion -eq '1.0.0' -and
            $Node.Depth -eq 0 -and
            $Node.Disposition -eq [DependencyDisposition]::Acceptable)
}

Test-Case "DependencyNode HasDependencies 空依赖" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Node = [DependencyNode]::new('Test.Package', $Version, $Range, 0)
    return $Node.HasDependencies() -eq $false
}

Test-Case "DependencyNode ToString 格式" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Node = [DependencyNode]::new('Test.Package', $Version, $Range, 2)
    $str = $Node.ToString()
    return $str -like '*Test.Package*1.0.0*'
}

Test-Case "DependencyNode IsAccepted / IsRejected" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Node = [DependencyNode]::new('Test.Package', $Version, $Range, 0)
    $Node.Disposition = [DependencyDisposition]::Accepted
    return ($Node.IsAccepted() -eq $true -and $Node.IsRejected() -eq $false)
}

#endregion

#region 3. DependencyResolutionResult 类测试

Write-Host "`n=== 3. DependencyResolutionResult 类 ===" -ForegroundColor Cyan

Test-Case "创建 DependencyResolutionResult 默认值" -Test {
    $Result = [DependencyResolutionResult]::new()
    return ($Result.Success -eq $false -and
            $Result.TotalPackages -eq 0 -and
            $Result.MaxDepth -eq 0 -and
            $Result.RootNodes.Count -eq 0 -and
            $Result.Errors.Count -eq 0)
}

#endregion

#region 4. 依赖信息获取（需网络）

Write-Host "`n=== 4. 依赖信息获取（网络） ===" -ForegroundColor Cyan

try {
    $Source = New-NugetSource -Url 'https://api.nuget.org/v3/index.json'
    
    Test-Case "获取 Newtonsoft.Json nuspec 并解析依赖" -Test {
        $NuspecXml = Get-NugetPackagManifest -Source $Source -Id 'Newtonsoft.Json' -Version '13.0.3'
        $Deps = Get-NuspecDependencies -NuspecXml $NuspecXml
        return $null -ne $Deps
    }

    Test-Case "获取 Microsoft.Extensions.Hosting nuspec 并按框架解析依赖" -Test {
        $NuspecXml = Get-NugetPackagManifest -Source $Source -Id 'Microsoft.Extensions.Hosting' -Version '8.0.0'
        $Deps = Get-NuspecDependencies -NuspecXml $NuspecXml -TargetFramework 'net8.0'
        return $Deps.Count -gt 0
    }

    Test-Case "Get-NugetPackageDependencies 函数（含版本标准化）" -Test {
        $Deps = Get-NugetPackageDependencies -Source $Source -Id 'Newtonsoft.Json' -Version '13.0.3'
        return $null -ne $Deps
    }

    Test-Case "Get-CachedPackageVersions 获取版本列表" -Test {
        $Context = [DependencyResolutionContext]::new($Source)
        $Versions = Get-CachedPackageVersions -Context $Context -Id 'Newtonsoft.Json'
        return $Versions.Count -gt 0
    }
}
catch {
    Write-Host "  SKIP  网络测试跳过（无法连接 nuget.org）" -ForegroundColor Yellow
}

#endregion

#region 5. 依赖展开

Write-Host "`n=== 5. 依赖展开（网络） ===" -ForegroundColor Cyan

try {
    $Source = New-NugetSource -Url 'https://api.nuget.org/v3/index.json'
    
    Test-Case "Expand-NugetDependency Newtonsoft.Json 13.0.3（无传递依赖）" -Test {
        $Tree = Expand-NugetDependency -Source $Source -Id 'Newtonsoft.Json' -Version '13.0.3'
        return ($Tree.PackageId -eq 'Newtonsoft.Json' -and
                $Tree.ResolvedVersion.NormalizedVersion -eq '13.0.3')
    }

    Test-Case "Expand-NugetDependency Microsoft.Extensions.Hosting 8.0.0（有传递依赖）" -Test {
        $Tree = Expand-NugetDependency -Source $Source -Id 'Microsoft.Extensions.Hosting' -Version '8.0.0'
        return ($Tree.PackageId -eq 'Microsoft.Extensions.Hosting' -and
                $Tree.Children.Count -gt 0)
    }

    Test-Case "Expand-NugetDependency 深度限制" -Test {
        $Tree = Expand-NugetDependency -Source $Source -Id 'Newtonsoft.Json' -Version '13.0.3' -MaxDepth 3
        return $Tree.Depth -eq 0
    }
}
catch {
    Write-Host "  SKIP  网络测试跳过（无法连接 nuget.org）" -ForegroundColor Yellow
}

#endregion

#region 6. 闭包求解

Write-Host "`n=== 6. 闭包求解（网络） ===" -ForegroundColor Cyan

try {
    $Source = New-NugetSource -Url 'https://api.nuget.org/v3/index.json'
    
    Test-Case "Resolve-NugetDependencyClosure 单包求解" -Test {
        $Result = Resolve-NugetDependencyClosure -Source $Source -Packages @{
            'Newtonsoft.Json' = '13.0.3'
        }
        return ($Result.Success -and
                $Result.ResolvedPackages.ContainsKey('Newtonsoft.Json') -and
                $Result.TotalPackages -ge 1)
    }

    Test-Case "Resolve-NugetDependencyClosure 版本范围求解" -Test {
        $Result = Resolve-NugetDependencyClosure -Source $Source -Packages @{
            'Newtonsoft.Json' = '[12.0, 14.0)'
        }
        $Ver = $Result.ResolvedPackages['Newtonsoft.Json']
        return ($Result.Success -and $Ver.Major -ge 12 -and $Ver.Major -lt 14)
    }

    Test-Case "Resolve-NugetDependencyClosure 多包求解" -Test {
        $Result = Resolve-NugetDependencyClosure -Source $Source -Packages @{
            'Microsoft.Extensions.DependencyInjection' = '8.0.0'
            'Microsoft.Extensions.Logging'             = '8.0.0'
        }
        return ($Result.Success -and $Result.TotalPackages -gt 1)
    }

    Test-Case "Get-NugetDependencyClosure 简化接口" -Test {
        $Result = Get-NugetDependencyClosure -Source $Source -Packages @{
            'Newtonsoft.Json' = '13.0.3'
        }
        return ($Result.Success -and $Result.ResolvedPackages.ContainsKey('Newtonsoft.Json'))
    }

    Test-Case "冲突检测 - 无冲突情况" -Test {
        $Result = Resolve-NugetDependencyClosure -Source $Source -Packages @{
            'Newtonsoft.Json' = '13.0.3'
        }
        $Conflicts = Test-NugetDependencyConflict -Result $Result
        return ($Conflicts.Count -eq 0)
    }
}
catch {
    Write-Host "  SKIP  网络测试跳过（无法连接 nuget.org）" -ForegroundColor Yellow
}

#endregion

#region 7. 可视化输出

Write-Host "`n=== 7. 可视化输出 ===" -ForegroundColor Cyan

Test-Case "Format-NugetDependencyTree 输出格式" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Root = [DependencyNode]::new('Root.Package', $Version, $Range, 0)
    $Child = [DependencyNode]::new('Child.Package', $Version, $Range, 1)
    $Root.Children = @($Child)
    
    $Lines = Format-NugetDependencyTree -Node $Root
    return ($Lines.Count -ge 2 -and
            $Lines[0] -like '*Root.Package*' -and
            $Lines[1] -like '*Child.Package*')
}

Test-Case "Format-NugetDependencyTree 深层嵌套" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Root = [DependencyNode]::new('Root', $Version, $Range, 0)
    $Child1 = [DependencyNode]::new('Child1', $Version, $Range, 1)
    $Child2 = [DependencyNode]::new('Child2', $Version, $Range, 2)
    $Child1.Children = @($Child2)
    $Root.Children = @($Child1)
    
    $Lines = Format-NugetDependencyTree -Node $Root
    return ($Lines.Count -ge 3)
}

Test-Case "Format-NugetDependencyList 输出" -Test {
    $Result = [DependencyResolutionResult]::new()
    $Ver1 = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Ver2 = ConvertTo-NuGetVersion -VersionString '2.0.0'
    $Result.ResolvedPackages = @{
        'Package.A' = $Ver1
        'Package.B' = $Ver2
    }
    $Result.Success = $true
    $Result.TotalPackages = 2
    
    $Lines = Format-NugetDependencyList -Result $Result
    return ($Lines.Count -eq 2 -and
            $Lines[0] -like 'Package.A*1.0.0*' -and
            $Lines[1] -like 'Package.B*2.0.0*')
}

Test-Case "Format-NugetDependencyMermaid 输出" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Root = [DependencyNode]::new('Root.Package', $Version, $Range, 0)
    
    $Mermaid = Format-NugetDependencyMermaid -Node $Root
    return ($Mermaid -like '*mermaid*' -and $Mermaid -like '*flowchart*' -and $Mermaid -like '*Root.Package*')
}

#endregion

#region 8. 边界情况

Write-Host "`n=== 8. 边界情况 ===" -ForegroundColor Cyan

Test-Case "Parse-DependencyElement 处理缺少 id" -Test {
    $xml = [xml]'<dependency version="1.0" />'
    $result = Parse-DependencyElement -DependencyElement $xml.dependency
    return $null -eq $result
}

Test-Case "Parse-DependencyElement 处理 _._ 占位包" -Test {
    $xml = [xml]'<dependency id="_._" version="1.0" />'
    $result = Parse-DependencyElement -DependencyElement $xml.dependency
    return $null -eq $result
}

Test-Case "Get-NuspecDependencies 处理无 metadata 的 XML" -Test {
    $xml = [xml]'<package></package>'
    $Deps = Get-NuspecDependencies -NuspecXml $xml
    return $Deps.Count -eq 0
}

Test-Case "Get-NodeMaxDepth 叶子节点" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Node = [DependencyNode]::new('Test', $Version, $Range, 5)
    $depth = Get-NodeMaxDepth -Node $Node
    return $depth -eq 5
}

Test-Case "Get-NodeMaxDepth 嵌套节点" -Test {
    $Version = ConvertTo-NuGetVersion -VersionString '1.0.0'
    $Range = ConvertTo-VersionRange -RangeString '1.0.0'
    $Root = [DependencyNode]::new('Root', $Version, $Range, 0)
    $Child1 = [DependencyNode]::new('Child1', $Version, $Range, 1)
    $Child2 = [DependencyNode]::new('Child2', $Version, $Range, 3)
    $Child1.Children = @($Child2)
    $Root.Children = @($Child1)
    $depth = Get-NodeMaxDepth -Node $Root
    return $depth -eq 3
}

#endregion

#region 9. Register-Constraint 与 Find-SatisfyingVersion

Write-Host "`n=== 9. 约束引擎 ===" -ForegroundColor Cyan

try {
    $Source = New-NugetSource -Url 'https://api.nuget.org/v3/index.json'
    $Context = [DependencyResolutionContext]::new($Source)
    
    Test-Case "Register-Constraint 注册约束" -Test {
        $Range = ConvertTo-VersionRange -RangeString '[1.0, 2.0)'
        Register-Constraint -Context $Context -PackageId 'Test.Package' -Constraint $Range
        return $Context.Constraints.ContainsKey('test.package')
    }

    Test-Case "Register-Constraint 去重" -Test {
        $Range = ConvertTo-VersionRange -RangeString '[1.0, 2.0)'
        $before = $Context.Constraints['test.package'].Count
        Register-Constraint -Context $Context -PackageId 'Test.Package' -Constraint $Range
        $after = $Context.Constraints['test.package'].Count
        return $before -eq $after
    }

    Test-Case "Find-SatisfyingVersion 查找版本" -Test {
        $Range = ConvertTo-VersionRange -RangeString '[12.0, 14.0)'
        $Constraints = [System.Collections.Generic.List[VersionRange]]::new()
        $Constraints.Add($Range)
        
        $Best = Find-SatisfyingVersion -Context $Context -PackageId 'Newtonsoft.Json' -Constraints $Constraints
        return ($null -ne $Best -and $Best.Major -ge 12 -and $Best.Major -lt 14)
    }
}
catch {
    Write-Host "  SKIP  网络测试跳过（无法连接 nuget.org）" -ForegroundColor Yellow
}

#endregion

# 输出结果
Test-Results
