##Module Core.Types

#region 类型定义

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

#endregion
