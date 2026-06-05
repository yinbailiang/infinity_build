##Module Core.Types

<#
.NOTES
    Infinity Build 核心数据类型定义。
    包含：InfinityModule、InfinityProgramSegment、ResourceFileInfo、ResourceFileHash。
#>

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