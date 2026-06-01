##Module Std.Nuget.Frameworks

<#
.NOTES
    Name: infinity_nuget_frameworks
    Author: YinBailiang
    Version: 2.2.0
.SYNOPSIS
    NuGet 目标框架处理模块
.DESCRIPTION
    这个模块提供以下功能：
    1. 表示目标框架（NuGetFramework 类）
    2. 解析框架字符串（如 net472、net6.0-windows10.0）
    3. 框架兼容性判断（含等价闭包展开）
    4. 框架就近匹配（Framework Reduction）
    5. 框架短名称与标识符映射
    6. 预定义常用框架实例
    参考：NuGet.Client\src\NuGet.Core\NuGet.Frameworks
#>

#region NuGetFramework 类

class NuGetFramework {
    [string]$Framework
    [version]$Version
    [string]$ProfileName
    [string]$Platform
    [version]$PlatformVersion

    NuGetFramework() {
        $this.Framework = ''; $this.Version = [version]'0.0.0.0'; $this.ProfileName = ''; $this.Platform = ''; $this.PlatformVersion = [version]'0.0.0.0'
    }

    NuGetFramework([string]$Framework, [version]$Version, [string]$ProfileName, [string]$Platform, [version]$PlatformVersion) {
        $this.Framework = $Framework
        $this.Version = if ($Version) { [NuGetFramework]::NormalizeVersion($Version) } else { [version]'0.0.0.0' }
        $this.ProfileName = if ($ProfileName) { $ProfileName } else { '' }
        $isNet5Era = ($this.Framework -eq '.NETCoreApp' -and $this.Version.Major -ge 5)
        $this.Platform = if ($isNet5Era -and $Platform) { $Platform } else { '' }
        $this.PlatformVersion = if ($isNet5Era -and $PlatformVersion) { [NuGetFramework]::NormalizeVersion($PlatformVersion) } else { [version]'0.0.0.0' }
    }

    NuGetFramework([string]$Framework, [version]$Version) {
        $this.Framework = $Framework
        $this.Version = if ($Version) { [NuGetFramework]::NormalizeVersion($Version) } else { [version]'0.0.0.0' }
        $this.ProfileName = ''; $this.Platform = ''; $this.PlatformVersion = [version]'0.0.0.0'
    }

    NuGetFramework([string]$Framework, [version]$Version, [string]$ProfileName) {
        $this.Framework = $Framework
        $this.Version = if ($Version) { [NuGetFramework]::NormalizeVersion($Version) } else { [version]'0.0.0.0' }
        $this.ProfileName = if ($ProfileName) { $ProfileName } else { '' }
        $this.Platform = ''; $this.PlatformVersion = [version]'0.0.0.0'
    }

    NuGetFramework([string]$Framework, [version]$Version, [string]$Platform, [version]$PlatformVersion) {
        $this.Framework = $Framework
        $this.Version = if ($Version) { [NuGetFramework]::NormalizeVersion($Version) } else { [version]'0.0.0.0' }
        $this.ProfileName = ''
        $isNet5Era = ($this.Framework -eq '.NETCoreApp' -and $this.Version.Major -ge 5)
        $this.Platform = if ($isNet5Era -and $Platform) { $Platform } else { '' }
        $this.PlatformVersion = if ($isNet5Era -and $PlatformVersion) { [NuGetFramework]::NormalizeVersion($PlatformVersion) } else { [version]'0.0.0.0' }
    }

    static [version] NormalizeVersion([version]$Ver) {
        if ($Ver.Build -lt 0 -or $Ver.Revision -lt 0) {
            return [version]::new($Ver.Major, $Ver.Minor,
                [Math]::Max($Ver.Build, 0), [Math]::Max($Ver.Revision, 0))
        }
        return $Ver
    }

    [bool] IsNet5Era() { return ($this.Framework -eq '.NETCoreApp' -and $this.Version.Major -ge 5) }
    [bool] HasPlatform() { return (-not [string]::IsNullOrEmpty($this.Platform)) }
    [bool] HasProfile() { return (-not [string]::IsNullOrEmpty($this.ProfileName)) }
    [bool] IsPCL() { return ($this.Framework -eq '.NETPortable' -and $this.Version.Major -lt 5) }
    [bool] IsPackageBased() {
        # 官方: PackagesBased 静态集合不含 .NETCore; 仅 NetCore 5.0+ 才是包分发
        if (@('.NETCoreApp', '.NETStandard', '.NETStandardApp', '.NETPlatform', 'DNXCore', 'UAP', 'Tizen') -contains $this.Framework) { return $true }
        return ($this.Framework -eq '.NETCore' -and $this.Version.Major -ge 5)
    }
    [bool] IsSpecificFramework() { return ($this.Framework -ne 'Any' -and $this.Framework -ne 'Agnostic' -and $this.Framework -ne 'Unsupported') }
    [bool] IsAny() { return ($this.Framework -eq 'Any') }
    [bool] IsAgnostic() { return ($this.Framework -eq 'Agnostic') }
    [bool] IsUnsupported() { return ($this.Framework -eq 'Unsupported') }
    [bool] AllFrameworkVersions() { return ($this.Version.Major -le 0 -and $this.Version.Minor -le 0 -and $this.Version.Build -le 0 -and $this.Version.Revision -le 0) }
    [string] GetFrameworkIdentifier() { if ($this.IsNet5Era()) { return '.NETFramework' }; return $this.Framework }
    [string] GetShortFolderName() { return ConvertTo-NuGetFrameworkShortName -Framework $this }

    [string] GetDotNetFrameworkName() {
        # 与官方 GetDisplayVersion 对齐: 去除尾部零, 仅 Build/Revision > 0 时包含
        $ver = $this.Version
        $verStr = "$($ver.Major).$($ver.Minor)"
        if ($ver.Build -gt 0 -or $ver.Revision -gt 0) {
            $verStr += ".$($ver.Build)"
            if ($ver.Revision -gt 0) { $verStr += ".$($ver.Revision)" }
        }
        if (-not $this.IsSpecificFramework()) { return "$($this.Framework),Version=v0.0" }
        $name = "$($this.Framework),Version=v$verStr"
        if ($this.HasProfile()) { $name += ",Profile=$($this.ProfileName)" }
        return $name
    }

    [bool] Equals([object]$Other) {
        if ($null -eq $Other) { return $false }
        # 与官方 NuGetFrameworkFullComparer 对齐：Unsupported 框架永不相等
        if ($this.IsUnsupported() -or $Other.IsUnsupported()) { return $false }
        return ($this.Framework -eq $Other.Framework -and $this.Version -eq $Other.Version -and
            $this.ProfileName -eq $Other.ProfileName -and $this.Platform -eq $Other.Platform -and
            $this.PlatformVersion -eq $Other.PlatformVersion)
    }

    [string] ToString() { return $this.GetShortFolderName() }
}

class NuGetAnyFramework : NuGetFramework {
    NuGetAnyFramework() : base('Any', [version]'0.0.0.0', '', '', [version]'0.0.0.0') { }
}

class NuGetAgnosticFramework : NuGetFramework {
    NuGetAgnosticFramework() : base('Agnostic', [version]'0.0.0.0', '', '', [version]'0.0.0.0') { }
}

class NuGetUnsupportedFramework : NuGetFramework {
    NuGetUnsupportedFramework() : base('Unsupported', [version]'0.0.0.0', '', '', [version]'0.0.0.0') { }
    NuGetUnsupportedFramework([string]$Name) : base('Unsupported', [version]'0.0.0.0', '', '', [version]'0.0.0.0') {
        $this.Framework = "Unsupported,$Name"
    }
}

$Script:AnyFramework = [NuGetAnyFramework]::new()
$Script:AgnosticFramework = [NuGetAgnosticFramework]::new()
$Script:UnsupportedFramework = [NuGetUnsupportedFramework]::new()

#endregion

#region 框架常量与映射表

# 框架标识符别名（synonym → canonical identifier）
$Script:IdentifierSynonyms = @{
    'netframework'              = '.NETFramework'
    '.net'                      = '.NETFramework'
    'netcore'                   = '.NETCore'
    'netportable'               = '.NETPortable'
    'asp.net'                   = 'ASP.NET'
    'asp.netcore'               = 'ASP.NETCore'
    'xamarin.playstationthree'  = 'Xamarin.PlayStation3'
    'xamarinplaystationthree'   = 'Xamarin.PlayStation3'
    'xamarin.playstationfour'   = 'Xamarin.PlayStation4'
    'xamarinplaystationfour'    = 'Xamarin.PlayStation4'
    'xamarinplaystationvita'    = 'Xamarin.PlayStationVita'
}

# 框架标识符短名称（canonical identifier → short name）
$Script:IdentifierShortNames = @{
    '.NETCoreApp'              = 'netcoreapp'
    '.NETStandardApp'          = 'netstandardapp'
    '.NETStandard'             = 'netstandard'
    '.NETPlatform'             = 'dotnet'
    '.NETFramework'            = 'net'
    '.NETMicroFramework'       = 'netmf'
    '.NETnanoFramework'        = 'netnano'
    'Silverlight'              = 'sl'
    '.NETPortable'             = 'portable'
    'WindowsPhone'             = 'wp'
    'WindowsPhoneApp'          = 'wpa'
    'Windows'                  = 'win'
    'WinRT'                    = 'winrt'
    'ASP.NET'                  = 'aspnet'
    'ASP.NETCore'              = 'aspnetcore'
    'native'                   = 'native'
    'MonoAndroid'              = 'monoandroid'
    'MonoTouch'                = 'monotouch'
    'MonoMac'                  = 'monomac'
    'Xamarin.iOS'              = 'xamarinios'
    'Xamarin.Mac'              = 'xamarinmac'
    'Xamarin.PlayStation3'     = 'xamarinpsthree'
    'Xamarin.PlayStation4'     = 'xamarinpsfour'
    'Xamarin.PlayStationVita'  = 'xamarinpsvita'
    'Xamarin.WatchOS'          = 'xamarinwatchos'
    'Xamarin.TVOS'             = 'xamarintvos'
    'Xamarin.Xbox360'          = 'xamarinxboxthreesixty'
    'Xamarin.XboxOne'          = 'xamarinxboxone'
    'DNX'                      = 'dnx'
    'DNXCore'                  = 'dnxcore'
    '.NETCore'                 = 'netcore'
    'UAP'                      = 'uap'
    'Tizen'                    = 'tizen'
}

# 短名称到标识符（short name → canonical identifier）
$Script:ShortNameToIdentifier = @{}
foreach ($kv in $Script:IdentifierShortNames.GetEnumerator()) {
    $Script:ShortNameToIdentifier[$kv.Value] = $kv.Key
}

# 短名称按长度降序排列（防止前缀劫持）
$Script:SortedShortNames = $Script:IdentifierShortNames.GetEnumerator() |
    Sort-Object { $_.Value.Length } -Descending |
    ForEach-Object { $_ }

# Profile 短名映射
$Script:ProfileShortNames = @(
    @{ Framework = '.NETFramework'; ShortProfile = 'Client'; Profile = 'Client' }
    @{ Framework = '.NETFramework'; ShortProfile = 'CF';     Profile = 'CompactFramework' }
    @{ Framework = '.NETFramework'; ShortProfile = 'Full';   Profile = '' }
    @{ Framework = 'Silverlight';   ShortProfile = 'WP';     Profile = 'WindowsPhone' }
    @{ Framework = 'Silverlight';   ShortProfile = 'WP71';   Profile = 'WindowsPhone71' }
)

# 等价 Profile 映射
$Script:EquivalentProfiles = @(
    @{ Framework = '.NETFramework'; Profile = 'Client';         Equivalent = '' }
    @{ Framework = '.NETFramework'; Profile = 'Full';           Equivalent = '' }
    @{ Framework = 'Silverlight';   Profile = 'WindowsPhone71'; Equivalent = 'WindowsPhone' }
    @{ Framework = 'WindowsPhone';  Profile = 'WindowsPhone71'; Equivalent = 'WindowsPhone' }
)

# 子集框架映射（键=超集框架, 值=子集框架列表）
$Script:SubSetFrameworks = @{
    'DNX'             = @('.NETFramework')
    'DNXCore'         = @('.NETPlatform')
    '.NETStandardApp' = @('.NETStandard')
}

# 等价框架映射
$Script:EquivalentFrameworksFull = @(
    @{ A = [NuGetFramework]::new('UAP', '0.0.0.0'); B = [NuGetFramework]::new('UAP', '10.0.0.0') }
    @{ A = [NuGetFramework]::new('Windows', '0.0.0.0'); B = [NuGetFramework]::new('Windows', '8.0.0.0') }
    @{ A = [NuGetFramework]::new('Windows', '8.0.0.0'); B = [NuGetFramework]::new('.NETCore', '4.5.0.0') }
    @{ A = [NuGetFramework]::new('.NETCore', '4.5.0.0'); B = [NuGetFramework]::new('WinRT', '4.5.0.0') }
    @{ A = [NuGetFramework]::new('.NETCore', '0.0.0.0'); B = [NuGetFramework]::new('.NETCore', '4.5.0.0') }
    @{ A = [NuGetFramework]::new('WinRT', '0.0.0.0'); B = [NuGetFramework]::new('WinRT', '4.5.0.0') }
    @{ A = [NuGetFramework]::new('Windows', '8.1.0.0'); B = [NuGetFramework]::new('.NETCore', '4.5.1.0') }
    @{ A = [NuGetFramework]::new('WindowsPhone', '0.0.0.0'); B = [NuGetFramework]::new('WindowsPhone', '7.0.0.0') }
    @{ A = [NuGetFramework]::new('WindowsPhone', '7.0.0.0'); B = [NuGetFramework]::new('Silverlight', '3.0.0.0', 'WindowsPhone') }
    @{ A = [NuGetFramework]::new('WindowsPhone', '7.1.0.0'); B = [NuGetFramework]::new('Silverlight', '4.0.0.0', 'WindowsPhone71') }
    @{ A = [NuGetFramework]::new('WindowsPhone', '8.0.0.0'); B = [NuGetFramework]::new('Silverlight', '8.0.0.0', 'WindowsPhone') }
    @{ A = [NuGetFramework]::new('WindowsPhone', '8.1.0.0'); B = [NuGetFramework]::new('Silverlight', '8.1.0.0', 'WindowsPhone') }
    @{ A = [NuGetFramework]::new('WindowsPhoneApp', '0.0.0.0'); B = [NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0') }
    @{ A = [NuGetFramework]::new('Tizen', '0.0.0.0'); B = [NuGetFramework]::new('Tizen', '3.0.0.0') }
    @{ A = [NuGetFramework]::new('DNX', '0.0.0.0'); B = [NuGetFramework]::new('DNX', '4.5.0.0') }
    @{ A = [NuGetFramework]::new('DNXCore', '0.0.0.0'); B = [NuGetFramework]::new('DNXCore', '5.0.0.0') }
    @{ A = [NuGetFramework]::new('.NETPlatform', '0.0.0.0'); B = [NuGetFramework]::new('.NETPlatform', '5.0.0.0') }
    @{ A = [NuGetFramework]::new('ASP.NET', '0.0.0.0'); B = [NuGetFramework]::new('ASP.NET', '5.0.0.0') }
    @{ A = [NuGetFramework]::new('ASP.NETCore', '0.0.0.0'); B = [NuGetFramework]::new('ASP.NETCore', '5.0.0.0') }
    @{ A = [NuGetFramework]::new('DNX', '4.5.0.0'); B = [NuGetFramework]::new('ASP.NET', '5.0.0.0') }
    @{ A = [NuGetFramework]::new('DNXCore', '5.0.0.0'); B = [NuGetFramework]::new('ASP.NETCore', '5.0.0.0') }
)

# 兼容性映射（通过 FrameworkExpander 展开）
$Script:OneWayCompatibilityMappings = [System.Collections.Generic.List[hashtable]]::new()

function Add-OneWayMapping {
    param([NuGetFramework]$TargetMin, [NuGetFramework]$TargetMax, [NuGetFramework]$SupportedMin, [NuGetFramework]$SupportedMax)
    $Script:OneWayCompatibilityMappings.Add(@{
            TargetMin    = $TargetMin
            TargetMax    = $TargetMax
            SupportedMin = $SupportedMin
            SupportedMax = $SupportedMax
        })
}

function New-GenerationMapping {
    param([NuGetFramework]$Framework, [NuGetFramework]$NetPlatform)
    Add-OneWayMapping -TargetMin $Framework `
        -TargetMax ([NuGetFramework]::new($Framework.Framework, '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('.NETPlatform', '0.0.0.0')) `
        -SupportedMax $NetPlatform
}

function New-StandardMapping {
    param([NuGetFramework]$Framework, [NuGetFramework]$NetStandard)
    Add-OneWayMapping -TargetMin $Framework `
        -TargetMax ([NuGetFramework]::new($Framework.Framework, '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('.NETStandard', '1.0.0.0')) `
        -SupportedMax $NetStandard
}

function New-GenerationAndStandardMapping {
    param([NuGetFramework]$Framework, [NuGetFramework]$NetPlatform, [NuGetFramework]$NetStandard)
    New-GenerationMapping -Framework $Framework -NetPlatform $NetPlatform
    New-StandardMapping -Framework $Framework -NetStandard $NetStandard
}

function New-GenerationAndStandardMappingForAllVersions {
    param([string]$Identifier, [NuGetFramework]$NetPlatform, [NuGetFramework]$NetStandard)
    $lowest = [NuGetFramework]::new($Identifier, '0.0.0.0')
    New-GenerationAndStandardMapping -Framework $lowest -NetPlatform $NetPlatform -NetStandard $NetStandard
}

function Initialize-CompatibilityMappings {
    # UAP supports Win81 + WPA81 + NetCore50
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('Windows', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('Windows', '8.1.0.0'))
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('WindowsPhoneApp', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0'))
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('.NETCore', '5.0.0.0')) -SupportedMax ([NuGetFramework]::new('.NETCore', '5.0.0.0'))

    # Windows projects support WinRT
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('Windows', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('Windows', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('WinRT', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('WinRT', '4.5.0.0'))

    # Tizen mappings
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '3.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.6.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '4.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '6.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))

    # UAP 10.0.15064.0 → NetStandard2.0
    New-StandardMapping -Framework ([NuGetFramework]::new('UAP', '10.0.15064.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))

    # NetCoreApp → NetStandard
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '1.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.6.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '1.1.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.7.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '2.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '3.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))

    # net463 → NetStandard2.0
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.3.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))

    # dnxcore50 → dotnet5.6 + netstandard1.5
    New-GenerationAndStandardMappingForAllVersions -Identifier 'DNXCore' -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.5.0.0'))

    # uap → dotnet5.5 + netstandard1.4
    New-GenerationAndStandardMappingForAllVersions -Identifier 'UAP' -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.4.0.0'))

    # netcore50 → dotnet5.5 + netstandard1.4
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '5.0.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.4.0.0'))

    # wpa81 → dotnet5.3 + netstandard1.2
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))

    # wp8/wp81 → dotnet5.1 + netstandard1.0
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('WindowsPhone', '8.0.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.1.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.0.0.0'))

    # net45 → dotnet5.2 + netstandard1.1
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.5.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.2.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.1.0.0'))

    # net451 → dotnet5.3 + netstandard1.2
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.5.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))

    # net46 → dotnet5.4 + netstandard1.3
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.4.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.3.0.0'))

    # net461 → dotnet5.5 + netstandard2.0
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))

    # net462 → dotnet5.6 + netstandard2.0
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.2.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))

    # netcore45 → dotnet5.2 + netstandard1.1
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '4.5.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.2.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.1.0.0'))

    # netcore451 → dotnet5.3 + netstandard1.2
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '4.5.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))

    # Xamarin → dotnet5.6 + netstandard2.1
    foreach ($id in @('MonoAndroid', 'MonoMac', 'MonoTouch', 'Xamarin.iOS', 'Xamarin.Mac', 'Xamarin.TVOS', 'Xamarin.WatchOS')) {
        New-GenerationAndStandardMappingForAllVersions -Identifier $id -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))
    }

    # Xamarin → dotnet5.6 + netstandard2.0
    foreach ($id in @('Xamarin.PlayStation3', 'Xamarin.PlayStation4', 'Xamarin.PlayStationVita', 'Xamarin.Xbox360', 'Xamarin.XboxOne')) {
        New-GenerationAndStandardMappingForAllVersions -Identifier $id -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    }
}

Initialize-CompatibilityMappings

# 已弃用框架别名
$Script:DeprecatedFrameworkAliases = @{
    '45'  = 'net45'; '4.5' = 'net45'
    '40'  = 'net40'; '4.0' = 'net40'; '4' = 'net40'
    '35'  = 'net35'; '3.5' = 'net35'
    '20'  = 'net20'; '2' = 'net20'; '2.0' = 'net20'
}

#endregion

#region 预定义常用框架实例

$Script:CommonFrameworks = @{}

function Initialize-CommonFrameworks {
    $Script:CommonFrameworks['net11']    = [NuGetFramework]::new('.NETFramework', '1.1.0.0')
    $Script:CommonFrameworks['net20']    = [NuGetFramework]::new('.NETFramework', '2.0.0.0')
    $Script:CommonFrameworks['net35']    = [NuGetFramework]::new('.NETFramework', '3.5.0.0')
    $Script:CommonFrameworks['net40']    = [NuGetFramework]::new('.NETFramework', '4.0.0.0')
    $Script:CommonFrameworks['net4']     = $Script:CommonFrameworks['net40']
    $Script:CommonFrameworks['net403']   = [NuGetFramework]::new('.NETFramework', '4.0.3.0')
    $Script:CommonFrameworks['net45']    = [NuGetFramework]::new('.NETFramework', '4.5.0.0')
    $Script:CommonFrameworks['net451']   = [NuGetFramework]::new('.NETFramework', '4.5.1.0')
    $Script:CommonFrameworks['net452']   = [NuGetFramework]::new('.NETFramework', '4.5.2.0')
    $Script:CommonFrameworks['net46']    = [NuGetFramework]::new('.NETFramework', '4.6.0.0')
    $Script:CommonFrameworks['net461']   = [NuGetFramework]::new('.NETFramework', '4.6.1.0')
    $Script:CommonFrameworks['net462']   = [NuGetFramework]::new('.NETFramework', '4.6.2.0')
    $Script:CommonFrameworks['net463']   = [NuGetFramework]::new('.NETFramework', '4.6.3.0')
    $Script:CommonFrameworks['net47']    = [NuGetFramework]::new('.NETFramework', '4.7.0.0')
    $Script:CommonFrameworks['net471']   = [NuGetFramework]::new('.NETFramework', '4.7.1.0')
    $Script:CommonFrameworks['net472']   = [NuGetFramework]::new('.NETFramework', '4.7.2.0')
    $Script:CommonFrameworks['net48']    = [NuGetFramework]::new('.NETFramework', '4.8.0.0')
    $Script:CommonFrameworks['net481']   = [NuGetFramework]::new('.NETFramework', '4.8.1.0')
    $Script:CommonFrameworks['netstandard1.0'] = [NuGetFramework]::new('.NETStandard', '1.0.0.0')
    $Script:CommonFrameworks['netstandard10']  = $Script:CommonFrameworks['netstandard1.0']
    $Script:CommonFrameworks['netstandard1.1'] = [NuGetFramework]::new('.NETStandard', '1.1.0.0')
    $Script:CommonFrameworks['netstandard11']  = $Script:CommonFrameworks['netstandard1.1']
    $Script:CommonFrameworks['netstandard1.2'] = [NuGetFramework]::new('.NETStandard', '1.2.0.0')
    $Script:CommonFrameworks['netstandard12']  = $Script:CommonFrameworks['netstandard1.2']
    $Script:CommonFrameworks['netstandard1.3'] = [NuGetFramework]::new('.NETStandard', '1.3.0.0')
    $Script:CommonFrameworks['netstandard13']  = $Script:CommonFrameworks['netstandard1.3']
    $Script:CommonFrameworks['netstandard1.4'] = [NuGetFramework]::new('.NETStandard', '1.4.0.0')
    $Script:CommonFrameworks['netstandard14']  = $Script:CommonFrameworks['netstandard1.4']
    $Script:CommonFrameworks['netstandard1.5'] = [NuGetFramework]::new('.NETStandard', '1.5.0.0')
    $Script:CommonFrameworks['netstandard15']  = $Script:CommonFrameworks['netstandard1.5']
    $Script:CommonFrameworks['netstandard1.6'] = [NuGetFramework]::new('.NETStandard', '1.6.0.0')
    $Script:CommonFrameworks['netstandard16']  = $Script:CommonFrameworks['netstandard1.6']
    $Script:CommonFrameworks['netstandard1.7'] = [NuGetFramework]::new('.NETStandard', '1.7.0.0')
    $Script:CommonFrameworks['netstandard17']  = $Script:CommonFrameworks['netstandard1.7']
    $Script:CommonFrameworks['netstandard2.0'] = [NuGetFramework]::new('.NETStandard', '2.0.0.0')
    $Script:CommonFrameworks['netstandard20']  = $Script:CommonFrameworks['netstandard2.0']
    $Script:CommonFrameworks['netstandard2.1'] = [NuGetFramework]::new('.NETStandard', '2.1.0.0')
    $Script:CommonFrameworks['netstandard21']  = $Script:CommonFrameworks['netstandard2.1']
    $Script:CommonFrameworks['netcoreapp1.0'] = [NuGetFramework]::new('.NETCoreApp', '1.0.0.0')
    $Script:CommonFrameworks['netcoreapp10']  = $Script:CommonFrameworks['netcoreapp1.0']
    $Script:CommonFrameworks['netcoreapp1.1'] = [NuGetFramework]::new('.NETCoreApp', '1.1.0.0')
    $Script:CommonFrameworks['netcoreapp11']  = $Script:CommonFrameworks['netcoreapp1.1']
    $Script:CommonFrameworks['netcoreapp2.0'] = [NuGetFramework]::new('.NETCoreApp', '2.0.0.0')
    $Script:CommonFrameworks['netcoreapp20']  = $Script:CommonFrameworks['netcoreapp2.0']
    $Script:CommonFrameworks['netcoreapp2.1'] = [NuGetFramework]::new('.NETCoreApp', '2.1.0.0')
    $Script:CommonFrameworks['netcoreapp21']  = $Script:CommonFrameworks['netcoreapp2.1']
    $Script:CommonFrameworks['netcoreapp2.2'] = [NuGetFramework]::new('.NETCoreApp', '2.2.0.0')
    $Script:CommonFrameworks['netcoreapp3.0'] = [NuGetFramework]::new('.NETCoreApp', '3.0.0.0')
    $Script:CommonFrameworks['netcoreapp30']  = $Script:CommonFrameworks['netcoreapp3.0']
    $Script:CommonFrameworks['netcoreapp3.1'] = [NuGetFramework]::new('.NETCoreApp', '3.1.0.0')
    $Script:CommonFrameworks['netcoreapp31']  = $Script:CommonFrameworks['netcoreapp3.1']
    $Script:CommonFrameworks['net5.0']  = [NuGetFramework]::new('.NETCoreApp', '5.0.0.0')
    $Script:CommonFrameworks['net50']   = $Script:CommonFrameworks['net5.0']
    $Script:CommonFrameworks['netcoreapp5.0'] = $Script:CommonFrameworks['net5.0']
    $Script:CommonFrameworks['netcoreapp50']  = $Script:CommonFrameworks['net5.0']
    $Script:CommonFrameworks['net6.0']  = [NuGetFramework]::new('.NETCoreApp', '6.0.0.0')
    $Script:CommonFrameworks['net60']   = $Script:CommonFrameworks['net6.0']
    $Script:CommonFrameworks['netcoreapp6.0'] = $Script:CommonFrameworks['net6.0']
    $Script:CommonFrameworks['netcoreapp60']  = $Script:CommonFrameworks['net6.0']
    $Script:CommonFrameworks['net7.0']  = [NuGetFramework]::new('.NETCoreApp', '7.0.0.0')
    $Script:CommonFrameworks['net70']   = $Script:CommonFrameworks['net7.0']
    $Script:CommonFrameworks['netcoreapp7.0'] = $Script:CommonFrameworks['net7.0']
    $Script:CommonFrameworks['netcoreapp70']  = $Script:CommonFrameworks['net7.0']
    $Script:CommonFrameworks['net8.0']  = [NuGetFramework]::new('.NETCoreApp', '8.0.0.0')
    $Script:CommonFrameworks['net80']   = $Script:CommonFrameworks['net8.0']
    $Script:CommonFrameworks['netcoreapp8.0'] = $Script:CommonFrameworks['net8.0']
    $Script:CommonFrameworks['netcoreapp80']  = $Script:CommonFrameworks['net8.0']
    $Script:CommonFrameworks['net9.0']  = [NuGetFramework]::new('.NETCoreApp', '9.0.0.0')
    $Script:CommonFrameworks['net10.0'] = [NuGetFramework]::new('.NETCoreApp', '10.0.0.0')
    $Script:CommonFrameworks['net11.0'] = [NuGetFramework]::new('.NETCoreApp', '11.0.0.0')
    $Script:CommonFrameworks['net6.0-windows10.0'] = [NuGetFramework]::new('.NETCoreApp', '6.0.0.0', 'windows', '10.0.0.0')
    $Script:CommonFrameworks['net8.0-windows10.0'] = [NuGetFramework]::new('.NETCoreApp', '8.0.0.0', 'windows', '10.0.0.0')
    $Script:CommonFrameworks['net6.0-android'] = [NuGetFramework]::new('.NETCoreApp', '6.0.0.0', 'android', '0.0.0.0')
    $Script:CommonFrameworks['net8.0-android'] = [NuGetFramework]::new('.NETCoreApp', '8.0.0.0', 'android', '0.0.0.0')
    $Script:CommonFrameworks['net6.0-ios'] = [NuGetFramework]::new('.NETCoreApp', '6.0.0.0', 'ios', '0.0.0.0')
    $Script:CommonFrameworks['net8.0-ios'] = [NuGetFramework]::new('.NETCoreApp', '8.0.0.0', 'ios', '0.0.0.0')
    $Script:CommonFrameworks['netcore45']  = [NuGetFramework]::new('.NETCore', '4.5.0.0')
    $Script:CommonFrameworks['netcore451'] = [NuGetFramework]::new('.NETCore', '4.5.1.0')
    $Script:CommonFrameworks['netcore50']  = [NuGetFramework]::new('.NETCore', '5.0.0.0')
    $Script:CommonFrameworks['monoandroid'] = [NuGetFramework]::new('MonoAndroid', '0.0.0.0')
    $Script:CommonFrameworks['monotouch']   = [NuGetFramework]::new('MonoTouch', '0.0.0.0')
    $Script:CommonFrameworks['monomac']     = [NuGetFramework]::new('MonoMac', '0.0.0.0')
    $Script:CommonFrameworks['xamarin.ios']     = [NuGetFramework]::new('Xamarin.iOS', '0.0.0.0')
    $Script:CommonFrameworks['xamarin.mac']     = [NuGetFramework]::new('Xamarin.Mac', '0.0.0.0')
    $Script:CommonFrameworks['xamarin.tvos']    = [NuGetFramework]::new('Xamarin.TVOS', '0.0.0.0')
    $Script:CommonFrameworks['xamarin.watchos'] = [NuGetFramework]::new('Xamarin.WatchOS', '0.0.0.0')
    $Script:CommonFrameworks['win']     = [NuGetFramework]::new('Windows', '8.0.0.0')
    $Script:CommonFrameworks['win8']    = $Script:CommonFrameworks['win']
    $Script:CommonFrameworks['win81']   = [NuGetFramework]::new('Windows', '8.1.0.0')
    $Script:CommonFrameworks['win10']   = [NuGetFramework]::new('Windows', '10.0.0.0')
    $Script:CommonFrameworks['winrt']   = [NuGetFramework]::new('WinRT', '4.5.0.0')
    $Script:CommonFrameworks['winrt45'] = $Script:CommonFrameworks['winrt']
    $Script:CommonFrameworks['wp']      = [NuGetFramework]::new('WindowsPhone', '7.0.0.0')
    $Script:CommonFrameworks['wp7']     = $Script:CommonFrameworks['wp']
    $Script:CommonFrameworks['wp75']    = [NuGetFramework]::new('WindowsPhone', '7.5.0.0')
    $Script:CommonFrameworks['wp8']     = [NuGetFramework]::new('WindowsPhone', '8.0.0.0')
    $Script:CommonFrameworks['wp81']    = [NuGetFramework]::new('WindowsPhone', '8.1.0.0')
    $Script:CommonFrameworks['wpa']     = [NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0')
    $Script:CommonFrameworks['wpa81']   = $Script:CommonFrameworks['wpa']
    $Script:CommonFrameworks['sl4']     = [NuGetFramework]::new('Silverlight', '4.0.0.0')
    $Script:CommonFrameworks['sl5']     = [NuGetFramework]::new('Silverlight', '5.0.0.0')
    $Script:CommonFrameworks['uap10.0'] = [NuGetFramework]::new('UAP', '10.0.0.0')
    $Script:CommonFrameworks['tizen3'] = [NuGetFramework]::new('Tizen', '3.0.0.0')
    $Script:CommonFrameworks['tizen4'] = [NuGetFramework]::new('Tizen', '4.0.0.0')
    $Script:CommonFrameworks['tizen6'] = [NuGetFramework]::new('Tizen', '6.0.0.0')
    $Script:CommonFrameworks['dnx']        = [NuGetFramework]::new('DNX', '0.0.0.0')
    $Script:CommonFrameworks['dnx45']      = [NuGetFramework]::new('DNX', '4.5.0.0')
    $Script:CommonFrameworks['dnx451']     = [NuGetFramework]::new('DNX', '4.5.1.0')
    $Script:CommonFrameworks['dnxcore']    = [NuGetFramework]::new('DNXCore', '0.0.0.0')
    $Script:CommonFrameworks['dnxcore50']  = [NuGetFramework]::new('DNXCore', '5.0.0.0')
    $Script:CommonFrameworks['aspnet50']   = [NuGetFramework]::new('ASP.NET', '5.0.0.0')
    $Script:CommonFrameworks['aspnetcore50'] = [NuGetFramework]::new('ASP.NETCore', '5.0.0.0')
    # 与官方 TryParseCommonFramework 对齐："dotnet", "dotnet50", "dotnet5.0" 均映射到 DotNet50
    $Script:CommonFrameworks['dotnet']   = [NuGetFramework]::new('.NETPlatform', '5.0.0.0')
    $Script:CommonFrameworks['dotnet50'] = $Script:CommonFrameworks['dotnet']
    $Script:CommonFrameworks['dotnet5.0'] = $Script:CommonFrameworks['dotnet']
    $Script:CommonFrameworks['dotnet51'] = [NuGetFramework]::new('.NETPlatform', '5.1.0.0')
    $Script:CommonFrameworks['dotnet52'] = [NuGetFramework]::new('.NETPlatform', '5.2.0.0')
    $Script:CommonFrameworks['dotnet53'] = [NuGetFramework]::new('.NETPlatform', '5.3.0.0')
    $Script:CommonFrameworks['dotnet54'] = [NuGetFramework]::new('.NETPlatform', '5.4.0.0')
    $Script:CommonFrameworks['dotnet55'] = [NuGetFramework]::new('.NETPlatform', '5.5.0.0')
    $Script:CommonFrameworks['dotnet56'] = [NuGetFramework]::new('.NETPlatform', '5.6.0.0')
    $Script:CommonFrameworks['native']   = [NuGetFramework]::new('native', '0.0.0.0')
}

Initialize-CommonFrameworks

#endregion

#region 框架解析

function ConvertTo-NuGetFramework {
    [CmdletBinding()]
    [OutputType([NuGetFramework])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FrameworkString
    )

    process {
        $InputStr = $FrameworkString.Trim()

        if ($InputStr -eq 'any' -or $InputStr -eq 'Any,Version=v0.0') { return $Script:AnyFramework }
        if ($InputStr -eq 'agnostic' -or $InputStr -eq 'Agnostic,Version=v0.0') { return $Script:AgnosticFramework }
        if ($InputStr -eq 'unsupported') { return $Script:UnsupportedFramework }

        if ($Script:CommonFrameworks.ContainsKey($InputStr)) { return $Script:CommonFrameworks[$InputStr] }

        if ($InputStr -match ',Version=v') { return ConvertFrom-FrameworkName -FrameworkName $InputStr }

        return ConvertFrom-FrameworkFolder -Folder $InputStr
    }
}

function ConvertFrom-FrameworkFolder {
    [CmdletBinding()]
    [OutputType([NuGetFramework])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Folder
    )

    $InputStr = $Folder.Trim()

    if ($InputStr.Contains('%')) { $InputStr = [System.Uri]::UnescapeDataString($InputStr) }

    $InputStrLower = $InputStr.ToLowerInvariant()

    switch ($InputStrLower) {
        'any'         { return $Script:AnyFramework }
        'agnostic'    { return $Script:AgnosticFramework }
        'unsupported' { return $Script:UnsupportedFramework }
    }

    # RawParse: 逐字符分段
    $Raw = ConvertFrom-RawParse -InputStr $InputStrLower
    # 与官方对齐：RawParse 失败 → 检查弃用别名 → 仍失败则 UnsupportedFramework
    if (-not $Raw) {
        if ($Script:DeprecatedFrameworkAliases.ContainsKey($InputStrLower)) {
            return $Script:CommonFrameworks[$Script:DeprecatedFrameworkAliases[$InputStrLower]]
        }
        return $Script:UnsupportedFramework
    }

    $Identifier = ''
    $Version = [version]'0.0.0.0'
    $ProfileName = ''

    # 精确匹配短名（与官方 TryGetIdentifier 对齐：仅精确匹配）
    $Matched = $false
    foreach ($entry in $Script:SortedShortNames) {
        if ($Raw.Identifier -eq $entry.Value) { $Identifier = $entry.Key; $Matched = $true; break }
    }
    if (-not $Matched) {
        # 回退：标识符别名或短名反向查找（与官方 TryGetIdentifier 对齐）
        $LowerId = $Raw.Identifier.ToLowerInvariant()
        if ($Script:IdentifierSynonyms.ContainsKey($LowerId)) { $Identifier = $Script:IdentifierSynonyms[$LowerId] }
        elseif ($Script:ShortNameToIdentifier.ContainsKey($Raw.Identifier)) { $Identifier = $Script:ShortNameToIdentifier[$Raw.Identifier] }
        else {
            # 官方：未知标识符返回 UnsupportedFramework
            return $Script:UnsupportedFramework
        }
    }

    if ($Raw.Version) {
        if ($Raw.Version.Contains('.')) { try { $Version = [version]$Raw.Version } catch { throw "无法解析框架版本号 '$($Raw.Version)'" } }
        else { $Version = ConvertTo-NuGetFrameworkVersion -VersionString $Raw.Version }
    }

    # net ≥ 5.0 → .NETCoreApp
    if ($Identifier -eq '.NETFramework' -and $Version.Major -ge 5) { $Identifier = '.NETCoreApp' }

    # .NET 5.0+ 平台处理
    if ($Identifier -eq '.NETCoreApp' -and $Version.Major -ge 5 -and $Raw.ProfilePart) {
        $PlatformResult = ConvertFrom-PlatformString -PlatformString $Raw.ProfilePart
        return [NuGetFramework]::new($Identifier, $Version, $PlatformResult.Name, $PlatformResult.Version)
    }

    # PCL / Profile
    if ($Identifier -eq '.NETPortable' -and $Raw.ProfilePart) { $ProfileName = $Raw.ProfilePart }
    elseif ($Raw.ProfilePart -and $Identifier -ne '.NETCoreApp') {
        $ProfileName = Resolve-ProfileShortName -Framework $Identifier -ShortProfile $Raw.ProfilePart
    }

    return [NuGetFramework]::new($Identifier, $Version, $ProfileName)
}

function ConvertFrom-RawParse {
    param([string]$InputStr)
    $Chars = $InputStr.ToCharArray(); $Len = $Chars.Count

    $IdEnd = 0
    while ($IdEnd -lt $Len -and ($Chars[$IdEnd] -match '[a-zA-Z\.]')) { $IdEnd++ }
    if ($IdEnd -eq 0) { return $null }

    $Identifier = $InputStr.Substring(0, $IdEnd)
    $VerEnd = $IdEnd
    while ($VerEnd -lt $Len -and ($Chars[$VerEnd] -match '[\d\.]')) { $VerEnd++ }
    $Version = if ($VerEnd -gt $IdEnd) { $InputStr.Substring($IdEnd, $VerEnd - $IdEnd) } else { '' }
    $ProfilePart = ''
    if ($VerEnd -lt $Len -and $Chars[$VerEnd] -eq '-') {
        $ProfilePart = $InputStr.Substring($VerEnd + 1)
        # 校验 Profile 字符合法性（与官方 IsValidProfileChar 对齐：字母、数字、.、-、+）
        foreach ($c in $ProfilePart.ToCharArray()) {
            $x = [int]$c
            if (-not (($x -ge 48 -and $x -le 57) -or ($x -ge 65 -and $x -le 90) -or ($x -ge 97 -and $x -le 122) -or $x -eq 46 -or $x -eq 43 -or $x -eq 45)) {
                return $null
            }
        }
        # 空 Profile 不允许
        if ($ProfilePart.Length -eq 0) { return $null }
    }

    return @{ Identifier = $Identifier; Version = $Version; ProfilePart = $ProfilePart }
}

function Resolve-ProfileShortName {
    param([string]$Framework, [string]$ShortProfile)
    foreach ($mapping in $Script:ProfileShortNames) {
        if ($mapping.Framework -eq $Framework -and $mapping.ShortProfile -eq $ShortProfile) { return $mapping.Profile }
    }
    return $ShortProfile
}

function ConvertFrom-FrameworkName {
    [CmdletBinding()]
    [OutputType([NuGetFramework])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FrameworkName
    )

    $Parts = $FrameworkName -split ',' | ForEach-Object { $_.Trim() }
    $Identifier = $Parts[0]
    $Version = [version]'0.0.0.0'
    $ProfileName = ''
    $Platform = ''
    $PlatformVersion = [version]'0.0.0.0'

    $LowerId = $Identifier.ToLowerInvariant()
    if ($Script:IdentifierSynonyms.ContainsKey($LowerId)) { $Identifier = $Script:IdentifierSynonyms[$LowerId] }

    for ($i = 1; $i -lt $Parts.Count; $i++) {
        $Part = $Parts[$i]
        if ($Part.StartsWith('Version=v', [System.StringComparison]::OrdinalIgnoreCase)) {
            $VerStr = $Part.Substring(9).TrimStart('v')
            if (-not $VerStr.Contains('.')) { $VerStr += '.0' }
            $Version = [version]$VerStr
        }
        elseif ($Part.StartsWith('Profile=', [System.StringComparison]::OrdinalIgnoreCase)) { $ProfileName = $Part.Substring(8) }
        elseif ($Part.StartsWith('Platform=', [System.StringComparison]::OrdinalIgnoreCase)) { $Platform = $Part.Substring(9) }
        elseif ($Part.StartsWith('PlatformVersion=v', [System.StringComparison]::OrdinalIgnoreCase)) { $PlatformVersion = [version]$Part.Substring(17).TrimStart('v') }
    }

    if ($Identifier -eq '.NETPortable' -and $ProfileName -and $ProfileName.Contains('-')) {
        throw "PCL profile 不允许包含连字符：$ProfileName"
    }

    return [NuGetFramework]::new($Identifier, $Version, $ProfileName, $Platform, $PlatformVersion)
}

function ConvertTo-NuGetFrameworkVersion {
    [CmdletBinding()]
    [OutputType([version])]
    param([Parameter(Mandatory = $true)][string]$VersionString)

    $InputStr = $VersionString.Trim()

    if ($InputStr.Contains('.')) {
        try { return [version]$InputStr } catch { throw "无效的框架版本号：'$VersionString'" }
    }

    if ($InputStr -notmatch '^\d+$') { throw "框架版本号包含非数字字符：'$VersionString'" }

    # 与官方 TryGetVersion 对齐：仅取前4位字符，逐位用 '.' 拼接
    $chars = $InputStr.ToCharArray()
    $takeCount = [Math]::Min($chars.Length, 4)
    $versionStr = ($chars[0..($takeCount - 1)] -join '.')
    return [version]$versionStr
}

function ConvertFrom-PlatformString {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory = $true)][string]$PlatformString)

    $InputStr = $PlatformString.Trim()
    # 仿照官方 ParseFolder 逐字符扫描：分离平台名称和版本号
    $chars = $InputStr.ToCharArray()
    $nameEnd = 0
    while ($nameEnd -lt $chars.Count -and ($chars[$nameEnd] -match '[a-zA-Z\.]')) { $nameEnd++ }
    if ($nameEnd -eq 0) { throw "无法解析平台字符串：'$PlatformString'" }
    $Name = $InputStr.Substring(0, $nameEnd).ToLowerInvariant()
    $VersionStr = if ($nameEnd -lt $chars.Count) { $InputStr.Substring($nameEnd) } else { '' }

    if ([string]::IsNullOrEmpty($VersionStr)) {
        return @{ Name = $Name; Version = [version]'0.0.0.0' }
    }
    # 与官方 TryGetPlatformVersion 对齐：无点号的版本字符串补 .0
    if ($VersionStr.IndexOf('.') -lt 0) {
        $VersionStr += '.0'
    }
    try {
        return @{ Name = $Name; Version = [version]$VersionStr }
    }
    catch {
        throw "无法解析平台版本号：'$PlatformString'"
    }
}

#endregion

#region 短名称转换

function ConvertTo-NuGetFrameworkShortName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NuGetFramework]$Framework
    )

    if ($Framework.IsAny()) { return 'any' }
    if ($Framework.IsAgnostic()) { return 'agnostic' }
    if ($Framework.IsUnsupported()) { return 'unsupported' }
    if (-not $Framework.IsSpecificFramework()) { return $Framework.Framework.ToLowerInvariant() }

    $lookupId = $Framework.GetFrameworkIdentifier()
    $ShortFramework = if ($Script:IdentifierShortNames.ContainsKey($lookupId)) { $Script:IdentifierShortNames[$lookupId] }
    else { ($lookupId -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() }

    $VerStr = ''
    if (-not $Framework.AllFrameworkVersions()) { $VerStr = Get-FrameworkVersionString -Framework $Framework }

    $Result = "$ShortFramework$VerStr"

    if ($Framework.IsPCL()) {
        # 与官方 GetShortFolderName 对齐：展开 PCL Profile 到组成框架列表
        $pclFrameworks = Get-PCLFrameworks -Pcl $Framework -IncludeOptional:$false
        if ($pclFrameworks -and $pclFrameworks.Count -gt 0) {
            # 按短名称字母排序后以 + 连接
            $sortedNames = @($pclFrameworks | ForEach-Object { ConvertTo-NuGetFrameworkShortName -Framework $_ } | Sort-Object)
            return "portable-$($sortedNames -join '+')"
        }
        # 回退：无法解析的 PCL profile 直接使用原始值
        return "portable-$($Framework.ProfileName)".ToLowerInvariant()
    }

    if ($Framework.IsNet5Era()) {
        if ($Framework.HasPlatform()) {
            $Result += "-$($Framework.Platform.ToLowerInvariant())"
            if ($Framework.PlatformVersion -ne [version]'0.0.0.0') { $Result += Get-FrameworkVersionString -Framework $Framework -ForPlatform }
        }
    }
    else {
        if ($Framework.HasProfile()) {
            $ShortProfile = $Framework.ProfileName
            foreach ($mapping in $Script:ProfileShortNames) {
                if ($mapping.Framework -eq $Framework.Framework -and $mapping.Profile -eq $Framework.ProfileName) { $ShortProfile = $mapping.ShortProfile; break }
            }
            if ($ShortProfile) { $Result += "-$ShortProfile" }
        }
    }

    return $Result.ToLowerInvariant()
}

function Get-FrameworkVersionString {
    param([NuGetFramework]$Framework, [switch]$ForPlatform)
    $Ver = if ($ForPlatform) { $Framework.PlatformVersion } else { $Framework.Version }

    # 全零版本 → 空字符串
    if ($Ver.Major -le 0 -and $Ver.Minor -le 0 -and $Ver.Build -le 0 -and $Ver.Revision -le 0) { return '' }

    $major = if ($Ver.Major -gt 0) { $Ver.Major } else { 0 }
    $minor = if ($Ver.Minor -gt 0) { $Ver.Minor } else { 0 }
    $build = if ($Ver.Build -gt 0) { $Ver.Build } else { 0 }
    $revision = if ($Ver.Revision -gt 0) { $Ver.Revision } else { 0 }

    # 计算有效部件数（从 minor 开始去尾零）
    if ($revision -gt 0) { $partCount = 4 }
    elseif ($build -gt 0) { $partCount = 3 }
    elseif ($minor -gt 0) { $partCount = 2 }
    else { $partCount = 1 }

    # 平台版本始终使用点分格式（至少保留 Major.Minor）
    if ($ForPlatform) {
        if ($partCount -lt 2) { $partCount = 2 }
        $result = "$major"
        if ($partCount -gt 1) { $result += ".$minor" }
        if ($partCount -gt 2) { $result += ".$build" }
        if ($partCount -gt 3) { $result += ".$revision" }
        return $result
    }

    # 单位数版本框架（Windows, WindowsPhone, Silverlight, Tizen）允许单段版本号
    $singleDigitFrameworks = @('Windows', 'WindowsPhone', 'Silverlight', 'Tizen')
    # 点分框架（总是使用小数点分隔）—— 对应官方 DecimalPointFrameworks
    $decimalPointFrameworks = @('.NETCoreApp', '.NETStandard', '.NETnanoFramework')

    $isSingleDigit = $singleDigitFrameworks -contains $Framework.Framework
    $isDecimalPoint = $decimalPointFrameworks -contains $Framework.Framework

    # 非单位数框架且 partCount=1 → 至少 Major.Minor
    if ($partCount -eq 1 -and -not $isSingleDigit) { $partCount = 2 }

    # 任一部分 > 9 时必须使用点分（防止歧义）
    $hasLargePart = ($major -gt 9 -or $minor -gt 9 -or $build -gt 9 -or $revision -gt 9)

    if ($isDecimalPoint -or $hasLargePart) {
        if ($partCount -eq 1) { $partCount = 2 }
        $result = "$major"
        if ($partCount -gt 1) { $result += ".$minor" }
        if ($partCount -gt 2) { $result += ".$build" }
        if ($partCount -gt 3) { $result += ".$revision" }
        return $result
    }
    else {
        # 数字拼接格式（如 net472、dotnet52）
        $result = "$major"
        if ($partCount -gt 1) { $result += "$minor" }
        if ($partCount -gt 2) { $result += "$build" }
        if ($partCount -gt 3) { $result += "$revision" }
        return $result
    }
}

function ConvertTo-NuGetFrameworkFullName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NuGetFramework]$Framework
    )

    if (-not $Framework.IsSpecificFramework()) { return "$($Framework.Framework),Version=v0.0" }

    $name = "$($Framework.Framework),Version=v$($Framework.Version.Major).$($Framework.Version.Minor)"
    if ($Framework.Version.Build -gt 0 -or $Framework.Version.Revision -gt 0) { $name = "$($Framework.Framework),Version=v$($Framework.Version)" }
    if ($Framework.HasProfile()) { $name += ",Profile=$($Framework.ProfileName)" }
    return $name
}

#endregion

#region 框架兼容性

function Test-NuGetFrameworkCompatibility {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        $Target,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        $Candidate
    )

    $TargetFx = if ($Target -is [NuGetFramework]) { $Target } else { ConvertTo-NuGetFramework -FrameworkString $Target }
    $CandidateFx = if ($Candidate -is [NuGetFramework]) { $Candidate } else { ConvertTo-NuGetFramework -FrameworkString $Candidate }

    if ($TargetFx.Equals($CandidateFx)) { return $true }
    if ($TargetFx.IsAny() -or $CandidateFx.IsAny()) { return $true }
    # 与官方 IsSpecialFrameworkCompatible 顺序对齐: Unsupported 优先于 Agnostic
    if ($TargetFx.IsUnsupported()) { return $false }
    if ($CandidateFx.IsAgnostic()) { return $true }
    if ($CandidateFx.IsUnsupported()) { return $false }

    # PCL 兼容性路径（与官方 IsPCLCompatible 对齐）
    if ($TargetFx.IsPCL() -or $CandidateFx.IsPCL()) {
        return Test-PCLCompatibility -Target $TargetFx -Candidate $CandidateFx
    }

    # Target 等价闭包展开
    $TargetSet = @($TargetFx)
    $TargetSet += Expand-Framework -Framework $TargetFx

    # Candidate 等价闭包展开
    $CandidateSet = @($CandidateFx)
    $CandidateSet += Get-EquivalentFrameworksClosure -Framework $CandidateFx

    foreach ($tc in $TargetSet) {
        foreach ($cc in $CandidateSet) {
            if (Test-FrameworkCompatibilityCore -Target $tc -Candidate $cc) { return $true }
        }
    }

    return $false
}

function Test-PCLCompatibility {
    param([NuGetFramework]$Target, [NuGetFramework]$Candidate)

    # PCL target + 非PCL candidate: 展开 PCL 组成框架，检查 candidate 是否与任一组成框架兼容
    if ($Target.IsPCL() -and -not $Candidate.IsPCL()) {
        $targetFrameworks = Get-PCLFrameworks -Pcl $Target -IncludeOptional:$false
        if ($targetFrameworks -and $targetFrameworks.Count -gt 0) {
            foreach ($tf in $targetFrameworks) {
                if (Test-NuGetFrameworkCompatibility -Target $tf -Candidate $Candidate) { return $true }
            }
        }
        return $false
    }

    # 非PCL target + PCL candidate: 展开 candidate PCL（含 optional）检查覆盖
    if (-not $Target.IsPCL() -and $Candidate.IsPCL()) {
        $candidateFrameworks = Get-PCLFrameworks -Pcl $Candidate -IncludeOptional:$true
        if (-not $candidateFrameworks -or $candidateFrameworks.Count -eq 0) { return $false }
        return ($candidateFrameworks | Where-Object { Test-NuGetFrameworkCompatibility -Target $Target -Candidate $_ }).Count -gt 0
    }

    # PCL+PCL: 双方展开后检查
    $targetFrameworks = Get-PCLFrameworks -Pcl $Target -IncludeOptional:$false
    $candidateFrameworks = Get-PCLFrameworks -Pcl $Candidate -IncludeOptional:$true
    if (-not $targetFrameworks -or $targetFrameworks.Count -eq 0) { return $false }
    if (-not $candidateFrameworks -or $candidateFrameworks.Count -eq 0) { return $false }
    # candidate 必须覆盖 target 的所有框架
    foreach ($tf in $targetFrameworks) {
        $covered = $false
        foreach ($cf in $candidateFrameworks) {
            if (Test-NuGetFrameworkCompatibility -Target $tf -Candidate $cf) { $covered = $true; break }
        }
        if (-not $covered) { return $false }
    }
    return $true
}

function Get-PCLFrameworks {
    param([NuGetFramework]$Pcl, [bool]$IncludeOptional)
    $profileStr = $Pcl.ProfileName
    if (-not $profileStr) { return $null }
    # PCL Profile 格式: "Profile{number}" 或 "framework1+framework2+..."
    if ($profileStr -match '^Profile(\d+)$') {
        $profileNum = [int]$Matches[1]
        return Get-PCLProfileFrameworks -ProfileNumber $profileNum -IncludeOptional:$IncludeOptional
    }
    # 非标准 profile（如 "net45+win8"），按 + 分割
    $parts = $profileStr -split '\+'
    $result = [System.Collections.Generic.List[NuGetFramework]]::new()
    foreach ($part in $parts) {
        try { $result.Add((ConvertTo-NuGetFramework -FrameworkString $part)) } catch { }
    }
    return $result.ToArray()
}

function Get-PCLProfileFrameworks {
    param([int]$ProfileNumber, [bool]$IncludeOptional)
    # 完整的 PCL Profile → 组成框架映射（与官方 DefaultPortableFrameworkMappings 对齐）
    $pclMap = @{
        2   = @('net40', 'win8', 'sl4', 'wp7')
        3   = @('net40', 'sl4')
        4   = @('net45', 'sl4', 'win8', 'wp7')
        5   = @('net40', 'win8')
        6   = @('net403', 'win8')
        7   = @('net45', 'win8')
        14  = @('net40', 'sl5')
        18  = @('net403', 'sl4')
        19  = @('net403', 'sl5')
        23  = @('net45', 'sl4')
        24  = @('net45', 'sl5')
        31  = @('win81', 'wp81')
        32  = @('win81', 'wpa81')
        36  = @('net40', 'sl4', 'win8', 'wp8')
        37  = @('net40', 'sl5', 'win8')
        41  = @('net403', 'sl4', 'win8')
        42  = @('net403', 'sl5', 'win8')
        44  = @('net451', 'win81')
        46  = @('net45', 'sl4', 'win8')
        47  = @('net45', 'sl5', 'win8')
        49  = @('net45', 'wp8')
        78  = @('net45', 'win8', 'wp8')
        84  = @('wp81', 'wpa81')
        88  = @('net40', 'sl4', 'win8', 'wp75')
        92  = @('net40', 'win8', 'wpa81')
        95  = @('net403', 'sl4', 'win8', 'wp7')
        96  = @('net403', 'sl4', 'win8', 'wp75')
        102 = @('net403', 'win8', 'wpa81')
        104 = @('net45', 'sl4', 'win8', 'wp75')
        111 = @('net45', 'win8', 'wpa81')
        136 = @('net40', 'sl5', 'win8', 'wp8')
        143 = @('net403', 'sl4', 'win8', 'wp8')
        147 = @('net403', 'sl5', 'win8', 'wp8')
        151 = @('net451', 'win81', 'wpa81')
        154 = @('net45', 'sl4', 'win8', 'wp8')
        157 = @('win81', 'wp81', 'wpa81')
        158 = @('net45', 'sl5', 'win8', 'wp8')
        225 = @('net40', 'sl5', 'win8', 'wpa81')
        240 = @('net403', 'sl5', 'win8', 'wpa81')
        255 = @('net45', 'sl5', 'win8', 'wpa81')
        259 = @('net45', 'win8', 'wpa81', 'wp8')
        328 = @('net40', 'sl5', 'win8', 'wpa81', 'wp8')
        336 = @('net403', 'sl5', 'win8', 'wpa81', 'wp8')
        344 = @('net45', 'sl5', 'win8', 'wpa81', 'wp8')
    }
    if (-not $pclMap.ContainsKey($ProfileNumber)) { return @() }
    $result = [System.Collections.Generic.List[NuGetFramework]]::new()
    foreach ($key in $pclMap[$ProfileNumber]) {
        if ($Script:CommonFrameworks.ContainsKey($key)) {
            $result.Add($Script:CommonFrameworks[$key])
        }
    }
    # 可选框架：MonoAndroid + MonoTouch + Xamarin.iOS/Mac/TVOS/WatchOS
    if ($IncludeOptional) {
        $optionalProfiles = @(5, 6, 7, 14, 19, 24, 37, 42, 44, 47, 49, 78, 92, 102, 111, 136, 147, 151, 158, 225, 255, 259, 328, 336, 344)
        if ($ProfileNumber -in $optionalProfiles) {
            foreach ($key in @('monoandroid', 'monotouch', 'xamarin.ios', 'xamarin.mac', 'xamarin.watchos', 'xamarin.tvos')) {
                if ($Script:CommonFrameworks.ContainsKey($key)) {
                    $result.Add($Script:CommonFrameworks[$key])
                }
            }
        }
    }
    return $result.ToArray()
}

function Test-FrameworkCompatibilityCore {
    param([NuGetFramework]$Target, [NuGetFramework]$Candidate)

    $isNet6Era = $Target.IsNet5Era() -and $Target.Version.Major -ge 6

    # net6.0+ 跨框架平台映射: MonoAndroid→android, Tizen→tizen
    if ($isNet6Era -and $Target.HasPlatform() -and $Target.Framework -ne $Candidate.Framework) {
        if ($Candidate.Framework -eq 'MonoAndroid') { return ($Target.Platform -eq 'android') }
        if ($Candidate.Framework -eq 'Tizen') { return ($Target.Platform -eq 'tizen') }
        return $false
    }

    # 同标识符检查
    if ($Target.Framework -ne $Candidate.Framework) { return $false }

    # 版本兼容性: candidate 全零版本视为通配
    $versionOk = ($Candidate.Version -eq [version]'0.0.0.0' -or $Target.Version -ge $Candidate.Version)
    # Profile 精确匹配（等价 Profile 已在 Expand/Closure 阶段完成展开，与官方对齐）
    $profileOk = ($Target.ProfileName -eq $Candidate.ProfileName)
    if (-not $versionOk -or -not $profileOk) { return $false }

    # 平台检查（与官方 IsCompatibleWithTargetCore 对齐）
    if ($Target.IsNet5Era() -and $Candidate.HasPlatform()) {
        # .NET 10+ Windows TFM: 不同 CsWinRT 修订版本不兼容
        if ($Target.Version.Major -ge 10 -and
            $Target.Platform -eq 'windows' -and $Target.PlatformVersion.Major -ge 10 -and
            $Candidate.PlatformVersion.Major -ge 10 -and
            $Target.PlatformVersion.Revision -ne $Candidate.PlatformVersion.Revision) {
            return $false
        }
        if ($Target.Platform -ne $Candidate.Platform) { return $false }
        return ($Target.PlatformVersion -ge $Candidate.PlatformVersion)
    }

    # net5Era 下 Target 无平台但 Candidate 有平台 → 不兼容
    if ($Target.IsNet5Era() -and -not $Target.HasPlatform() -and $Candidate.HasPlatform()) { return $false }

    return $true
}

# 生成框架唯一键（含 Platform/PlatformVersion，与官方 NuGetFrameworkFullComparer 对齐）
function Get-FrameworkUniqueKey {
    param([NuGetFramework]$Framework)
    return "$($Framework.Framework)|$($Framework.Version)|$($Framework.ProfileName)|$($Framework.Platform)|$($Framework.PlatformVersion)"
}

function Expand-Framework {
    param([NuGetFramework]$Framework)

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $seen.Add((Get-FrameworkUniqueKey $Framework)) | Out-Null
    $toExpand = [System.Collections.Generic.Stack[NuGetFramework]]::new()
    $toExpand.Push($Framework)
    $results = [System.Collections.Generic.List[NuGetFramework]]::new()

    while ($toExpand.Count -gt 0) {
        $current = $toExpand.Pop()

        # 框架级别等价（与官方 FrameworkExpander + FrameworkRange 对齐）
        # 逻辑：若 equiv.A 的版本落在 [0.0, current.Version] 区间内，则 equiv.B 是 current 的等价展开项
        foreach ($equiv in $Script:EquivalentFrameworksFull) {
            # 精确等价：A ↔ B
            if ($equiv.A.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.B
                if ($seen.Add($key)) { $results.Add($equiv.B); $toExpand.Push($equiv.B) }
            }
            if ($equiv.B.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.A
                if ($seen.Add($key)) { $results.Add($equiv.A); $toExpand.Push($equiv.A) }
            }
            # 范围等价：equiv.A.Version ∈ [0.0, current.Version] → equiv.B 是等价项
            # 注意：此处检查 equiv.A.Version <= current.Version（而非 current.Version <= equiv.A.Version）
            if ($equiv.A.Framework -eq $current.Framework -and
                $equiv.A.ProfileName -eq $current.ProfileName -and
                -not $equiv.A.Equals($current) -and
                $equiv.A.Version -ge [version]'0.0.0.0' -and
                $equiv.A.Version -le $current.Version) {
                $key = Get-FrameworkUniqueKey $equiv.B
                if ($seen.Add($key)) { $results.Add($equiv.B); $toExpand.Push($equiv.B) }
            }
            if ($equiv.B.Framework -eq $current.Framework -and
                $equiv.B.ProfileName -eq $current.ProfileName -and
                -not $equiv.B.Equals($current) -and
                $equiv.B.Version -ge [version]'0.0.0.0' -and
                $equiv.B.Version -le $current.Version) {
                $key = Get-FrameworkUniqueKey $equiv.A
                if ($seen.Add($key)) { $results.Add($equiv.A); $toExpand.Push($equiv.A) }
            }
        }

        # Profile 等价展开（与官方 _equivalentProfiles 对齐）
        foreach ($ep in $Script:EquivalentProfiles) {
            if ($ep.Framework -eq $current.Framework) {
                if ($ep.Profile -eq $current.ProfileName) {
                    $eqFx = [NuGetFramework]::new($current.Framework, $current.Version, $ep.Equivalent)
                    $key = Get-FrameworkUniqueKey $eqFx
                    if ($seen.Add($key)) { $results.Add($eqFx); $toExpand.Push($eqFx) }
                }
                if ($ep.Equivalent -eq $current.ProfileName) {
                    $eqFx = [NuGetFramework]::new($current.Framework, $current.Version, $ep.Profile)
                    $key = Get-FrameworkUniqueKey $eqFx
                    if ($seen.Add($key)) { $results.Add($eqFx); $toExpand.Push($eqFx) }
                }
            }
        }

        if (-not $current.HasProfile()) {
            if ($Script:SubSetFrameworks.ContainsKey($current.Framework)) {
                foreach ($subId in $Script:SubSetFrameworks[$current.Framework]) {
                    $subFx = [NuGetFramework]::new($subId, $current.Version, $current.ProfileName)
                    $key = Get-FrameworkUniqueKey $subFx
                    if ($seen.Add($key)) { $results.Add($subFx); $toExpand.Push($subFx) }
                }
            }
        }

        foreach ($mapping in $Script:OneWayCompatibilityMappings) {
            if ($current.Framework -eq $mapping.TargetMin.Framework -and
                $current.Version -ge $mapping.TargetMin.Version -and
                $current.Version -le $mapping.TargetMax.Version) {
                $s = $mapping.SupportedMin
                $key = Get-FrameworkUniqueKey $s
                if ($seen.Add($key)) { $results.Add($s) }
                if (-not $mapping.SupportedMin.Equals($mapping.SupportedMax)) {
                    $s = $mapping.SupportedMax
                    $key = Get-FrameworkUniqueKey $s
                    if ($seen.Add($key)) { $results.Add($s) }
                }
            }
        }
    }

    # PCL → netstandard 兼容展开（与官方 FrameworkExpander + DefaultPortableFrameworkMappings 对齐）
    # 此操作在循环外部执行，不参与递归展开
    if ($Framework.IsPCL()) {
        $profileNum = -1
        if ($Framework.ProfileName -match '^Profile(\d+)$') { $profileNum = [int]$Matches[1] }
        # PCL Profile → netstandard 兼容映射（与官方 CompatibilityMappings 对齐）
        $pclNetStandardMap = @{
            7   = 'netstandard1.1'
            31  = 'netstandard1.0'
            32  = 'netstandard1.2'
            44  = 'netstandard1.2'
            49  = 'netstandard1.0'
            78  = 'netstandard1.0'
            84  = 'netstandard1.0'
            111 = 'netstandard1.1'
            151 = 'netstandard1.2'
            157 = 'netstandard1.0'
            259 = 'netstandard1.0'
        }
        if ($pclNetStandardMap.ContainsKey($profileNum)) {
            $ns = $Script:CommonFrameworks[$pclNetStandardMap[$profileNum]]
            if ($ns) {
                $key = Get-FrameworkUniqueKey $ns
                if ($seen.Add($key)) { $results.Add($ns) }
            }
        }
    }

    return $results.ToArray()
}

function Get-EquivalentFrameworksClosure {
    param([NuGetFramework]$Framework)

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $seen.Add((Get-FrameworkUniqueKey $Framework)) | Out-Null
    $toExpand = [System.Collections.Generic.Stack[NuGetFramework]]::new()
    $toExpand.Push($Framework)
    $results = [System.Collections.Generic.List[NuGetFramework]]::new()

    while ($toExpand.Count -gt 0) {
        $current = $toExpand.Pop()

        # 框架级别等价
        foreach ($equiv in $Script:EquivalentFrameworksFull) {
            if ($equiv.A.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.B
                if ($seen.Add($key)) { $results.Add($equiv.B); $toExpand.Push($equiv.B) }
            }
            if ($equiv.B.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.A
                if ($seen.Add($key)) { $results.Add($equiv.A); $toExpand.Push($equiv.A) }
            }
        }

        # Profile 级别等价（与官方 _equivalentProfiles 对齐）
        # 仅对当前弹出框架本身查找其 ProfileName 的等价替代
        foreach ($ep in $Script:EquivalentProfiles) {
            if ($ep.Framework -eq $current.Framework) {
                if ($ep.Profile -eq $current.ProfileName) {
                    $eqFx = [NuGetFramework]::new($current.Framework, $current.Version, $ep.Equivalent)
                    $key = Get-FrameworkUniqueKey $eqFx
                    if ($seen.Add($key)) { $results.Add($eqFx); $toExpand.Push($eqFx) }
                }
                if ($ep.Equivalent -eq $current.ProfileName) {
                    $eqFx = [NuGetFramework]::new($current.Framework, $current.Version, $ep.Profile)
                    $key = Get-FrameworkUniqueKey $eqFx
                    if ($seen.Add($key)) { $results.Add($eqFx); $toExpand.Push($eqFx) }
                }
            }
        }
    }

    return $results.ToArray()
}

function Test-EquivalentProfiles {
    param([string]$Framework, [string]$ProfileA, [string]$ProfileB)
    if ($ProfileA -eq $ProfileB) { return $true }
    foreach ($ep in $Script:EquivalentProfiles) {
        if ($ep.Framework -eq $Framework) {
            if (($ep.Profile -eq $ProfileA -and $ep.Equivalent -eq $ProfileB) -or
                ($ep.Profile -eq $ProfileB -and $ep.Equivalent -eq $ProfileA)) {
                return $true
            }
        }
    }
    return $false
}

function Test-VersionInRange {
    param([version]$Version, [version]$MinVersion, [version]$MaxVersion)
    return ($Version -ge $MinVersion -and $Version -le $MaxVersion)
}

#endregion

#region 框架就近匹配

function Get-NearestNuGetFramework {
    [CmdletBinding()]
    [OutputType([NuGetFramework])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Target,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Candidates
    )

    $TargetFx = if ($Target -is [NuGetFramework]) { $Target } else { ConvertTo-NuGetFramework -FrameworkString $Target }
    $CandidateFxs = foreach ($c in $Candidates) { if ($c -is [NuGetFramework]) { $c } else { ConvertTo-NuGetFramework -FrameworkString $c } }
    if ($CandidateFxs.Count -eq 0) { return $null }

    $nonUnsupported = @($CandidateFxs | Where-Object { -not $_.IsUnsupported() })
    if ($nonUnsupported.Count -gt 0) { $CandidateFxs = $nonUnsupported }

    $Exact = @($CandidateFxs | Where-Object { $_.Equals($TargetFx) })
    if ($Exact.Count -eq 1) { return $Exact[0] }

    $Compatible = @($CandidateFxs | Where-Object { Test-NuGetFrameworkCompatibility -Target $TargetFx -Candidate $_ })
    if ($Compatible.Count -eq 0) { return $null }
    if ($Compatible.Count -eq 1) { return $Compatible[0] }

    $Reduced = @(Resolve-FrameworksUpwards -Frameworks $Compatible)

    # net6Era 跨框架匹配: MonoAndroid→android, Tizen→tizen
    $isNet6Era = $TargetFx.IsNet5Era() -and $TargetFx.Version.Major -ge 6
    if ($Reduced.Count -gt 1 -and ($Reduced | Where-Object { $_.Framework -eq $TargetFx.Framework }).Count -gt 0) {
        $Reduced = @($Reduced | Where-Object {
            if ($isNet6Era -and $TargetFx.HasPlatform() -and ($_.Framework -eq 'MonoAndroid' -or $_.Framework -eq 'Tizen')) { return $true }
            return ($_.Framework -eq $TargetFx.Framework)
        })
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }

    # PCL 过滤（与官方对齐：优先非 PCL）
    $withPcl = @($Reduced | Where-Object { $_.IsPCL() })
    $withoutPcl = @($Reduced | Where-Object { -not $_.IsPCL() })
    if ($withoutPcl.Count -gt 0 -and $withPcl.Count -gt 0) { $Reduced = $withoutPcl }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }

    # 包分发框架过滤（仅当 Target 不是包分发框架时）
    if (-not $TargetFx.IsPackageBased()) {
        $nonPackage = @($Reduced | Where-Object { -not $_.IsPackageBased() })
        if ($nonPackage.Count -gt 0) { $Reduced = $nonPackage }
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }

    # Profile 匹配
    if ($TargetFx.HasProfile()) {
        $sameProfile = @($Reduced | Where-Object { $_.Framework -eq $TargetFx.Framework -and $_.ProfileName -eq $TargetFx.ProfileName })
        if ($sameProfile.Count -gt 0) { $Reduced = $sameProfile }
    }
    if ($Reduced.Count -gt 1) {
        $withProfile = @($Reduced | Where-Object { $_.HasProfile() })
        $withoutProfile = @($Reduced | Where-Object { -not $_.HasProfile() })
        if ($withoutProfile.Count -gt 0 -and $withProfile.Count -gt 0) { $Reduced = $withoutProfile }
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }

    # net6Era 平台匹配：Target 有平台时，优先交叉框架映射（MonoAndroid→android, Tizen→tizen）
    if ($TargetFx.HasPlatform() -and $Reduced.Count -gt 1) {
        $crossMatches = @()
        if ($isNet6Era) {
            if ($TargetFx.Platform -eq 'android') { $crossMatches = @($Reduced | Where-Object { $_.Framework -eq 'MonoAndroid' }) }
            elseif ($TargetFx.Platform -eq 'tizen') { $crossMatches = @($Reduced | Where-Object { $_.Framework -eq 'Tizen' }) }
        }
        if ($crossMatches.Count -gt 0) {
            $Reduced = $crossMatches
        }
        elseif ((-not $isNet6Era) -or ($Reduced | Where-Object { $_.Framework -eq $TargetFx.Framework -and $_.Version.Major -ge 6 }).Count -gt 0) {
            $Reduced = @($Reduced | Where-Object { $_.Framework -eq $TargetFx.Framework } |
                Group-Object -Property Version |
                Sort-Object -Property Name -Descending |
                Select-Object -First 1 |
                ForEach-Object { $_.Group })
        }
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }

    # 与官方 FrameworkPrecedenceSorter 对齐：非包分发框架优先级（NonPackageBased）在前，包分发框架（PackageBased）在后
    return ($Reduced | Sort-Object -Property {
        $precedence = @{
            # NonPackageBasedFrameworkPrecedence
            '.NETFramework'   = 0
            '.NETCore'        = 1
            'Windows'         = 2
            'WindowsPhoneApp' = 3
            'Silverlight'     = 4
            'WindowsPhone'    = 5
            'WinRT'           = 6
            # PackageBasedFrameworkPrecedence
            '.NETCoreApp'     = 10
            '.NETStandardApp' = 11
            '.NETStandard'    = 12
            '.NETPlatform'    = 13
            'DNXCore'         = 14
            'UAP'             = 15
            'Tizen'           = 16
            # Xamarin / Mono
            'MonoAndroid'     = 20
            'MonoTouch'       = 21
            'MonoMac'         = 22
            'Xamarin.iOS'     = 23
            'Xamarin.Mac'     = 24
            'Xamarin.TVOS'    = 25
            'Xamarin.WatchOS' = 26
            'Xamarin.PlayStation3'  = 27
            'Xamarin.PlayStation4'  = 28
            'Xamarin.PlayStationVita' = 29
            'Xamarin.Xbox360'       = 30
            'Xamarin.XboxOne'       = 31
            # Legacy
            'DNX'             = 40
            'ASP.NET'         = 41
            'ASP.NETCore'     = 42
            '.NETMicroFramework'    = 43
            '.NETnanoFramework'     = 44
            'native'          = 45
        }
        $p = $precedence[$_.Framework]
        if ($null -eq $p) { $p = 50 }
        return $p
    }, { $_.Version } -Descending | Select-Object -First 1)
}

function Resolve-FrameworksUpwards {
    param([NuGetFramework[]]$Frameworks)

    # 移除 Any 框架（除非它是唯一的）
    $hasNonAny = @($Frameworks | Where-Object { -not $_.IsAny() })
    if ($hasNonAny.Count -gt 0) { $Frameworks = $hasNonAny }

    # 按完整框架身份去重（含 Platform/PlatformVersion，防止 net6.0-windows 与 net6.0-android 被误删）
    $sortedFxs = @($Frameworks | Sort-Object -Property Framework, Version, Profile, Platform, PlatformVersion -Unique)
    $seen = @($false) * $sortedFxs.Count

    # 官方算法 ReduceCore: 对于每对 (x, y)，若 isCompat(x, y) 则移除 x
    # ReduceUpwards 传入 isCompat = (x, y) => IsCompatible(y, x)
    # 即：若 y 兼容 x（y 可以代替 x），则移除 x，保留更高级的 y
    for ($i = 0; $i -lt $sortedFxs.Count; $i++) {
        if ($seen[$i]) { continue }
        for ($j = 0; $j -lt $sortedFxs.Count; $j++) {
            if ($i -eq $j -or $seen[$j]) { continue }
            if (Test-NuGetFrameworkCompatibility -Target $sortedFxs[$j] -Candidate $sortedFxs[$i]) {
                $revCompat = Test-NuGetFrameworkCompatibility -Target $sortedFxs[$i] -Candidate $sortedFxs[$j]
                # 双向兼容且同标识符时，丢弃零版本框架（如 win 被 win8 替代）
                if ($revCompat -and $sortedFxs[$i].Framework -eq $sortedFxs[$j].Framework) {
                    $seen[$i] = ($sortedFxs[$i].AllFrameworkVersions() -and -not $sortedFxs[$j].AllFrameworkVersions())
                }
                else {
                    # 平台不同的框架不应互相归约（如 net6.0 和 net6.0-windows）
                    $samePlatformProfile = ($sortedFxs[$i].Platform -eq $sortedFxs[$j].Platform -and
                                            $sortedFxs[$i].PlatformVersion -eq $sortedFxs[$j].PlatformVersion)
                    $seen[$i] = -not $revCompat -and $samePlatformProfile
                }
                if ($seen[$i]) { break }
            }
        }
    }

    $results = [System.Collections.Generic.List[NuGetFramework]]::new()
    for ($i = 0; $i -lt $sortedFxs.Count; $i++) {
        if (-not $seen[$i]) { $results.Add($sortedFxs[$i]) }
    }
    return $results.ToArray()
}

#endregion

#region 工具函数

function Get-NuGetFrameworkKeys {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return $Script:CommonFrameworks.Keys | Sort-Object
}

function Get-NuGetFrameworkInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FrameworkString
    )

    process {
        $Fx = ConvertTo-NuGetFramework -FrameworkString $FrameworkString
        [PSCustomObject]@{
            Framework       = $Fx.Framework
            Version         = $Fx.Version
            Profile         = $Fx.ProfileName
            Platform        = $Fx.Platform
            PlatformVersion = $Fx.PlatformVersion
            ShortFolderName = ConvertTo-NuGetFrameworkShortName -Framework $Fx
            FullName        = ConvertTo-NuGetFrameworkFullName -Framework $Fx
            IsNet5Era       = $Fx.IsNet5Era()
            IsPackageBased  = $Fx.IsPackageBased()
            IsPCL           = $Fx.IsPCL()
            IsSpecific      = $Fx.IsSpecificFramework()
        }
    }
}

#endregion