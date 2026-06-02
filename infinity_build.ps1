class InfinityModule {
    [string]$Name
    [System.Collections.Generic.List[string]]$Requires
    [System.Collections.Generic.List[string]]$Code
    [System.IO.FileInfo]$SourceInfo
    [System.Collections.Generic.Dictionary[int, int]]$LineMappings
}
class InfinityProgramSegment {
    [System.Collections.Generic.List[string]]$Code
    [System.Collections.Generic.Dictionary[int, System.Tuple[string, int]]]$LineMappings
}
class ResourceFileInfo {
    [System.IO.FileInfo]$FileInfo
    [string]$RelativePath
}
class ResourceFileHash {
    [string]$RelativePath
    [string]$Hash256
}
$Script:ModuleBuilders = @{}
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
$Script:ShortNameToIdentifier = @{}
foreach ($kv in $Script:IdentifierShortNames.GetEnumerator()) {
    $Script:ShortNameToIdentifier[$kv.Value] = $kv.Key
}
$Script:SortedShortNames = $Script:IdentifierShortNames.GetEnumerator() |
    Sort-Object { $_.Value.Length } -Descending |
    ForEach-Object { $_ }
$Script:ProfileShortNames = @(
    @{ Framework = '.NETFramework'; ShortProfile = 'Client'; Profile = 'Client' }
    @{ Framework = '.NETFramework'; ShortProfile = 'CF';     Profile = 'CompactFramework' }
    @{ Framework = '.NETFramework'; ShortProfile = 'Full';   Profile = '' }
    @{ Framework = 'Silverlight';   ShortProfile = 'WP';     Profile = 'WindowsPhone' }
    @{ Framework = 'Silverlight';   ShortProfile = 'WP71';   Profile = 'WindowsPhone71' }
)
$Script:EquivalentProfiles = @(
    @{ Framework = '.NETFramework'; Profile = 'Client';         Equivalent = '' }
    @{ Framework = '.NETFramework'; Profile = 'Full';           Equivalent = '' }
    @{ Framework = 'Silverlight';   Profile = 'WindowsPhone71'; Equivalent = 'WindowsPhone' }
    @{ Framework = 'WindowsPhone';  Profile = 'WindowsPhone71'; Equivalent = 'WindowsPhone' }
)
$Script:SubSetFrameworks = @{
    'DNX'             = @('.NETFramework')
    'DNXCore'         = @('.NETPlatform')
    '.NETStandardApp' = @('.NETStandard')
}
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
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('Windows', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('Windows', '8.1.0.0'))
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('WindowsPhoneApp', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0'))
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('UAP', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('UAP', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('.NETCore', '5.0.0.0')) -SupportedMax ([NuGetFramework]::new('.NETCore', '5.0.0.0'))
    Add-OneWayMapping -TargetMin ([NuGetFramework]::new('Windows', '0.0.0.0')) -TargetMax ([NuGetFramework]::new('Windows', '2147483647.0.0.0')) `
        -SupportedMin ([NuGetFramework]::new('WinRT', '0.0.0.0')) -SupportedMax ([NuGetFramework]::new('WinRT', '4.5.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '3.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.6.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '4.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('Tizen', '6.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('UAP', '10.0.15064.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '1.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.6.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '1.1.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.7.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '2.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETCoreApp', '3.0.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))
    New-StandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.3.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-GenerationAndStandardMappingForAllVersions -Identifier 'DNXCore' -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.5.0.0'))
    New-GenerationAndStandardMappingForAllVersions -Identifier 'UAP' -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.4.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '5.0.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.4.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('WindowsPhoneApp', '8.1.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('WindowsPhone', '8.0.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.1.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.0.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.5.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.2.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.1.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.5.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.4.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.3.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.5.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETFramework', '4.6.2.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '4.5.0.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.2.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.1.0.0'))
    New-GenerationAndStandardMapping -Framework ([NuGetFramework]::new('.NETCore', '4.5.1.0')) -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.3.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '1.2.0.0'))
    foreach ($id in @('MonoAndroid', 'MonoMac', 'MonoTouch', 'Xamarin.iOS', 'Xamarin.Mac', 'Xamarin.TVOS', 'Xamarin.WatchOS')) {
        New-GenerationAndStandardMappingForAllVersions -Identifier $id -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.1.0.0'))
    }
    foreach ($id in @('Xamarin.PlayStation3', 'Xamarin.PlayStation4', 'Xamarin.PlayStationVita', 'Xamarin.Xbox360', 'Xamarin.XboxOne')) {
        New-GenerationAndStandardMappingForAllVersions -Identifier $id -NetPlatform ([NuGetFramework]::new('.NETPlatform', '5.6.0.0')) -NetStandard ([NuGetFramework]::new('.NETStandard', '2.0.0.0'))
    }
}
Initialize-CompatibilityMappings
$Script:DeprecatedFrameworkAliases = @{
    '45'  = 'net45'; '4.5' = 'net45'
    '40'  = 'net40'; '4.0' = 'net40'; '4' = 'net40'
    '35'  = 'net35'; '3.5' = 'net35'
    '20'  = 'net20'; '2' = 'net20'; '2.0' = 'net20'
}
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
    $Raw = ConvertFrom-RawParse -InputStr $InputStrLower
    if (-not $Raw) {
        if ($Script:DeprecatedFrameworkAliases.ContainsKey($InputStrLower)) {
            return $Script:CommonFrameworks[$Script:DeprecatedFrameworkAliases[$InputStrLower]]
        }
        return $Script:UnsupportedFramework
    }
    $Identifier = ''
    $Version = [version]'0.0.0.0'
    $ProfileName = ''
    $Matched = $false
    foreach ($entry in $Script:SortedShortNames) {
        if ($Raw.Identifier -eq $entry.Value) { $Identifier = $entry.Key; $Matched = $true; break }
    }
    if (-not $Matched) {
        $LowerId = $Raw.Identifier.ToLowerInvariant()
        if ($Script:IdentifierSynonyms.ContainsKey($LowerId)) { $Identifier = $Script:IdentifierSynonyms[$LowerId] }
        elseif ($Script:ShortNameToIdentifier.ContainsKey($Raw.Identifier)) { $Identifier = $Script:ShortNameToIdentifier[$Raw.Identifier] }
        else {
            return $Script:UnsupportedFramework
        }
    }
    if ($Raw.Version) {
        if ($Raw.Version.Contains('.')) { try { $Version = [version]$Raw.Version } catch { throw "无法解析框架版本号 '$($Raw.Version)'" } }
        else { $Version = ConvertTo-NuGetFrameworkVersion -VersionString $Raw.Version }
    }
    if ($Identifier -eq '.NETFramework' -and $Version.Major -ge 5) { $Identifier = '.NETCoreApp' }
    if ($Identifier -eq '.NETCoreApp' -and $Version.Major -ge 5 -and $Raw.ProfilePart) {
        $PlatformResult = ConvertFrom-PlatformString -PlatformString $Raw.ProfilePart
        return [NuGetFramework]::new($Identifier, $Version, $PlatformResult.Name, $PlatformResult.Version)
    }
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
        foreach ($c in $ProfilePart.ToCharArray()) {
            $x = [int]$c
            if (-not (($x -ge 48 -and $x -le 57) -or ($x -ge 65 -and $x -le 90) -or ($x -ge 97 -and $x -le 122) -or $x -eq 46 -or $x -eq 43 -or $x -eq 45)) {
                return $null
            }
        }
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
    $chars = $InputStr.ToCharArray()
    $nameEnd = 0
    while ($nameEnd -lt $chars.Count -and ($chars[$nameEnd] -match '[a-zA-Z\.]')) { $nameEnd++ }
    if ($nameEnd -eq 0) { throw "无法解析平台字符串：'$PlatformString'" }
    $Name = $InputStr.Substring(0, $nameEnd).ToLowerInvariant()
    $VersionStr = if ($nameEnd -lt $chars.Count) { $InputStr.Substring($nameEnd) } else { '' }
    if ([string]::IsNullOrEmpty($VersionStr)) {
        return @{ Name = $Name; Version = [version]'0.0.0.0' }
    }
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
        $pclFrameworks = Get-PCLFrameworks -Pcl $Framework -IncludeOptional:$false
        if ($pclFrameworks -and $pclFrameworks.Count -gt 0) {
            $sortedNames = @($pclFrameworks | ForEach-Object { ConvertTo-NuGetFrameworkShortName -Framework $_ } | Sort-Object)
            return "portable-$($sortedNames -join '+')"
        }
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
    if ($Ver.Major -le 0 -and $Ver.Minor -le 0 -and $Ver.Build -le 0 -and $Ver.Revision -le 0) { return '' }
    $major = if ($Ver.Major -gt 0) { $Ver.Major } else { 0 }
    $minor = if ($Ver.Minor -gt 0) { $Ver.Minor } else { 0 }
    $build = if ($Ver.Build -gt 0) { $Ver.Build } else { 0 }
    $revision = if ($Ver.Revision -gt 0) { $Ver.Revision } else { 0 }
    if ($revision -gt 0) { $partCount = 4 }
    elseif ($build -gt 0) { $partCount = 3 }
    elseif ($minor -gt 0) { $partCount = 2 }
    else { $partCount = 1 }
    if ($ForPlatform) {
        if ($partCount -lt 2) { $partCount = 2 }
        $result = "$major"
        if ($partCount -gt 1) { $result += ".$minor" }
        if ($partCount -gt 2) { $result += ".$build" }
        if ($partCount -gt 3) { $result += ".$revision" }
        return $result
    }
    $singleDigitFrameworks = @('Windows', 'WindowsPhone', 'Silverlight', 'Tizen')
    $decimalPointFrameworks = @('.NETCoreApp', '.NETStandard', '.NETnanoFramework')
    $isSingleDigit = $singleDigitFrameworks -contains $Framework.Framework
    $isDecimalPoint = $decimalPointFrameworks -contains $Framework.Framework
    if ($partCount -eq 1 -and -not $isSingleDigit) { $partCount = 2 }
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
    if ($TargetFx.IsUnsupported()) { return $false }
    if ($CandidateFx.IsAgnostic()) { return $true }
    if ($CandidateFx.IsUnsupported()) { return $false }
    if ($TargetFx.IsPCL() -or $CandidateFx.IsPCL()) {
        return Test-PCLCompatibility -Target $TargetFx -Candidate $CandidateFx
    }
    $TargetSet = @($TargetFx)
    $TargetSet += Expand-Framework -Framework $TargetFx
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
    if ($Target.IsPCL() -and -not $Candidate.IsPCL()) {
        $targetFrameworks = Get-PCLFrameworks -Pcl $Target -IncludeOptional:$false
        if ($targetFrameworks -and $targetFrameworks.Count -gt 0) {
            foreach ($tf in $targetFrameworks) {
                if (Test-NuGetFrameworkCompatibility -Target $tf -Candidate $Candidate) { return $true }
            }
        }
        return $false
    }
    if (-not $Target.IsPCL() -and $Candidate.IsPCL()) {
        $candidateFrameworks = Get-PCLFrameworks -Pcl $Candidate -IncludeOptional:$true
        if (-not $candidateFrameworks -or $candidateFrameworks.Count -eq 0) { return $false }
        return ($candidateFrameworks | Where-Object { Test-NuGetFrameworkCompatibility -Target $Target -Candidate $_ }).Count -gt 0
    }
    $targetFrameworks = Get-PCLFrameworks -Pcl $Target -IncludeOptional:$false
    $candidateFrameworks = Get-PCLFrameworks -Pcl $Candidate -IncludeOptional:$true
    if (-not $targetFrameworks -or $targetFrameworks.Count -eq 0) { return $false }
    if (-not $candidateFrameworks -or $candidateFrameworks.Count -eq 0) { return $false }
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
    if ($profileStr -match '^Profile(\d+)$') {
        $profileNum = [int]$Matches[1]
        return Get-PCLProfileFrameworks -ProfileNumber $profileNum -IncludeOptional:$IncludeOptional
    }
    $parts = $profileStr -split '\+'
    $result = [System.Collections.Generic.List[NuGetFramework]]::new()
    foreach ($part in $parts) {
        try { $result.Add((ConvertTo-NuGetFramework -FrameworkString $part)) } catch { }
    }
    return $result.ToArray()
}
function Get-PCLProfileFrameworks {
    param([int]$ProfileNumber, [bool]$IncludeOptional)
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
    if ($isNet6Era -and $Target.HasPlatform() -and $Target.Framework -ne $Candidate.Framework) {
        if ($Candidate.Framework -eq 'MonoAndroid') { return ($Target.Platform -eq 'android') }
        if ($Candidate.Framework -eq 'Tizen') { return ($Target.Platform -eq 'tizen') }
        return $false
    }
    if ($Target.Framework -ne $Candidate.Framework) { return $false }
    $versionOk = ($Candidate.Version -eq [version]'0.0.0.0' -or $Target.Version -ge $Candidate.Version)
    $profileOk = ($Target.ProfileName -eq $Candidate.ProfileName)
    if (-not $versionOk -or -not $profileOk) { return $false }
    if ($Target.IsNet5Era() -and $Candidate.HasPlatform()) {
        if ($Target.Version.Major -ge 10 -and
            $Target.Platform -eq 'windows' -and $Target.PlatformVersion.Major -ge 10 -and
            $Candidate.PlatformVersion.Major -ge 10 -and
            $Target.PlatformVersion.Revision -ne $Candidate.PlatformVersion.Revision) {
            return $false
        }
        if ($Target.Platform -ne $Candidate.Platform) { return $false }
        return ($Target.PlatformVersion -ge $Candidate.PlatformVersion)
    }
    if ($Target.IsNet5Era() -and -not $Target.HasPlatform() -and $Candidate.HasPlatform()) { return $false }
    return $true
}
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
        foreach ($equiv in $Script:EquivalentFrameworksFull) {
            if ($equiv.A.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.B
                if ($seen.Add($key)) { $results.Add($equiv.B); $toExpand.Push($equiv.B) }
            }
            if ($equiv.B.Equals($current)) {
                $key = Get-FrameworkUniqueKey $equiv.A
                if ($seen.Add($key)) { $results.Add($equiv.A); $toExpand.Push($equiv.A) }
            }
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
    if ($Framework.IsPCL()) {
        $profileNum = -1
        if ($Framework.ProfileName -match '^Profile(\d+)$') { $profileNum = [int]$Matches[1] }
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
    $isNet6Era = $TargetFx.IsNet5Era() -and $TargetFx.Version.Major -ge 6
    if ($Reduced.Count -gt 1 -and ($Reduced | Where-Object { $_.Framework -eq $TargetFx.Framework }).Count -gt 0) {
        $Reduced = @($Reduced | Where-Object {
            if ($isNet6Era -and $TargetFx.HasPlatform() -and ($_.Framework -eq 'MonoAndroid' -or $_.Framework -eq 'Tizen')) { return $true }
            return ($_.Framework -eq $TargetFx.Framework)
        })
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }
    $withPcl = @($Reduced | Where-Object { $_.IsPCL() })
    $withoutPcl = @($Reduced | Where-Object { -not $_.IsPCL() })
    if ($withoutPcl.Count -gt 0 -and $withPcl.Count -gt 0) { $Reduced = $withoutPcl }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }
    if (-not $TargetFx.IsPackageBased()) {
        $nonPackage = @($Reduced | Where-Object { -not $_.IsPackageBased() })
        if ($nonPackage.Count -gt 0) { $Reduced = $nonPackage }
    }
    if ($Reduced.Count -eq 1) { return $Reduced[0] }
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
    return ($Reduced | Sort-Object -Property {
        $precedence = @{
            '.NETFramework'   = 0
            '.NETCore'        = 1
            'Windows'         = 2
            'WindowsPhoneApp' = 3
            'Silverlight'     = 4
            'WindowsPhone'    = 5
            'WinRT'           = 6
            '.NETCoreApp'     = 10
            '.NETStandardApp' = 11
            '.NETStandard'    = 12
            '.NETPlatform'    = 13
            'DNXCore'         = 14
            'UAP'             = 15
            'Tizen'           = 16
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
    $hasNonAny = @($Frameworks | Where-Object { -not $_.IsAny() })
    if ($hasNonAny.Count -gt 0) { $Frameworks = $hasNonAny }
    $sortedFxs = @($Frameworks | Sort-Object -Property Framework, Version, Profile, Platform, PlatformVersion -Unique)
    $seen = @($false) * $sortedFxs.Count
    for ($i = 0; $i -lt $sortedFxs.Count; $i++) {
        if ($seen[$i]) { continue }
        for ($j = 0; $j -lt $sortedFxs.Count; $j++) {
            if ($i -eq $j -or $seen[$j]) { continue }
            if (Test-NuGetFrameworkCompatibility -Target $sortedFxs[$j] -Candidate $sortedFxs[$i]) {
                $revCompat = Test-NuGetFrameworkCompatibility -Target $sortedFxs[$i] -Candidate $sortedFxs[$j]
                if ($revCompat -and $sortedFxs[$i].Framework -eq $sortedFxs[$j].Framework) {
                    $seen[$i] = ($sortedFxs[$i].AllFrameworkVersions() -and -not $sortedFxs[$j].AllFrameworkVersions())
                }
                else {
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
enum VersionComparison {
    Default               = 0
    Version               = 1
    VersionRelease        = 2
    VersionReleaseMetadata = 3
}
enum NuGetVersionFloatBehavior {
    None
    Prerelease
    Revision
    Patch
    Minor
    Major
    AbsoluteLatest
    PrereleaseRevision
    PrereleasePatch
    PrereleaseMinor
    PrereleaseMajor
}
class NuGetVersion {
    [string]   $OriginalVersion
    [string]   $NormalizedVersion
    [int]      $Major
    [int]      $Minor
    [int]      $Patch
    [int]      $Revision
    [int[]]    $CoreSegments
    [string]   $PreRelease
    [string[]] $ReleaseLabels
    [string]   $BuildMetadata
    NuGetVersion([string] $VersionString) {
        $NugetVersionRegex = [regex]::new(
            '^(?:v)?(?<CoreSegments>\d+(?:\.\d+){0,3})(?:-(?<Prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<Buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
        )
        $CleanVersion = $VersionString.Trim() -replace '\s+', ''
        $RegexMatch = $NugetVersionRegex.Match($CleanVersion)
        if (-not $RegexMatch.Success) {
            throw "无效的 NuGet 版本号 '$CleanVersion'：不符合 NuGet 官方版本规范（参考：https://learn.microsoft.com/en-us/nuget/concepts/package-versioning）"
        }
        $this.OriginalVersion = $CleanVersion
        $Segments = $RegexMatch.Groups['CoreSegments'].Value -split '\.' | ForEach-Object {
            if ($_ -eq '0') { 0 } else { [int]($_ -replace '^0+', '') }
        }
        while ($Segments.Count -lt 4) {
            $Segments += 0
        }
        $this.CoreSegments = $Segments
        $this.Major   = $Segments[0]
        $this.Minor   = $Segments[1]
        $this.Patch   = $Segments[2]
        $this.Revision = $Segments[3]
        $NormalizedCore = $Segments[0..2] -join '.'
        if ($Segments[3] -ne 0) {
            $NormalizedCore = $Segments -join '.'
        }
        $Normalized = $NormalizedCore
        $PreReleaseGroup = $RegexMatch.Groups['Prerelease']
        $BuildMetadataGroup = $RegexMatch.Groups['Buildmetadata']
        if ($PreReleaseGroup.Success -and $PreReleaseGroup.Value) {
            $Normalized += "-$($PreReleaseGroup.Value)"
        }
        $this.NormalizedVersion = $Normalized
        $this.PreRelease    = if ($PreReleaseGroup.Success)    { $PreReleaseGroup.Value    } else { $null }
        $this.BuildMetadata = if ($BuildMetadataGroup.Success) { $BuildMetadataGroup.Value } else { $null }
        if ($this.PreRelease) {
            $this.ReleaseLabels = $this.PreRelease -split '\.'
        }
        else {
            $this.ReleaseLabels = @()
        }
    }
    [string] ToString() {
        return $this.NormalizedVersion
    }
    [string] ToFullString() {
        $result = $this.NormalizedVersion
        if ($this.HasMetadata()) {
            $result += "+$($this.BuildMetadata)"
        }
        return $result
    }
    [bool] IsPrerelease() {
        return $null -ne $this.PreRelease -and $this.PreRelease.Length -gt 0
    }
    [bool] HasMetadata() {
        return $null -ne $this.BuildMetadata -and $this.BuildMetadata.Length -gt 0
    }
    [bool] IsLegacyVersion() {
        return $this.Revision -gt 0
    }
    [bool] IsSemVer2() {
        return ($this.ReleaseLabels.Count -gt 1) -or ($this.HasMetadata())
    }
}
class FloatRange {
    [NuGetVersionFloatBehavior] $FloatBehavior
    [NuGetVersion]             $MinVersion
    [string]                   $OriginalReleasePrefix
    [bool]                     $IncludePrerelease
    FloatRange([string] $FloatVersionString) {
        $Clean = $FloatVersionString.Trim()
        $this.OriginalReleasePrefix = $null
        $this.IncludePrerelease = $false
        if ($Clean -eq '*-*') {
            $this.FloatBehavior = [NuGetVersionFloatBehavior]::AbsoluteLatest
            $this.MinVersion = [NuGetVersion]::new('0.0.0-0')
            $this.IncludePrerelease = $true
            $this.OriginalReleasePrefix = ''
            return
        }
        if ($Clean -eq '*') {
            $this.FloatBehavior = [NuGetVersionFloatBehavior]::Major
            $this.MinVersion = [NuGetVersion]::new('0.0.0')
            $this.OriginalReleasePrefix = $null
            return
        }
        $DashIndex = $Clean.IndexOf('-')
        $VersionPart = $Clean
        $PreReleasePart = $null
        if ($DashIndex -ge 0) {
            $VersionPart = $Clean.Substring(0, $DashIndex)
            $PreReleasePart = $Clean.Substring($DashIndex + 1)
        }
        $Segments = $VersionPart -split '\.'
        $StarIndex = -1
        for ($i = 0; $i -lt $Segments.Count; $i++) {
            if ($Segments[$i] -eq '*') { $StarIndex = $i; break }
        }
        $MinVersionString = ($Segments | ForEach-Object { if ($_ -eq '*') { '0' } else { $_ } }) -join '.'
        $MinSegments = $MinVersionString -split '\.'
        while ($MinSegments.Count -lt 3) { $MinSegments += '0' }
        $MinVersionString = $MinSegments -join '.'
        if ($PreReleasePart) {
            $this.IncludePrerelease = $true
            $ReleasePrefix = if ($PreReleasePart.EndsWith('*')) {
                $PreReleasePart.Substring(0, $PreReleasePart.Length - 1)
            } else {
                $PreReleasePart
            }
            $this.OriginalReleasePrefix = $ReleasePrefix
            $ReleasePartForVersion = if ($PreReleasePart -eq '*') {
                '0'
            } else {
                $PreReleasePart -replace '\*', '0'
            }
            if ($ReleasePartForVersion.Length -eq 0 -or $ReleasePartForVersion.EndsWith('.')) {
                $ReleasePartForVersion += '0'
            }
            $MinVersionString += "-$ReleasePartForVersion"
            if ($PreReleasePart -eq '*') {
                if ($Segments.Count -eq 4 -and $StarIndex -eq 3) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseRevision
                }
                elseif ($Segments.Count -eq 3 -and $StarIndex -eq 2) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleasePatch
                }
                elseif ($Segments.Count -eq 2 -and $StarIndex -eq 1) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMinor
                }
                elseif ($Segments.Count -eq 1 -and $StarIndex -eq 0) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMajor
                }
                else {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::Prerelease
                }
            }
            else {
                if ($PreReleasePart.Contains('*')) {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::PrereleaseMajor
                }
                else {
                    $this.FloatBehavior = [NuGetVersionFloatBehavior]::Prerelease
                }
            }
        }
        else {
            if ($Segments.Count -eq 4 -and $StarIndex -eq 3) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Revision
            }
            elseif ($Segments.Count -eq 3 -and $StarIndex -eq 2) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Patch
            }
            elseif ($Segments.Count -eq 2 -and $StarIndex -eq 1) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Minor
            }
            elseif ($Segments.Count -eq 1 -and $StarIndex -eq 0) {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::Major
            }
            else {
                $this.FloatBehavior = [NuGetVersionFloatBehavior]::None
            }
        }
        $this.MinVersion = [NuGetVersion]::new($MinVersionString)
    }
    [bool] Satisfies([NuGetVersion] $version) {
        if ($null -eq $version) { return $false }
        $behavior = $this.FloatBehavior
        if ($behavior -eq [NuGetVersionFloatBehavior]::AbsoluteLatest) {
            return $true
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::Major -and -not $version.IsPrerelease()) {
            return $true
        }
        if ($this.IncludePrerelease) {
            $prefix = $this.OriginalReleasePrefix
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseRevision) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       $this.MinVersion.Patch -eq $version.Patch -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleasePatch) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMinor) {
                return $this.MinVersion.Major -eq $version.Major -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMajor) {
                return (($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                       (-not $version.IsPrerelease())
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Prerelease) {
                $verCmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MinVersion -ComparisonMode ([VersionComparison]::Version)
                return $verCmp -eq 0 -and
                       ((($version.IsPrerelease()) -and ($prefix -eq '' -or [System.String]::new($version.PreRelease).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) -or
                        (-not $version.IsPrerelease()))
            }
        }
        else {
            if ($behavior -eq [NuGetVersionFloatBehavior]::Revision) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       $this.MinVersion.Patch -eq $version.Patch -and
                       -not $version.IsPrerelease()
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Patch) {
                return $this.MinVersion.Major -eq $version.Major -and
                       $this.MinVersion.Minor -eq $version.Minor -and
                       -not $version.IsPrerelease()
            }
            if ($behavior -eq [NuGetVersionFloatBehavior]::Minor) {
                return $this.MinVersion.Major -eq $version.Major -and
                       -not $version.IsPrerelease()
            }
        }
        return $false
    }
    [string] ToString() {
        $min = $this.MinVersion
        $behavior = $this.FloatBehavior
        if ($behavior -eq [NuGetVersionFloatBehavior]::Major) {
            return '*'
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::AbsoluteLatest) {
            return '*-*'
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::Minor) {
            return "$($min.Major).*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::Patch) {
            return "$($min.Major).$($min.Minor).*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::Revision) {
            return "$($min.Major).$($min.Minor).$($min.Patch).*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::Prerelease) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).$($min.Patch)-$prefix*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseRevision) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).$($min.Patch).*-$prefix*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleasePatch) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).$($min.Minor).*-$prefix*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMinor) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "$($min.Major).*-$prefix*"
        }
        if ($behavior -eq [NuGetVersionFloatBehavior]::PrereleaseMajor) {
            $prefix = if ($null -ne $this.OriginalReleasePrefix) { $this.OriginalReleasePrefix } else { '' }
            return "*-$prefix*"
        }
        return $min.NormalizedVersion
    }
}
class VersionRange {
    [NuGetVersion] $MinVersion
    [bool]         $IsMinInclusive
    [NuGetVersion] $MaxVersion
    [bool]         $IsMaxInclusive
    [FloatRange]   $FloatRange
    VersionRange() {
        $this.IsMinInclusive = $true
        $this.IsMaxInclusive = $false
    }
    VersionRange([string] $RangeString) {
        $this.IsMinInclusive = $true
        $this.IsMaxInclusive = $false
        $Clean = $RangeString.Trim()
        if (-not $Clean) {
            throw "版本范围字符串不能为空"
        }
        if ($Clean -eq '*' -or $Clean -eq '*-*' -or $Clean.Contains('*')) {
            $this.FloatRange = [FloatRange]::new($Clean)
            $this.MinVersion = $this.FloatRange.MinVersion
            $this.IsMinInclusive = $true
            $this.MaxVersion = $null
            return
        }
        if ($Clean[0] -eq '(' -or $Clean[0] -eq '[') {
            $LastChar = $Clean[$Clean.Length - 1]
            if ($LastChar -ne ')' -and $LastChar -ne ']') {
                throw "无效的版本范围 '$Clean'：缺少闭合括号"
            }
            $this.IsMinInclusive = ($Clean[0] -eq '[')
            $this.IsMaxInclusive = ($LastChar -eq ']')
            $Inner = $Clean.Substring(1, $Clean.Length - 2)
            $Parts = $Inner -split ','
            if ($Parts.Count -gt 2) {
                throw "无效的版本范围 '$Clean'：逗号分隔的部分过多"
            }
            if ($Parts.Count -eq 1 -and -not ($this.IsMinInclusive -and $this.IsMaxInclusive)) {
                throw "无效的版本范围 '$Clean'：单版本区间两端必须都是闭区间（如 [1.0]），不支持 (1.0]、[1.0)、(1.0)"
            }
            $MinStr = $Parts[0].Trim()
            $MaxStr = if ($Parts.Count -gt 1) { $Parts[1].Trim() } else { '' }
            if ($MinStr) {
                if ($MinStr.Contains('*')) {
                    $this.FloatRange = [FloatRange]::new($MinStr)
                    $this.MinVersion = $this.FloatRange.MinVersion
                }
                else {
                    $this.MinVersion = [NuGetVersion]::new($MinStr)
                }
            }
            if ($MaxStr) {
                $this.MaxVersion = [NuGetVersion]::new($MaxStr)
            }
            if ($this.MinVersion -and $this.MaxVersion) {
                $minMaxCmp = Compare-NugetVersionInternal -VersionA $this.MinVersion -VersionB $this.MaxVersion -ComparisonMode ([VersionComparison]::VersionRelease)
                if ($minMaxCmp -gt 0) {
                    throw "无效的版本范围 '$Clean'：最小版本大于最大版本"
                }
                if ($minMaxCmp -eq 0 -and ($this.IsMinInclusive -xor $this.IsMaxInclusive)) {
                    throw "无效的版本范围 '$Clean'：最小版本等于最大版本时，两端区间开闭必须一致（如 [1.0, 1.0) 非法）"
                }
            }
        }
        else {
            if ($Clean.Contains('*')) {
                $this.FloatRange = [FloatRange]::new($Clean)
                $this.MinVersion = $this.FloatRange.MinVersion
            }
            else {
                $this.MinVersion = [NuGetVersion]::new($Clean)
            }
            $this.IsMinInclusive = $true
        }
    }
    [bool] HasLowerBound() {
        return $null -ne $this.MinVersion
    }
    [bool] HasUpperBound() {
        return $null -ne $this.MaxVersion
    }
    [bool] HasLowerAndUpperBounds() {
        return $this.HasLowerBound() -and $this.HasUpperBound()
    }
    [bool] IsFloating() {
        return $null -ne $this.FloatRange -and
               $this.FloatRange.FloatBehavior -ne [NuGetVersionFloatBehavior]::None
    }
    [bool] HasPrereleaseBounds() {
        return ($this.HasLowerBound() -and $this.MinVersion.IsPrerelease()) -or
               ($this.HasUpperBound() -and $this.MaxVersion.IsPrerelease())
    }
    [bool] Satisfies([NuGetVersion] $version) {
        return $this.Satisfies($version, [VersionComparison]::VersionRelease)
    }
    [bool] Satisfies([NuGetVersion] $version, [VersionComparison] $versionComparison) {
        if ($null -eq $version) { return $false }
        if ($this.HasLowerBound()) {
            $cmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MinVersion -ComparisonMode $versionComparison
            if ($this.IsMinInclusive) {
                if ($cmp -lt 0) { return $false }
            }
            else {
                if ($cmp -le 0) { return $false }
            }
        }
        if ($this.HasUpperBound()) {
            $cmp = Compare-NugetVersionInternal -VersionA $version -VersionB $this.MaxVersion -ComparisonMode $versionComparison
            if ($this.IsMaxInclusive) {
                if ($cmp -gt 0) { return $false }
            }
            else {
                if ($cmp -ge 0) { return $false }
            }
        }
        return $true
    }
    [string] ToString() {
        return $this.ToNormalizedString()
    }
    [bool] IsBetter([NuGetVersion] $current, [NuGetVersion] $considering) {
        if ($null -eq $considering) { return $false }
        if ($null -ne $current -and [object]::ReferenceEquals($current, $considering)) { return $false }
        if (-not $this.HasPrereleaseBounds() -and $considering.IsPrerelease()) {
            $floatBehavior = if ($this.FloatRange) { $this.FloatRange.FloatBehavior } else { [NuGetVersionFloatBehavior]::None }
            $allowPrerelease = @(
                [NuGetVersionFloatBehavior]::Prerelease,
                [NuGetVersionFloatBehavior]::PrereleaseMajor,
                [NuGetVersionFloatBehavior]::PrereleaseMinor,
                [NuGetVersionFloatBehavior]::PrereleasePatch,
                [NuGetVersionFloatBehavior]::PrereleaseRevision,
                [NuGetVersionFloatBehavior]::AbsoluteLatest
            ) -contains $floatBehavior
            if (-not $allowPrerelease) {
                return $false
            }
        }
        if (-not $this.Satisfies($considering)) {
            return $false
        }
        if ($null -eq $current) {
            return $true
        }
        if ($this.IsFloating()) {
            $curInRange = $this.FloatRange.Satisfies($current)
            $conInRange = $this.FloatRange.Satisfies($considering)
            if ($curInRange -and -not $conInRange) {
                return $false
            }
            elseif ($conInRange -and -not $curInRange) {
                return $true
            }
            elseif ($curInRange -and $conInRange) {
                $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                return $cmp -lt 0
            }
            else {
                $curBelowMin = (Compare-NugetVersionInternal -VersionA $current -VersionB $this.FloatRange.MinVersion -ComparisonMode ([VersionComparison]::VersionRelease)) -lt 0
                $conBelowMin = (Compare-NugetVersionInternal -VersionA $considering -VersionB $this.FloatRange.MinVersion -ComparisonMode ([VersionComparison]::VersionRelease)) -lt 0
                if ($curBelowMin -and -not $conBelowMin) {
                    return $true
                }
                elseif (-not $curBelowMin -and $conBelowMin) {
                    return $false
                }
                elseif (-not $curBelowMin -and -not $conBelowMin) {
                    $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                    return $cmp -gt 0
                }
                else {
                    $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
                    return $cmp -lt 0
                }
            }
        }
        $cmp = Compare-NugetVersionInternal -VersionA $current -VersionB $considering -ComparisonMode ([VersionComparison]::VersionRelease)
        return $cmp -gt 0
    }
    [string] ToNormalizedString() {
        if ($this.IsFloating()) {
            return $this.FloatRange.ToString()
        }
        if (-not $this.HasLowerBound() -and -not $this.HasUpperBound()) {
            return '(, )'
        }
        $leftBracket  = if ($this.IsMinInclusive) { '[' } else { '(' }
        $rightBracket = if ($this.IsMaxInclusive) { ']' } else { ')' }
        $minStr = if ($this.HasLowerBound()) { $this.MinVersion.NormalizedVersion } else { '' }
        $maxStr = if ($this.HasUpperBound()) { $this.MaxVersion.NormalizedVersion } else { '' }
        return "$leftBracket$minStr, $maxStr$rightBracket"
    }
    [string] ToLegacyString() {
        if ($this.IsFloating()) {
            return $this.FloatRange.ToString()
        }
        return $this.ToNormalizedString()
    }
}
function ConvertTo-NuGetVersion {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VersionString
    )
    process {
        return [NuGetVersion]::new($VersionString)
    }
}
function Compare-NugetVersion {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionA,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionB,
        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::Default
    )
    return Compare-NugetVersionInternal -VersionA $VersionA -VersionB $VersionB -ComparisonMode $ComparisonMode
}
function Compare-NugetVersionInternal {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionA,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$VersionB,
        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::Default
    )
    if ($VersionA.Major -gt $VersionB.Major) { return 1 }
    if ($VersionA.Major -lt $VersionB.Major) { return -1 }
    if ($VersionA.Minor -gt $VersionB.Minor) { return 1 }
    if ($VersionA.Minor -lt $VersionB.Minor) { return -1 }
    if ($VersionA.Patch -gt $VersionB.Patch) { return 1 }
    if ($VersionA.Patch -lt $VersionB.Patch) { return -1 }
    if ($VersionA.Revision -gt $VersionB.Revision) { return 1 }
    if ($VersionA.Revision -lt $VersionB.Revision) { return -1 }
    if ($ComparisonMode -eq [VersionComparison]::Version) {
        return 0
    }
    $PreA = $VersionA.PreRelease
    $PreB = $VersionB.PreRelease
    if (-not $PreA -and -not $PreB) {
        if ($ComparisonMode -eq [VersionComparison]::VersionReleaseMetadata) {
            $MetaA = $VersionA.BuildMetadata
            $MetaB = $VersionB.BuildMetadata
            if (-not $MetaA -and -not $MetaB) { return 0 }
            if (-not $MetaA -and $MetaB) { return -1 }
            if ($MetaA -and -not $MetaB) { return 1 }
            return [string]::Compare($MetaA, $MetaB, [System.StringComparison]::OrdinalIgnoreCase)
        }
        return 0
    }
    if (-not $PreA -and $PreB) {
        return 1
    }
    if ($PreA -and -not $PreB) {
        return -1
    }
    $PreSegmentsA = $PreA -split '\.'
    $PreSegmentsB = $PreB -split '\.'
    $MaxLen = [Math]::Max($PreSegmentsA.Count, $PreSegmentsB.Count)
    for ($i = 0; $i -lt $MaxLen; $i++) {
        $SegA = if ($i -lt $PreSegmentsA.Count) { $PreSegmentsA[$i] } else { $null }
        $SegB = if ($i -lt $PreSegmentsB.Count) { $PreSegmentsB[$i] } else { $null }
        if ($null -eq $SegA -and $null -ne $SegB) {
            return -1
        }
        if ($null -ne $SegA -and $null -eq $SegB) {
            return 1
        }
        $IsNumA = $SegA -match '^\d+$'
        $IsNumB = $SegB -match '^\d+$'
        if ($IsNumA -and $IsNumB) {
            $IntA = [int]$SegA
            $IntB = [int]$SegB
            if ($IntA -gt $IntB) { return 1 }
            if ($IntA -lt $IntB) { return -1 }
        }
        elseif ($IsNumA -and -not $IsNumB) {
            return -1
        }
        elseif (-not $IsNumA -and $IsNumB) {
            return 1
        }
        else {
            $Cmp = [string]::Compare($SegA, $SegB, [System.StringComparison]::OrdinalIgnoreCase)
            if ($Cmp -gt 0) { return 1 }
            if ($Cmp -lt 0) { return -1 }
        }
    }
    if ($ComparisonMode -eq [VersionComparison]::VersionReleaseMetadata) {
        $MetaA = $VersionA.BuildMetadata
        $MetaB = $VersionB.BuildMetadata
        if (-not $MetaA -and -not $MetaB) { return 0 }
        if (-not $MetaA -and $MetaB) { return -1 }
        if ($MetaA -and -not $MetaB) { return 1 }
        return [string]::Compare($MetaA, $MetaB, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return 0
}
function Test-NuGetVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VersionString,
        [Parameter(Mandatory = $false)]
        [ref]$Version
    )
    try {
        $result = [NuGetVersion]::new($VersionString)
        if ($Version) {
            $Version.Value = $result
        }
        return $true
    }
    catch {
        if ($Version) {
            $Version.Value = $null
        }
        return $false
    }
}
function ConvertTo-VersionRange {
    [CmdletBinding()]
    [OutputType([VersionRange])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RangeString
    )
    process {
        return [VersionRange]::new($RangeString)
    }
}
function Test-NuGetVersionInRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion]$Version,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [VersionRange]$VersionRange,
        [Parameter(Mandatory = $false)]
        [VersionComparison]$ComparisonMode = [VersionComparison]::VersionRelease
    )
    return $VersionRange.Satisfies($Version, $ComparisonMode)
}
function Find-BestNuGetVersionMatch {
    [CmdletBinding()]
    [OutputType([NuGetVersion])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NuGetVersion[]]$Versions,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [VersionRange]$VersionRange
    )
    $bestMatch = $null
    foreach ($v in $Versions) {
        if ($VersionRange.IsBetter($bestMatch, $v)) {
            $bestMatch = $v
        }
    }
    return $bestMatch
}
enum LogType {
    LogErr = 0
    LogWarn = 1
    LogInfo = 2
    LogDebug = 3
}
class LogColorTable {
    [string]$ErrorColor
    [string]$WarnColor
    [string]$InfoColor
    [string]$DebugColor
    LogColorTable([string]$Error_C, [string]$Warn, [string]$Info, [string]$Debug) {
        $this.ErrorColor = $Error_C
        $this.WarnColor = $Warn
        $this.InfoColor = $Info
        $this.DebugColor = $Debug
    }
    [string]GetColor([LogType]$Type) {
        switch ($Type) {
            ([LogType]::LogErr)  { return $this.ErrorColor }
            ([LogType]::LogWarn) { return $this.WarnColor }
            ([LogType]::LogInfo) { return $this.InfoColor }
            ([LogType]::LogDebug) { return $this.DebugColor }
            default              {  }
        }
        return ""
    }
    static [LogColorTable] GetDefault() {
        return [LogColorTable]::new("91", "93", "96", "94")
    }
    static [LogColorTable] GetDark() {
        return [LogColorTable]::new("91", "93", "97", "90")
    }
    static [LogColorTable] GetLight() {
        return [LogColorTable]::new("31", "33", "30", "37")
    }
    static [LogColorTable] GetHighContrast() {
        return [LogColorTable]::new("97;41", "30;43", "97;44", "37;40")
    }
}
class LogServer {
    [LogType]$LogLevel
    [string]$AppName = $null
    [bool]$EnableColors = $true
    [LogColorTable]$ColorTable = [LogColorTable]::GetDefault()
    LogServer([LogType]$Level) {
        $this.LogLevel = $Level
    }
    LogServer([LogType]$Level, [string]$AppName) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
    }
    LogServer([LogType]$Level, [string]$AppName, [LogColorTable]$ColorTable) {
        $this.LogLevel = $Level
        $this.AppName = $AppName
        $this.ColorTable = $ColorTable
    }
    LogServer([LogType]$Level, [LogColorTable]$ColorTable) {
        $this.LogLevel = $Level
        $this.ColorTable = $ColorTable
    }
    [string]FormatMessage([LogType]$Type, [string]$Text) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelName = switch ($Type) {
            ([LogType]::LogErr) { "ERROR" }
            ([LogType]::LogWarn) { "WARN-" }
            ([LogType]::LogInfo) { "INFO-" }
            ([LogType]::LogDebug) { "DEBUG" }
        }
        if ($this.AppName) {
            return "[$timestamp][$($this.AppName)][$levelName]$Text"
        }
        else {
            return "[$timestamp][$levelName]$Text"
        }
    }
    [void]Write([LogType]$Type, [string]$Text) {
        if ([int]$Type -gt [int]$this.LogLevel) {
            return
        }
        $message = $this.FormatMessage($Type, $Text)
        if ($this.EnableColors) {
            $this.WriteColored($Type, $message)
        }
        else {
            Write-Host $message
        }
    }
    hidden [void]WriteColored([LogType]$Type, [string]$Message) {
        $colorCode = $this.ColorTable.GetColor($Type)
        if ([string]::IsNullOrEmpty($colorCode)) {
            Write-Host $Message
        }
        else {
            Write-Host "`u{001b}[${colorCode}m$Message`u{001b}[0m"
        }
    }
}
class LogClient {
    [LogServer]$Server
    [System.Collections.Generic.Stack[string]]$Context = @()
    LogClient([LogServer]$Server) {
        $this.Server = $Server
    }
    LogClient([LogType]$Level) {
        $this.Server = [LogServer]::new($Level)
    }
    LogClient([LogType]$Level, [LogColorTable]$ColorTable) {
        $this.Server = [LogServer]::new($Level, $ColorTable)
    }
    [object]Scope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
        try {
            $Result = & $ScriptBlock
            $this.Info("完成: $ScopeName")
            return $Result
        }
        catch {
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }
    [object]MeasureScope([string]$ScopeName, [scriptblock]$ScriptBlock) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $Result = & $ScriptBlock
            $Stopwatch.Stop()
            $this.Info("完成: $ScopeName")
            $this.Info("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            return $Result
        }
        catch {
            $Stopwatch.Stop()
            $this.Error("$ScopeName 执行出错: $($_.Exception.Message)")
            $this.Warn("耗时: $($Stopwatch.Elapsed.TotalSeconds.ToString('F3'))s")
            throw
        }
        finally {
            [void]$this.Context.Pop()
        }
    }
    [void]StartScope([string]$ScopeName) {
        [void]$this.Context.Push($ScopeName)
        $this.Info("开始: $ScopeName")
    }
    [void]EndScope() {
        $this.Info("完成: $($this.Context.Pop())")
    }
    [void]Error([string]$Message) {
        $this.WriteInternal([LogType]::LogErr, $Message)
    }
    [void]Warn([string]$Message) {
        $this.WriteInternal([LogType]::LogWarn, $Message)
    }
    [void]Info([string]$Message) {
        $this.WriteInternal([LogType]::LogInfo, $Message)
    }
    [void]Debug([string]$Message) {
        $this.WriteInternal([LogType]::LogDebug, $Message)
    }
    hidden [void]WriteInternal([LogType]$Type, [string]$Message) {
        $ContextPrefix = $this.BuildContextPrefix()
        $Lines = $Message -split "\r?\n"
        foreach ($Line in $Lines) {
            $this.Server.Write($Type, "$ContextPrefix $Line")
        }
    }
    hidden [string]BuildContextPrefix() {
        if ($this.Context.Count -ne 0) {
            $ContextArray = $this.Context.ToArray()
            [array]::Reverse($ContextArray)
            return "[$($ContextArray -join '.')]"
        }
        return ""
    }
}
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
function Get-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileInfo[]]$ResourceFiles
    )
    $HashList = [System.Collections.Generic.List[ResourceFileHash]]::new()
    $Script:BuildLogger.Info("计算资源文件快照 ($($ResourceFiles.Count) 个文件)")
    foreach ($ResourceFile in $ResourceFiles) {
        try {
            if (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf) {
                $FileHash = Get-FileHash -Path $ResourceFile.FileInfo -Algorithm SHA256 -ErrorAction Stop
                [void]$HashList.Add([ResourceFileHash]@{
                        RelativePath = $ResourceFile.RelativePath
                        Hash256      = $FileHash.Hash
                    })
            }
            else {
                $Script:BuildLogger.Warn("文件不存在，跳过: $($ResourceFile.FileInfo)")
            }
        }
        catch {
            $Script:BuildLogger.Warn("计算文件哈希失败 '$($ResourceFile.FileInfo)': $($_.Exception.Message)")
        }
    }
    $Script:BuildLogger.Info("资源快照计算完成: $($HashList.Count) 个文件")
    return $HashList.ToArray()
}
function Compare-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$NewSnapshot,
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$OldSnapshot
    )
    $Script:BuildLogger.Debug("比较资源快照: 新 $($NewSnapshot.Count) 个文件, 旧 $($OldSnapshot.Count) 个文件")
    if ($NewSnapshot.Count -ne $OldSnapshot.Count) {
        $Script:BuildLogger.Info("快照文件数量不同: 新 $($NewSnapshot.Count) vs 旧 $($OldSnapshot.Count)")
    }
    $OldFileHashTable = @{}
    foreach ($Item in $OldSnapshot) {
        $OldFileHashTable[$Item.RelativePath] = $Item.Hash256
    }
    $IsSame = $true
    foreach ($Item in $NewSnapshot) {
        $Path = $Item.RelativePath
        if (-not $OldFileHashTable.ContainsKey($Path)) {
            $Script:BuildLogger.Info("新增文件: $Path")
            $IsSame = $false
            continue
        }
        if ($OldFileHashTable[$Path] -ne $Item.Hash256) {
            $Script:BuildLogger.Info("文件哈希变化: $Path")
            $IsSame = $false
        }
        [void]$OldFileHashTable.Remove($Path)
    }
    foreach ($Path in $OldFileHashTable.Keys) {
        $Script:BuildLogger.Info("文件被删除：$Path")
        $IsSame = $false
    }
    $Script:BuildLogger.Debug("资源快照比较结果: $($IsSame ? '相同' : '不同')")
    return $IsSame
}
function Write-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileHash[]]$Snapshot,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        $Snapshot | ForEach-Object {
            @{
                RelativePath = $_.RelativePath
                Hash256      = $_.Hash256
            }
        } | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 -NoNewLine
        $Script:BuildLogger.Info("资源快照已保存到: $Path ($($Snapshot.Count) 个文件)")
    }
    catch {
        $Script:BuildLogger.Error("保存资源快照失败: $($_.Exception.Message)")
        throw
    }
}
function Read-ResourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            $Script:BuildLogger.Warn("未找到资源快照: $Path")
            return $null
        }
        $SnapshotData = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $Snapshot = @()
        foreach ($Item in $SnapshotData) {
            $Snapshot += [ResourceFileHash]@{
                RelativePath = $Item.RelativePath
                Hash256      = $Item.Hash256
            }
        }
        $Script:BuildLogger.Info("已从 $Path 读取 $($Snapshot.Count) 个文件快照")
        return $Snapshot
    }
    catch {
        $Script:BuildLogger.Warn("无法读取资源快照: $($_.Exception.Message)")
        return $null
    }
}
function Compress-ResourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ResourceFileInfo[]]$ResourceFiles,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $false)]
        [System.IO.Compression.CompressionLevel]$CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    try {
        $Script:BuildLogger.Info("开始压缩 $($ResourceFiles.Count) 个资源文件到: $DestinationPath")
        $ZipFileStream = if ($Force -or -not (Test-Path $DestinationPath)) {
            [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create)
        }
        else {
            $Script:BuildLogger.Error("目标位置被占用: $DestinationPath")
            throw "目标位置被占用: $DestinationPath"
        }
        $ZipArchive = [System.IO.Compression.ZipArchive]::new($ZipFileStream, [System.IO.Compression.ZipArchiveMode]::Create)
        $FileCount = 0
        foreach ($ResourceFile in $ResourceFiles) {
            if (-not (Test-Path -Path $ResourceFile.FileInfo -PathType Leaf)) {
                $Script:BuildLogger.Warn("找不到文件：$($ResourceFile.FileInfo)")
                $Script:BuildLogger.Warn("已自动跳过")
                continue
            }
            try {
                $EntryName = $ResourceFile.RelativePath -replace '^\.\\', '' -replace '^\./', ''
                $ZipEntry = $ZipArchive.CreateEntry($EntryName, $CompressionLevel)
                $EntryStream = $ZipEntry.Open()
                $FileStream = [System.IO.File]::OpenRead($ResourceFile.FileInfo)
                $FileStream.CopyTo($EntryStream)
                $EntryStream.Close()
                $FileStream.Close()
                $FileCount++
                if ($FileCount % 10 -eq 0) {
                    $Script:BuildLogger.Debug("  已压缩 $FileCount 个文件...")
                }
            }
            catch {
                $Script:BuildLogger.Error("压缩文件失败 '$($ResourceFile.FileInfo.FullName)': $($_.Exception.Message)")
                throw
            }
        }
        $ZipArchive.Dispose()
        $ZipFileStream.Close()
        $Script:BuildLogger.Info("资源压缩完成，共 $FileCount 个文件")
        if (Test-Path -Path $DestinationPath -PathType Leaf) {
            $ZipInfo = Get-Item -Path $DestinationPath
            $Script:BuildLogger.Info("ZIP文件大小: $([math]::Round($ZipInfo.Length / 1KB, 2)) KB")
        }
    }
    catch {
        $Script:BuildLogger.Error("无法压缩资源文件：$($_.Exception.Message)")
        throw
    }
}
function Get-ResourceEmbedModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipFilePath,
        [Parameter(Mandatory = $false)]
        [switch]$External,
        [Parameter(Mandatory = $false)]
        [string]$ExternalOutputPath
    )
    if (-not (Test-Path -Path $ZipFilePath -PathType Leaf)) {
        $Script:BuildLogger.Error("ZIP文件不存在: $ZipFilePath")
        return $null
    }
    try {
        $Script:BuildLogger.Info("生成资源嵌入模块: $ZipFilePath")
        $ZipBytes = [System.IO.File]::ReadAllBytes($ZipFilePath)
        $ZipHash = Get-FileHash -InputStream ([System.IO.MemoryStream]::new($ZipBytes)) -Algorithm SHA256
        $ResourceCode = if ($External) {
            $ZipFileName = if ($ExternalOutputPath) {
                [System.IO.Path]::GetFileName($ExternalOutputPath)
            } else {
                [System.IO.Path]::GetFileName($ZipFilePath)
            }
            $Script:BuildLogger.Info("外部模式 - ZIP文件名: $ZipFileName, 哈希: $($ZipHash.Hash)")
            @(
                "`$BuiltinResourceZipHash = `"$($ZipHash.Hash)`"",
                "`$BuiltinResourceZipName = `"$($ZipFileName.Replace('"','""'))`""
            )
        } else {
            $Base64Data = [System.Convert]::ToBase64String($ZipBytes)
            @(
                "`$BuiltinResourceZipHash = `"$($ZipHash.Hash)`"",
                "`$BuiltinResourceZipContent = [System.Convert]::FromBase64String(`"$($Base64Data)`")"
            )
        }
        $ResourceEmbedModule = [InfinityModule]@{
            Name         = 'Builtin.Resource'
            Code         = $ResourceCode
            Requires     = [System.Collections.Generic.List[string]]::new()
            SourceInfo   = Get-Item -Path $PSCommandPath
            LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
        }
        $ModuleCodeSize = [math]::Round(($ResourceEmbedModule.Code | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum / 1KB, 2)
        $Script:BuildLogger.Info("资源嵌入模块生成完成 (模块大小: $ModuleCodeSize KB)")
        return $ResourceEmbedModule
    }
    catch {
        $Script:BuildLogger.Error("生成资源嵌入模块失败: $($_.Exception.Message)")
        throw
    }
}
$Script:BuildLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityBuild")
$Script:BuildLogger = [LogClient]::new($Script:BuildLoggerServer)
$Script:NugetLoggerServer = [LogServer]::new([LogType]::LogDebug, "InfinityNuget")
$Script:NugetLogger = [LogClient]::new($Script:NugetLoggerServer)
function Find-Files {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Filters,
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location)
    )
    $Script:BuildLogger.Debug("查找文件: 路径=$Path, 过滤器=$($Filters -join ', ')")
    $FoundFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($Filter in $Filters) {
        $LastSep = [Math]::Max($Filter.LastIndexOf('/'), $Filter.LastIndexOf('\'))
        if ($LastSep -ge 0) {
            $SubDir = $Filter.Substring(0, $LastSep)
            $FileFilter = $Filter.Substring($LastSep + 1)
            $SearchPath = Join-Path $Path $SubDir
        }
        else {
            $FileFilter = $Filter
            $SearchPath = $Path
        }
        $Script:BuildLogger.Debug("  搜索路径: $SearchPath, 文件过滤器: $FileFilter")
        $Files = Get-ChildItem -Path $SearchPath -Filter $FileFilter -File -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            $FoundFiles.Add($File.FullName)
        }
    }
    $Script:BuildLogger.Debug("找到 $($FoundFiles.Count) 个文件")
    return $FoundFiles.ToArray()
}
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
function Get-InfinityModule {
    [CmdletBinding()]
    [OutputType([InfinityModule])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $Script:BuildLogger.Info("读取模块: $Path")
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        $Script:BuildLogger.Error("模块文件不存在: $Path")
        throw "模块文件不存在: $Path"
    }
    try {
        $FileContent = Get-Content -Path $Path -ReadCount 0 -Raw
    }
    catch {
        $Script:BuildLogger.Error("读取模块文件失败 '$Path': $($_.Exception.Message)")
        throw "读取模块文件失败 '$Path': $($_.Exception.Message)"
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($FileContent, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            $Script:BuildLogger.Warn("语法解析警告: $($err.Message) 来自: $($Path): line $($err.Extent.StartLineNumber)")
        }
    }
    $SourceInfo = Get-Item -Path $Path
    $InfinityModule = [InfinityModule]@{
        Name         = $SourceInfo.BaseName
        Requires     = [System.Collections.Generic.List[string]]::new()
        Code         = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = $SourceInfo
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    }
    $stringTokens = $tokens | Where-Object {
        $_.Kind -eq 'StringExpandable' -or $_.Kind -eq 'StringLiteral' -or
        $_.Kind -eq 'HereStringExpandable' -or $_.Kind -eq 'HereStringLiteral'
    }
    $commentTokens = $tokens | Where-Object { $_.Kind -eq 'Comment' }
    foreach ($comment in $commentTokens) {
        $commentLines = $comment.Text -split '\r?\n'
        foreach ($line in $commentLines) {
            $trimmedLine = $line.Trim()
            if ($trimmedLine.StartsWith('##')) {
                $directiveParts = $trimmedLine.Substring(2) -split '\s+', 2
                switch ($directiveParts[0]) {
                    'Module' {
                        $InfinityModule.Name = $directiveParts[1].Trim()
                        $Script:BuildLogger.Debug("  模块名: $($InfinityModule.Name)")
                    }
                    'Import' {
                        $InfinityModule.Requires.Add($directiveParts[1].Trim())
                        $Script:BuildLogger.Debug("  依赖模块: $($directiveParts[1].Trim())")
                    }
                    Default {
                        $Script:BuildLogger.Warn("未知的预处理指令: $line")
                        $Script:BuildLogger.Warn("来自: $($Path): line $($comment.Extent.StartLineNumber)")
                    }
                }
            }
        }
    }
    $lineCommentRanges = @{}
    foreach ($comment in $commentTokens) {
        $extent = $comment.Extent
        $startLine = $extent.StartLineNumber
        $startCol  = $extent.StartColumnNumber
        $endLine   = $extent.EndLineNumber
        $endCol    = $extent.EndColumnNumber
        if ($startLine -eq $endLine) {
            if (-not $lineCommentRanges.ContainsKey($startLine)) {
                $lineCommentRanges[$startLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$startLine].Add([PSCustomObject]@{Start = $startCol; End = $endCol})
        }
        else {
            if (-not $lineCommentRanges.ContainsKey($startLine)) {
                $lineCommentRanges[$startLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$startLine].Add([PSCustomObject]@{Start = $startCol; End = [int]::MaxValue})
            for ($line = $startLine + 1; $line -lt $endLine; $line++) {
                if (-not $lineCommentRanges.ContainsKey($line)) {
                    $lineCommentRanges[$line] = [System.Collections.Generic.List[object]]::new()
                }
                $lineCommentRanges[$line].Add([PSCustomObject]@{Start = 1; End = [int]::MaxValue})
            }
            if (-not $lineCommentRanges.ContainsKey($endLine)) {
                $lineCommentRanges[$endLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$endLine].Add([PSCustomObject]@{Start = 1; End = $endCol})
        }
    }
    [string[]]$Lines = $FileContent -split '\r?\n'
    for ([int]$i = 0; $i -lt $Lines.Count; ++$i) {
        $lineNum = $i + 1
        $lineText = $Lines[$i]
        $ranges = $lineCommentRanges[$lineNum]
        $filteredLine = if ($ranges) {
            $sorted = $ranges | Sort-Object Start
            $result = ''
            $currentPos = 1
            foreach ($range in $sorted) {
                $start = $range.Start
                $end   = [Math]::Min($range.End, $lineText.Length + 1)
                if ($start -gt $currentPos) {
                    $result += $lineText.Substring($currentPos - 1, $start - $currentPos)
                }
                $currentPos = $end
            }
            if ($currentPos -le $lineText.Length) {
                $result += $lineText.Substring($currentPos - 1)
            }
            $result
        }
        else {
            $lineText
        }
        $trimmedLine = $filteredLine.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            $insideString = $false
            foreach ($strToken in $stringTokens) {
                $ext = $strToken.Extent
                if ($lineNum -ge $ext.StartLineNumber -and $lineNum -le $ext.EndLineNumber) {
                    $insideString = $true
                    break
                }
            }
            if (-not $insideString) {
                continue
            }
        }
        $InfinityModule.Code.Add($trimmedLine)
        $InfinityModule.LineMappings[$InfinityModule.Code.Count] = $lineNum
    }
    $Script:BuildLogger.Info("模块 '$($InfinityModule.Name)' 读取完成: $($InfinityModule.Code.Count) 行代码, $($InfinityModule.Requires.Count) 个依赖")
    return $InfinityModule
}
function Get-InfinityModuleOrdered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )
    $Script:BuildLogger.Info("对 $($Modules.Count) 个模块进行拓扑排序")
    $ModuleMap = [System.Collections.Generic.Dictionary[string, InfinityModule]]::new()
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    $InDegree = [System.Collections.Generic.Dictionary[string, int]]::new()
    $AdjacencyList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]::new()
    foreach ($Module in $Modules) {
        $InDegree[$Module.Name] = 0
        $AdjacencyList[$Module.Name] = [System.Collections.Generic.List[string]]::new()
    }
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
    $SortedModules = [System.Collections.Generic.List[InfinityModule]]::new()
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($ModuleName in $InDegree.Keys) {
        if ($InDegree[$ModuleName] -eq 0) {
            $Queue.Enqueue($ModuleName)
        }
    }
    while ($Queue.Count -gt 0) {
        $CurrentModuleName = $Queue.Dequeue()
        $SortedModules.Add($ModuleMap[$CurrentModuleName])
        foreach ($DependentModuleName in $AdjacencyList[$CurrentModuleName]) {
            $InDegree[$DependentModuleName] -= 1
            if ($InDegree[$DependentModuleName] -eq 0) {
                $Queue.Enqueue($DependentModuleName)
            }
        }
    }
    if ($SortedModules.Count -ne $Modules.Count) {
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
function Select-InfinityModuleReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RootNames,
        [Parameter(Mandatory = $true)]
        [InfinityModule[]]$Modules
    )
    $Script:BuildLogger.Info("从 $($RootNames.Count) 个根模块中筛选可达模块，总模块数: $($Modules.Count)")
    $ModuleMap = @{}
    foreach ($Module in $Modules) {
        $ModuleMap[$Module.Name] = $Module
    }
    $Visited = [System.Collections.Generic.HashSet[string]]::new()
    $Queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($RootName in $RootNames) {
        if (-not $ModuleMap.ContainsKey($RootName)) {
            $Script:BuildLogger.Warn("根模块 '$RootName' 不在提供的模块列表中，已跳过")
            continue
        }
        if ($Visited.Add($RootName)) {
            $Queue.Enqueue($RootName)
        }
    }
    while ($Queue.Count -gt 0) {
        $CurrentName = $Queue.Dequeue()
        $CurrentModule = $ModuleMap[$CurrentName]
        foreach ($RequiredName in $CurrentModule.Requires) {
            if (-not $ModuleMap.ContainsKey($RequiredName)) {
                $Script:BuildLogger.Warn("模块 '$CurrentName' 依赖的模块 '$RequiredName' 不在提供的模块列表中")
                continue
            }
            if ($Visited.Add($RequiredName)) {
                $Queue.Enqueue($RequiredName)
            }
        }
    }
    $ReachableModules = $Modules | Where-Object { $Visited.Contains($_.Name) }
    $RemovedCount = $Modules.Count - $ReachableModules.Count
    if ($RemovedCount -gt 0) {
        $RemovedNames = ($Modules | Where-Object { -not $Visited.Contains($_.Name) }).Name -join ', '
        $Script:BuildLogger.Info("已剔除 $RemovedCount 个不被根模块依赖的模块: $RemovedNames")
    }
    $Script:BuildLogger.Info("可达模块筛选完成，保留 $($ReachableModules.Count) 个模块")
    return $ReachableModules
}
$Script:ModuleBuilders["Boot"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $EntryPoint = if ($Config.ContainsKey("EntryPoint")) {
        $Config["EntryPoint"]
    } else {
        $Script:BuildLogger.Warn("Boot 配置中缺少 'EntryPoint'，跳过启动模块生成")
        return @()
    }
    $RequireList = [System.Collections.Generic.List[string]]::new()
    if ($Config.ContainsKey("Require")) {
        $RequireList.Add($Config["Require"])
        $Script:BuildLogger.Info("启动模块依赖: $($Config['Require'])")
    }
    $Script:BuildLogger.Info("生成启动模块，入口函数: $EntryPoint")
    $BootCode = [System.Collections.Generic.List[string]]::new()
    $BootCode.Add("$EntryPoint @args")
    return @([InfinityModule]@{
        Name         = 'Builtin.Boot'
        Code         = $BootCode
        Requires     = $RequireList
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}
$Script:ModuleBuilders["PreDefineds"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $Script:BuildLogger.Info("生成预定义变量模块")
    $PreDefinedsModule = [InfinityModule]@{
        Name         = 'Builtin.PreDefineds'
        Requires     = [System.Collections.Generic.List[string]]::new()
        Code         = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    }
    $IncludeDefault = if ($Config.ContainsKey("Default")) { $Config["Default"] } else { $false }
    $DefinedsList = if ($Config.ContainsKey("Defineds") -and $Config["Defineds"] -is [array]) {
        $Config["Defineds"]
    } else { @() }
    if ($IncludeDefault) {
        if ($Script:BuildSystem.ContainsKey("Name")) {
            $PreDefinedsModule.Code.Add("`$BuildName = '$($Script:BuildSystem['Name'].Replace("'","''"))'")
        }
        if ($Script:BuildSystem.ContainsKey("Version")) {
            $PreDefinedsModule.Code.Add("`$BuildVersion = '$($Script:BuildSystem['Version'].Replace("'","''"))'")
        }
        if ($Script:BuildSystem.ContainsKey("Mode")) {
            $PreDefinedsModule.Code.Add("`$BuildMode = '$($Script:BuildSystem['Mode'].Replace("'","''"))'")
        }
        $Script:BuildLogger.Info("  已注入 $($PreDefinedsModule.Code.Count) 个默认系统变量")
    }
    foreach ($Item in $DefinedsList) {
        if ($Item -is [hashtable]) {
            foreach ($Name in $Item.Keys) {
                Add-PreDefinedVariable -Module $PreDefinedsModule -Name $Name -Value $Item[$Name]
            }
        }
    }
    $Script:BuildLogger.Info("预定义变量模块生成完成: $($PreDefinedsModule.Code.Count) 个变量")
    return @($PreDefinedsModule)
}
$Script:ModuleBuilders["Resource"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $ResourceZipPath = Join-Path $Script:CacheFolder "resource.zip"
    $ResourceSnapshotPath = Join-Path $Script:CacheFolder "resource_snapshot.json"
    $ResourceType = if ($Config.ContainsKey("Type")) { $Config["Type"] } else { "Builtin" }
    if ($ResourceType -notin @("Builtin", "External")) {
        $Script:BuildLogger.Error("不支持的资源类型: $ResourceType")
        throw "不支持的资源类型: $ResourceType"
    }
    $ResourceMappings = if ($Config.ContainsKey("resources") -and $Config["resources"] -is [array]) {
        $Config["resources"]
    } else { @() }
    if ($ResourceMappings.Count -eq 0) {
        $Script:BuildLogger.Warn("资源配置中没有资源映射，跳过资源构建")
        return @()
    }
    $AllResourceFiles = [System.Collections.Generic.List[ResourceFileInfo]]::new()
    foreach ($Mapping in $ResourceMappings) {
        if ($Mapping -isnot [hashtable] -or $Mapping.Count -eq 0) {
            $Script:BuildLogger.Warn("跳过无效的资源映射条目")
            continue
        }
        foreach ($SourceRel in $Mapping.Keys) {
            $DestPrefix = $Mapping[$SourceRel]
            $SourcePath = if ([System.IO.Path]::IsPathRooted($SourceRel)) {
                $SourceRel
            } else {
                Join-Path (Get-Location) $SourceRel
            }
            $DestPrefix = $DestPrefix -replace '^\.\\|^\./|\\$|/$', ''
            $DestPrefix = $DestPrefix -replace '\\', '/'
            $Script:BuildLogger.Info("资源映射: $SourceRel -> $DestPrefix/")
            if (-not (Test-Path $SourcePath -PathType Container)) {
                $Script:BuildLogger.Warn("资源源目录不存在: $SourcePath，跳过")
                continue
            }
            $Files = Get-ChildItem -Path $SourcePath -File -Recurse -ErrorAction SilentlyContinue
            foreach ($File in $Files) {
                try {
                    $FileRelativePath = Resolve-Path -Path $File -Relative -RelativeBasePath $SourcePath
                    $FileRelativePath = $FileRelativePath -replace '^\.\\|^\./', ''
                    $FileRelativePath = $FileRelativePath -replace '\\', '/'
                    $ZipEntryPath = if ($DestPrefix) {
                        "$DestPrefix/$FileRelativePath"
                    } else {
                        $FileRelativePath
                    }
                    $AllResourceFiles.Add([ResourceFileInfo]@{
                        FileInfo     = $File
                        RelativePath = $ZipEntryPath
                    })
                }
                catch {
                    $Script:BuildLogger.Warn("处理资源文件失败 '$($File.FullName)': $($_.Exception.Message)")
                }
            }
        }
    }
    if ($AllResourceFiles.Count -eq 0) {
        $Script:BuildLogger.Error("没有找到任何资源文件，无法构建资源模块")
        throw "没有找到任何资源文件，无法构建资源模块"
    }
    $ResourceFiles = $AllResourceFiles.ToArray()
    $Script:BuildLogger.Info("共收集 $($ResourceFiles.Count) 个资源文件（来自 $($ResourceMappings.Count) 个源）")
    $CurrentSnapshot = Get-ResourceSnapshot -ResourceFiles $ResourceFiles
    $PreviousSnapshot = Read-ResourceSnapshot -Path $ResourceSnapshotPath
    $IsChanged = if ($PreviousSnapshot) {
        -not (Compare-ResourceSnapshot -NewSnapshot $CurrentSnapshot -OldSnapshot $PreviousSnapshot)
    }
    else {
        $Script:BuildLogger.Info("未找到先前的资源快照文件: $ResourceSnapshotPath")
        $true
    }
    if ($IsChanged) {
        $Script:BuildLogger.Info("资源发生变化，开始压缩资源...")
        Compress-ResourceFiles -ResourceFiles $ResourceFiles -DestinationPath $ResourceZipPath -Force
        Write-ResourceSnapshot -Snapshot $CurrentSnapshot -Path $ResourceSnapshotPath
        $Script:BuildLogger.Info("资源压缩完成，已更新快照")
    }
    else {
        $Script:BuildLogger.Info("资源未发生变化，使用缓存的资源压缩包")
    }
    if ($ResourceType -eq "Builtin") {
        $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath
        $Ret = if ($Module) { @($Module) } else { @() }
        return $Ret
    }
    elseif ($ResourceType -eq "External") {
        $ExternalOutputDir = if ($Config.ContainsKey("OutputDir")) {
            $OutDir = $Config["OutputDir"]
            if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
                Join-Path (Get-Location) $OutDir
            } else {
                $OutDir
            }
        } else {
            (Get-Location)
        }
        $ExternalOutputName = if ($Config.ContainsKey("OutputName")) {
            $Config["OutputName"]
        } else {
            "$Script:BuildName-resources.zip"
        }
        if ($ExternalOutputName -notmatch '\.zip$') {
            $ExternalOutputName += '.zip'
        }
        $ExternalOutputPath = Join-Path $ExternalOutputDir $ExternalOutputName
        if (-not (Test-Path $ExternalOutputDir -PathType Container)) {
            $null = New-Item -Path $ExternalOutputDir -ItemType Directory -Force
            $Script:BuildLogger.Info("创建外部资源输出目录: $ExternalOutputDir")
        }
        Copy-Item -Path $ResourceZipPath -Destination $ExternalOutputPath -Force
        $Script:BuildLogger.Info("资源包已复制到外部路径: $ExternalOutputPath")
        $Module = Get-ResourceEmbedModule -ZipFilePath $ResourceZipPath -External -ExternalOutputPath $ExternalOutputPath
        $Ret = if ($Module) { @($Module) } else { @() }
        return $Ret
    }
}
class NugetSource {
    [string]$Version = $null
    [hashtable]$ServiceEndpoints = @{}
}
function New-NugetSource {
    [CmdletBinding()]
    [OutputType([NugetSource])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url
    )
    $Source = [NugetSource]::new()
    try {
        $RequestParams = @{
            Uri         = $Url
            Method      = "Get"
            TimeoutSec  = 30
            ErrorAction = "Stop"
        }
        $Response = Invoke-WebRequest @RequestParams
        if (-not $Response.Content) {
            throw "NuGet 包源响应内容为空：$Source"
        }
        try {
            $Data = $Response.Content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $Script:NugetLogger.Error("NuGet 包源JSON解析失败：$Source，错误信息：$($_.Exception.Message)")
            throw
        }
        $Source.Version = if ($Data.ContainsKey('version')) { $Data['version'] } else { "unknown" }
        if ($Data.ContainsKey('resources') -and $Data['resources'] -is [array]) {
            foreach ($Resource in $Data['resources']) {
                if ($Resource.ContainsKey('@type') -and $Resource.ContainsKey('@id')) {
                    $Source.ServiceEndpoints[$Resource['@type']] = $Resource['@id'] -replace '/$', ''
                }
            }
        }
        else {
            $Script:NugetLogger.Warn("NuGet 包源未找到有效资源列表：$Source")
        }
    }
    catch {
        if ($_.Exception.Response) {
            $StatusCode = $_.Exception.Response.StatusCode
            $StatusDesc = $_.Exception.Response.StatusDescription
            $Script:NugetLogger.Error("NuGet 包源请求失败: $Source | 状态码: $StatusCode | 描述: $StatusDesc")
        }
        else {
            $Script:NugetLogger.Error("NuGet 包源初始化失败: $Source | 错误: $($_.Exception.Message)")
        }
        throw
    }
    return $Source
}
function Search-NugetPackage {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetSource]$Source,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,
        [Parameter(Mandatory = $false)]
        [string]$PackageType,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$Take = 20,
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3000)]
        [int]$Skip = 0,
        [Parameter(Mandatory = $false)]
        [switch]$Prerelease
    )
    begin {
        if ($Source.ServiceEndpoints.ContainsKey("SearchQueryService/3.5.0")) {
            $SearchEndpoint = $Source.ServiceEndpoints["SearchQueryService/3.5.0"]
        }
        elseif ($Source.ServiceEndpoints.ContainsKey("SearchQueryService")) {
            if ($PackageType) {
                $Script:NugetLogger.Warn("包源不支持 SearchQueryService/3.5.0 无法筛选包类型")
                $PackageType = $null
            }
            $SearchEndpoint = $Source.ServiceEndpoints["SearchQueryService"]
        }
        else {
            throw "包源缺失 SearchQueryService 端点"
        }
    }
    process {
        try {
            $QueryParams = [System.Web.HttpUtility]::ParseQueryString([string]::Empty)
            $QueryParams.Add("q", [System.Web.HttpUtility]::UrlEncode($Query))
            $QueryParams.Add("take", $Take.ToString())
            $QueryParams.Add("skip", $Skip.ToString())
            $QueryParams.Add("prerelease", "$Prerelease".ToLower())
            if ($PackageType) {
                $QueryParams.Add("packageType", [System.Web.HttpUtility]::UrlEncode($PackageType))
            }
            $Url = "$($SearchEndpoint)?$($QueryParams.ToString())"
            $Script:NugetLogger.Info("尝试请求 $Url")
            $RequestParams = @{
                Uri         = $Url
                Method      = "Get"
                TimeoutSec  = 30
                ErrorAction = "Stop"
            }
            $Response = Invoke-RestMethod @RequestParams
            if ($Response -and $Response.Data) {
                return $Response.Data
            }
            else {
                $Script:NugetLogger.Warn("NuGet 搜索无结果：Query=$Query | Source=$($SearchEndpoint)")
                return @()
            }
        }
        catch {
            $ErrorMsg = if ($_.Exception.Response) {
                $StatusCode = [int]$_.Exception.Response.StatusCode
                $ReasonPhrase = $_.Exception.Response.ReasonPhrase
                "NuGet 搜索请求失败 | URL: $Url | 状态码: $StatusCode | 原因: $ReasonPhrase"
            }
            else {
                "NuGet 搜索失败 | Query: $Query | 错误: $($_.Exception.Message)"
            }
            $Script:NugetLogger.Error($ErrorMsg)
            throw
        }
    }
}
function Get-NugetPackageVersions {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [switch]$Preview
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/index.json"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-RestMethod -Uri $Url -Method Get
        $Versions = $Response.versions | ConvertTo-NuGetVersion
        return $Versions | Where-Object { $Preview -or (-not $_.IsPrerelease()) }
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}
function Get-NugetPackagManifest {
    [CmdletBinding()]
    [OutputType([xml])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/$($Version.ToLowerInvariant())/$($Id.ToLowerInvariant()).nuspec"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-WebRequest -Uri $Url -Method Get
        return [xml]$Response.Content
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id-$Version 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}
function Get-NugetPackagContent {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [NugetSource]$Source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )
    if (-not $Source.ServiceEndpoints.ContainsKey('PackageBaseAddress/3.0.0')) {
        throw "包源不支持 PackageBaseAddress/3.0.0"
    }
    $PackageBaseAddress = $Source.ServiceEndpoints['PackageBaseAddress/3.0.0'];
    $Url = "$($PackageBaseAddress)/$($Id.ToLowerInvariant())/$($Version.ToLowerInvariant())/$($Id.ToLowerInvariant()).$($Version.ToLowerInvariant()).nupkg"
    $Script:NugetLogger.Info("尝试请求 $Url")
    try {
        $Response = Invoke-WebRequest -Uri $Url -Method Get
        return [byte[]]$Response.Content
    }
    catch {
        switch ([int]$_.Exception.Response.StatusCode) {
            404 {
                $Script:NugetLogger.Error("包: $Id-$Version 不存在")
            }
            default {
                $Script:NugetLogger.Error("未知错误")
            }
        }
        throw
    }
}
$Script:ModuleBuilders["Source"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $SourceFiles = Find-Files -Filters $Config.Files
    $Script:BuildLogger.Info("找到 $($SourceFiles.Count) 个源文件")
    if ($SourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到任何源文件")
        return @()
    }
    $Modules = $SourceFiles | Select-Object -Unique | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}
$Script:ModuleBuilders["Std"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    if ($Config.ContainsKey("Enable")) {
        if (-not $Config.Enable) {
            return @()
        }
    }
    $AllSourceFiles = [System.Collections.Generic.List[string]]::new()
    $StdLibPath = Join-Path $PSScriptRoot "std"
    if (Test-Path $StdLibPath -PathType Container) {
        $StdJsonPath = Join-Path $StdLibPath "std.json"
        $IncludePatterns = @()
        if (Test-Path $StdJsonPath -PathType Leaf) {
            try {
                $StdJsonConfig = Get-Content $StdJsonPath -Raw | ConvertFrom-Json -AsHashtable
                if ($StdJsonConfig.ContainsKey("Std") -and $StdJsonConfig["Std"] -is [array]) {
                    $IncludePatterns = $StdJsonConfig["Std"]
                    $Script:BuildLogger.Info("从 std.json 读取包含模式: $($IncludePatterns -join ', ')")
                }
            }
            catch {
                $Script:BuildLogger.Warn("读取 std.json 失败: $($_.Exception.Message)，使用默认模式 *.psm1")
            }
        }
        if ($IncludePatterns.Count -eq 0) {
            $Script:BuildLogger.Info("std.json 未配置或不存在，使用默认模式 *.psm1")
            $IncludePatterns = @("*.psm1")
        }
        $BuiltinFiles = Find-Files -Filters $IncludePatterns -Path $StdLibPath
        foreach ($f in $BuiltinFiles) {
            $AllSourceFiles.Add($f)
        }
        $Script:BuildLogger.Info("内置 Std: 找到 $($BuiltinFiles.Count) 个源文件")
    }
    else {
        $Script:BuildLogger.Warn("标准库目录不存在: $StdLibPath")
    }
    $Script:BuildLogger.Info("Std 总共收集 $($AllSourceFiles.Count) 个源文件")
    if ($AllSourceFiles.Count -eq 0) {
        $Script:BuildLogger.Warn("未找到任何标准库源文件")
        return @()
    }
    $UniqueFiles = $AllSourceFiles | Select-Object -Unique
    $Modules = $UniqueFiles | ForEach-Object {
        Get-InfinityModule -Path $_
    }
    return @($Modules)
}
class NugetPackageLibraryManifest {
    [hashtable]$Packages = @{}
}
$Script:NugetPackageLibraryManifestFileName = "infinity_nuget_library.json"
function Save-NugetPackageLibraryManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetPackageLibraryManifest]$Manifest
    )
    try {
        $ManifestPath = Join-Path $Path $Script:NugetPackageLibraryManifestFileName
        $Script:NugetLogger.Info("保存包库清单到: $ManifestPath")
        $Manifest | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $ManifestPath -Encoding UTF8 -Force
        $Script:NugetLogger.Info("包库清单保存成功")
    }
    catch {
        $Script:NugetLogger.Error("保存包库清单失败: $($_.Exception.Message)")
        throw
    }
}
function Read-NugetPackageLibraryManifest {
    [CmdletBinding()]
    [OutputType([NugetPackageLibraryManifest])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    try {
        $ManifestPath = Join-Path $Path $Script:NugetPackageLibraryManifestFileName
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "未找到库清单文件: $ManifestPath"
        }
        $Script:NugetLogger.Info("从 $ManifestPath 读取包库清单")
        $Json = Get-Content -Path $ManifestPath -Raw -Encoding UTF8
        $ManifestData = $Json | ConvertFrom-Json -AsHashtable
        if(-not $ManifestData.ContainsKey("Packages")){
            $Script:NugetLogger.Warn("包库清单缺失 Packages 项, 自动补全")
            $PackageManifest['Packages'] = @{}
        }
        $PackageManifest = [NugetPackageLibraryManifest]::new()
        $PackageManifest.Packages = $ManifestData.Packages
        $Script:NugetLogger.Info("包库清单读取成功")
        return $PackageManifest
    }
    catch {
        $Script:NugetLogger.Error("读取包库清单失败: $($_.Exception.Message)")
        throw
    }
}
function New-NugetPackageLibraryManifest {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    if (-not (Test-Path -Path $Path -PathType Container)) {
        $Item = New-Item -Path $Path -ItemType Directory -Force
        $Path = $Item.FullName
    }
    else {
        $Item = Get-Item -Path $Path
        $Path = $Item.FullName
    }
    $Script:NugetLogger.Info("Nuget 包库文件夹: $($Path)")
    $PackageLibrary = [NugetPackageLibraryManifest]::new()
    Save-NugetPackageLibraryManifest -Path $Path -Manifest $PackageLibrary
    return $Path
}
function Install-NugetPackage {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [NugetSource]$Source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    try {
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }
        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $Id = $Id.Trim().ToLowerInvariant()
        $Version = $Version.Trim().ToLowerInvariant()
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath
        $PackagePath = Join-Path $LibraryPath $Id $Version
        if ($Manifest.Packages.ContainsKey($Id) -and $Manifest.Packages[$Id].ContainsKey($Version)) {
            if ($Force) {
                $Script:NugetLogger.Warn("包已存在，强制重新安装: $Id.$Version")
                if (Test-Path -Path $PackagePath) {
                    Remove-Item -Path $PackagePath -Recurse -Force
                }
            }
            else {
                $Script:NugetLogger.Info("包已安装: $Id.$Version")
                return $PackagePath
            }
        }
        if (Test-Path -Path $PackagePath) {
            if ($Force) {
                $Script:NugetLogger.Warn("异常的包文件存在于: $PackagePath")
                $Script:NugetLogger.Warn("强制删除: $PackagePath")
                Remove-Item -Path $PackagePath -Recurse -Force
            }
            else {
                throw "异常的包文件存在于: $PackagePath"
            }
        }
        $Script:NugetLogger.Info("开始安装包: $Id 版本: $Version")
        $PackageBytes = Get-NugetPackagContent -Source $Source -Id $Id -Version $Version
        $Script:NugetLogger.Info("包下载完成，大小: $([math]::Round($PackageBytes.Length/1KB,2)) KB")
        $null = New-Item -Path $PackagePath -ItemType Directory -Force
        $Script:NugetLogger.Info("创建包目录: $PackagePath")
        $NupkgPath = Join-Path $PackagePath "$Id.$Version.nupkg"
        [System.IO.File]::WriteAllBytes($NupkgPath, $PackageBytes)
        $Script:NugetLogger.Info("保存 .nupkg 文件到: $NupkgPath")
        $Script:NugetLogger.Info("开始解压包文件")
        Expand-Archive -Path $NupkgPath -DestinationPath $PackagePath
        $Script:NugetLogger.Info("包解压完成")
        if (-not $Manifest.Packages.ContainsKey($Id)) {
            $Manifest.Packages[$Id] = @{}
        }
        $Manifest.Packages[$Id][$Version] = @{
            InstallDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
        $Script:NugetLogger.Info("包安装成功: $Id.$Version")
        return $PackagePath
    }
    catch {
        $Script:NugetLogger.Error("安装包失败: $($_.Exception.Message)")
        if ($PackagePath -and (Test-Path -Path $PackagePath)) {
            Remove-Item -Path $PackagePath -Recurse -Force -ErrorAction SilentlyContinue
            $Script:NugetLogger.Info("清理失败安装的目录: $PackagePath")
        }
        throw
    }
}
function Uninstall-NugetPackage {
    [CmdletBinding(DefaultParameterSetName = 'SpecificVersion')]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVersion')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AllVersions')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $true, ParameterSetName = 'SpecificVersion')]
        [ValidateNotNullOrEmpty()]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,
        [Parameter(Mandatory = $true, ParameterSetName = 'AllVersions')]
        [switch]$AllVersions
    )
    try {
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }
        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $Id = $Id.Trim().ToLowerInvariant()
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath
        if (-not $Manifest.Packages.ContainsKey($Id)) {
            $Script:NugetLogger.Warn("包未安装: $Id")
            return $false
        }
        if ($AllVersions) {
            $VersionCount = $Manifest.Packages[$Id].Count
            if ($VersionCount -eq 0) {
                $Manifest.Packages.Remove($Id)
                Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
                return $true
            }
            $Script:NugetLogger.Info("开始卸载包 $Id 的所有版本，共 $VersionCount 个版本")
            $PackageDir = Join-Path $LibraryPath $Id
            if (Test-Path -Path $PackageDir -PathType Container) {
                Remove-Item -Path $PackageDir -Recurse -Force
                $Script:NugetLogger.Info("删除包目录: $PackageDir")
            }
            $Manifest.Packages.Remove($Id)
            Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
            $Script:NugetLogger.Info("成功卸载包 $Id 的所有版本")
            return $true
        }
        $Version = $Version.Trim().ToLowerInvariant()
        if (-not $Manifest.Packages[$Id].ContainsKey($Version)) {
            $Script:NugetLogger.Warn("包版本未安装: $Id.$Version")
            return $false
        }
        $Script:NugetLogger.Info("开始卸载包: $Id.$Version")
        $PackageDir = Join-Path $LibraryPath $Id $Version
        if (Test-Path -Path $PackageDir -PathType Container) {
            Remove-Item -Path $PackageDir -Recurse -Force
            $Script:NugetLogger.Info("删除包目录: $PackageDir")
        }
        $Manifest.Packages[$Id].Remove($Version)
        if ($Manifest.Packages[$Id].Count -eq 0) {
            $Manifest.Packages.Remove($Id)
        }
        Save-NugetPackageLibraryManifest -Path $LibraryPath -Manifest $Manifest
        $Script:NugetLogger.Info("成功卸载包: $Id.$Version")
        return $true
    }
    catch {
        $Script:NugetLogger.Error("卸载包失败: $($_.Exception.Message)")
        throw
    }
}
$Script:ImportedPackages = @{}
$Script:ImportedAssemblies = @{}
function Get-CurrentRuntimeFramework {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $version = [System.Environment]::Version
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $major = $version.Major
        $minor = $version.Minor
        if ($major -ge 5) {
            return "net$major.$minor"
        }
        return "netcoreapp$major.$minor"
    }
    else {
        $releaseKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue
        if ($releaseKey) {
            $release = $releaseKey.Release
            switch ($release) {
                { $_ -ge 533320 } { return 'net481' }
                { $_ -ge 528040 } { return 'net48' }
                { $_ -ge 461808 } { return 'net472' }
                { $_ -ge 461308 } { return 'net471' }
                { $_ -ge 460798 } { return 'net47' }
                { $_ -ge 394802 } { return 'net462' }
                { $_ -ge 394254 } { return 'net461' }
                { $_ -ge 393295 } { return 'net46' }
                { $_ -ge 379893 } { return 'net452' }
                { $_ -ge 378675 } { return 'net451' }
                { $_ -ge 378389 } { return 'net45' }
                default { return 'net48' }
            }
        }
        return "net$($version.Major)$($version.Minor)"
    }
}
function Get-NugetPackageAvailableTFMs {
    [CmdletBinding()]
    [OutputType([NuGetFramework[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath
    )
    $LibPath = Join-Path $PackagePath 'lib'
    if (-not (Test-Path -Path $LibPath -PathType Container)) {
        $Script:NugetLogger.Warn("包目录中未找到 lib 文件夹: $PackagePath")
        return @()
    }
    $TfmFolders = Get-ChildItem -Path $LibPath -Directory |
        Where-Object { $_.Name -notmatch '^_' } |
        ForEach-Object { $_.Name }
    if ($TfmFolders.Count -eq 0) {
        $Script:NugetLogger.Warn("lib 目录下未找到 TFM 子文件夹: $LibPath")
        return @()
    }
    $Frameworks = [System.Collections.Generic.List[NuGetFramework]]::new()
    foreach ($folder in $TfmFolders) {
        try {
            $fx = ConvertTo-NuGetFramework -FrameworkString $folder
            if (-not $fx.IsUnsupported()) {
                $Frameworks.Add($fx)
            }
            else {
                $Script:NugetLogger.Warn("跳过无法识别的 TFM 文件夹: $folder")
            }
        }
        catch {
            $Script:NugetLogger.Warn("解析 TFM 文件夹失败: $folder, 错误: $($_.Exception.Message)")
        }
    }
    return $Frameworks.ToArray()
}
function Resolve-NugetPackageTFMPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,
        [Parameter(Mandatory = $false)]
        [string]$TargetFramework
    )
    $TargetFxString = if ($TargetFramework) { $TargetFramework } else { Get-CurrentRuntimeFramework }
    $TargetFx = ConvertTo-NuGetFramework -FrameworkString $TargetFxString
    $Script:NugetLogger.Info("目标框架: $TargetFxString -> $(ConvertTo-NuGetFrameworkShortName $TargetFx)")
    $AvailableFxs = Get-NugetPackageAvailableTFMs -PackagePath $PackagePath
    if ($AvailableFxs.Count -eq 0) {
        $Script:NugetLogger.Warn("包未提供任何可识别的 TFM 程序集")
        return $null
    }
    $Script:NugetLogger.Info("包可用 TFM: $($AvailableFxs.ForEach({ ConvertTo-NuGetFrameworkShortName $_ }) -join ', ')")
    $BestMatch = Get-NearestNuGetFramework -Target $TargetFx -Candidates $AvailableFxs
    if (-not $BestMatch) {
        $Script:NugetLogger.Warn("未找到与 $TargetFxString 兼容的 TFM")
        return $null
    }
    $BestMatchFolder = ConvertTo-NuGetFrameworkShortName -Framework $BestMatch
    $Script:NugetLogger.Info("最佳 TFM 匹配: $BestMatchFolder")
    $MatchedLibPath = Join-Path $PackagePath 'lib' $BestMatchFolder
    if (-not (Test-Path -Path $MatchedLibPath -PathType Container)) {
        $OriginalFolder = Get-ChildItem -Path (Join-Path $PackagePath 'lib') -Directory |
            Where-Object { (ConvertTo-NuGetFramework -FrameworkString $_.Name -ErrorAction SilentlyContinue).Equals($BestMatch) } |
            Select-Object -First 1
        if ($OriginalFolder) {
            $MatchedLibPath = $OriginalFolder.FullName
        }
        else {
            $Script:NugetLogger.Error("匹配的 TFM 目录不存在: $MatchedLibPath")
            return $null
        }
    }
    return $MatchedLibPath
}
function Import-NugetAssemblies {
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibPath,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    if (-not (Test-Path -Path $LibPath -PathType Container)) {
        throw "程序集目录不存在: $LibPath"
    }
    $DllFiles = Get-ChildItem -Path $LibPath -Filter '*.dll' -File
    if ($DllFiles.Count -eq 0) {
        $Script:NugetLogger.Warn("目录中未找到 .dll 文件: $LibPath")
        return @()
    }
    $NewlyLoaded = [System.Collections.Generic.List[System.Reflection.Assembly]]::new()
    foreach ($dll in $DllFiles) {
        $DllPath = $dll.FullName
        if (-not $Force -and $Script:ImportedAssemblies.ContainsKey($DllPath)) {
            $Script:NugetLogger.Info("程序集已加载，跳过: $($dll.Name)")
            continue
        }
        try {
            $Script:NugetLogger.Info("加载程序集: $($dll.Name)")
            $AssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($DllPath)
            $ExistingAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { -not $_.IsDynamic -and $_.GetName().Name -eq $AssemblyName.Name } |
                Select-Object -First 1
            if ($ExistingAssembly -and -not $Force) {
                $Script:NugetLogger.Info("程序集已存在于 AppDomain，跳过加载: $($AssemblyName.Name)")
                $Script:ImportedAssemblies[$DllPath] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                continue
            }
            $LoadedAssembly = [System.Reflection.Assembly]::LoadFrom($DllPath)
            $Script:ImportedAssemblies[$DllPath] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $NewlyLoaded.Add($LoadedAssembly)
            $Script:NugetLogger.Info("程序集加载成功: $($AssemblyName.Name) v$($AssemblyName.Version)")
        }
        catch {
            $Script:NugetLogger.Error("加载程序集失败: $($dll.Name), 错误: $($_.Exception.Message)")
        }
    }
    return $NewlyLoaded.ToArray()
}
function Import-NugetPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LibraryPath,
        [Parameter(Mandatory = $false)]
        [string]$Version,
        [Parameter(Mandatory = $false)]
        [string]$TargetFramework,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    try {
        if (-not (Test-Path -Path $LibraryPath -PathType Container)) {
            throw "包库路径不存在: $LibraryPath"
        }
        $LibraryPath = (Get-Item -Path $LibraryPath).FullName
        $IdNormalized = $Id.Trim().ToLowerInvariant()
        $Manifest = Read-NugetPackageLibraryManifest -Path $LibraryPath
        if (-not $Manifest.Packages.ContainsKey($IdNormalized)) {
            throw "包未安装: $Id。请先使用 Install-NugetPackage 安装。"
        }
        $InstalledVersions = $Manifest.Packages[$IdNormalized]
        $ResolvedVersion = $null
        if ($Version) {
            $VersionNormalized = $Version.Trim().ToLowerInvariant()
            if (-not $InstalledVersions.ContainsKey($VersionNormalized)) {
                throw "包版本未安装: $Id v$Version"
            }
            $ResolvedVersion = $VersionNormalized
        }
        else {
            $SortedVersions = $InstalledVersions.Keys |
                ForEach-Object { [NuGetVersion]::new($_) } |
                Sort-Object -Descending
            if ($SortedVersions.Count -eq 0) {
                throw "包 $Id 无已安装版本"
            }
            $ResolvedVersion = $SortedVersions[0].NormalizedVersion
            $Script:NugetLogger.Info("自动选择最新版本: $ResolvedVersion")
        }
        $TargetFxString = if ($TargetFramework) { $TargetFramework } else { Get-CurrentRuntimeFramework }
        $ImportKey = "$IdNormalized|$ResolvedVersion|$TargetFxString"
        if (-not $Force -and $Script:ImportedPackages.ContainsKey($ImportKey)) {
            $Script:NugetLogger.Info("包已导入，跳过（幂等）: $ImportKey")
            return [PSCustomObject]@{
                PackageId         = $IdNormalized
                Version           = $ResolvedVersion
                TargetFramework   = $TargetFxString
                MatchedTFM        = $Script:ImportedPackages[$ImportKey].MatchedTFM
                LoadedAssemblies  = @()
                IsCached          = $true
                ImportTime        = $Script:ImportedPackages[$ImportKey].ImportTime
            }
        }
        $PackagePath = Join-Path $LibraryPath $IdNormalized $ResolvedVersion
        if (-not (Test-Path -Path $PackagePath -PathType Container)) {
            throw "包目录不存在，可能已被手动删除: $PackagePath"
        }
        $Script:NugetLogger.Info("开始加载包: $IdNormalized v$ResolvedVersion")
        $MatchedLibPath = Resolve-NugetPackageTFMPath -PackagePath $PackagePath -TargetFramework $TargetFxString
        if (-not $MatchedLibPath) {
            throw "无法为 $IdNormalized v$ResolvedVersion 找到与 $TargetFxString 兼容的程序集"
        }
        $Script:NugetLogger.Info("匹配的程序集路径: $MatchedLibPath")
        $LoadedAssemblies = Import-NugetAssemblies -LibPath $MatchedLibPath -Force:$Force
        $MatchedTfmFolder = Split-Path $MatchedLibPath -Leaf
        $ImportTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Script:ImportedPackages[$ImportKey] = @{
            MatchedTFM  = $MatchedTfmFolder
            ImportTime  = $ImportTime
            PackagePath = $PackagePath
        }
        $Script:NugetLogger.Info("包加载完成: $IdNormalized v$ResolvedVersion -> $MatchedTfmFolder, 加载了 $($LoadedAssemblies.Count) 个程序集")
        return [PSCustomObject]@{
            PackageId         = $IdNormalized
            Version           = $ResolvedVersion
            TargetFramework   = $TargetFxString
            MatchedTFM        = $MatchedTfmFolder
            LoadedAssemblies  = $LoadedAssemblies
            IsCached          = $false
            ImportTime        = $ImportTime
        }
    }
    catch {
        $Script:NugetLogger.Error("加载包失败: $($_.Exception.Message)")
        throw
    }
}
function Get-ImportedNugetPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id
    )
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($key in $Script:ImportedPackages.Keys) {
        $Parts = $key -split '\|'
        $PkgId = $Parts[0]
        $PkgVersion = $Parts[1]
        $PkgTFM = $Parts[2]
        if ($Id -and $PkgId -ne $Id.Trim().ToLowerInvariant()) { continue }
        $Results.Add([PSCustomObject]@{
            PackageId       = $PkgId
            Version         = $PkgVersion
            TargetFramework = $PkgTFM
            MatchedTFM      = $Script:ImportedPackages[$key].MatchedTFM
            ImportTime      = $Script:ImportedPackages[$key].ImportTime
            PackagePath     = $Script:ImportedPackages[$key].PackagePath
        })
    }
    return $Results.ToArray()
}
function Reset-ImportedNugetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id
    )
    if ($Id) {
        $IdNormalized = $Id.Trim().ToLowerInvariant()
        $KeysToRemove = $Script:ImportedPackages.Keys | Where-Object { $_ -like "$IdNormalized|*" }
        foreach ($k in $KeysToRemove) {
            $Script:ImportedPackages.Remove($k)
        }
        $Script:NugetLogger.Info("已清除包 $IdNormalized 的导入记录")
    }
    else {
        $Script:ImportedPackages.Clear()
        $Script:NugetLogger.Info("已清除全部导入记录")
    }
}
$Script:ModuleBuilders["Nuget"] = {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $Script:NugetLogger.Info("配置: $($Config | ConvertTo-Json -Depth 3)")
    $PackagesPath = $Config["PackagesPath"]
    if (-not [System.IO.Path]::IsPathRooted($PackagesPath)) {
        $PackagesPath = Join-Path (Get-Location) $PackagesPath
    }
    if (-not (Test-Path -Path $PackagesPath -PathType Container)) {
        $null = New-Item -Path $PackagesPath -ItemType Directory
        $LibraryPath = New-NugetPackageLibraryManifest -Path $PackagesPath
    }
    else {
        $LibraryPath = (Get-Item -Path $PackagesPath).FullName
    }
    $Source = New-NugetSource -Url $Config['Sources'][0]
    foreach($Pack in $Config['Packs']){
        $Id = $Pack.Keys[0]
        $Ver = $Pack[$Pack.Keys[0]]
        $null = Install-NugetPackage -Source $Source -Id $Id -Version $Ver -LibraryPath $LibraryPath
    }
    return @([InfinityModule]@{
        Name         = 'Builtin.Nuget'
        Code         = [System.Collections.Generic.List[string]]::new()
        Requires     = [System.Collections.Generic.List[string]]::new()
        SourceInfo   = Get-Item -Path $PSCommandPath
        LineMappings = [System.Collections.Generic.Dictionary[int, int]]::new()
    })
}
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
        if (-not (Test-Path -Path $CacheFolder -PathType Container)) {
            $Script:BuildLogger.Info("创建缓存目录: $CacheFolder")
            if (-not (New-Item -Path $CacheFolder -ItemType Directory -Force)) {
                $Script:BuildLogger.Error("无法创建缓存目录: $CacheFolder")
                throw "无法创建缓存目录: $CacheFolder"
            }
        }
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
        if ($ExtraConfig) {
            $Script:BuildLogger.Info("应用额外配置: $($ExtraConfig.Keys -join ', ')")
            foreach ($Key in $ExtraConfig.Keys) {
                $BuildSteps[$Key] = $ExtraConfig[$Key]
            }
        }
        $AllModules = [System.Collections.Generic.List[InfinityModule]]::new()
        foreach ($StepName in $BuildSteps.Keys) {
            if (-not $Script:ModuleBuilders.ContainsKey($StepName)) {
                $Script:BuildLogger.Warn("未注册的构建步骤: $StepName，已跳过")
                continue
            }
            $StepConfig = $BuildSteps[$StepName]
            $Script:BuildLogger.MeasureScope("构建步骤: $StepName", {
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
        if ($Script:BuildConfig.ContainsKey("Boot")){
            if ($Script:BuildConfig["Boot"].ContainsKey("Require")){
                $Script:BuildLogger.Info("剔除未使用模块...")
                $SortedModules = Select-InfinityModuleReachable -RootNames @("Builtin.Boot") -Modules $SortedModules
            }
        }
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
Invoke-Main @args
