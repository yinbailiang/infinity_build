##Module Core.Parser
##Import Core.Logger
##Import Core.Types

#region 模块解析

<#
.SYNOPSIS
    解析 .psm1 源文件为 InfinityModule 对象。
.DESCRIPTION
    读取指定路径的 .psm1 模块源文件，执行以下处理：
    - 从注释中提取 ##Module / ##Import 预处理指令
    - 剥离所有注释（单行、多行、块注释）
    - 处理 #infb: rm 行移除指令（用于剔除调试代码）
    - 保留 here-string 内部的空白行
    - 生成行号映射（Code 行号 -> 源文件行号）
#>
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

    # 解析脚本，获取 tokens（包含注释）并忽略语法错误（errors 只做记录）
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

    # ---------- 1. 收集字符串 token（用于判断空白行是否位于字符串内部） ----------
    $stringTokens = $tokens | Where-Object {
        $_.Kind -eq 'StringExpandable' -or $_.Kind -eq 'StringLiteral' -or
        $_.Kind -eq 'HereStringExpandable' -or $_.Kind -eq 'HereStringLiteral'
    }

    # ---------- 2. 从注释 token 中提取预处理指令 ----------
    $commentTokens = $tokens | Where-Object { $_.Kind -eq 'Comment' }
    foreach ($comment in $commentTokens) {
        # 注释文本可能跨多行（多行注释），按行处理
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

    # ---------- 2.5. 提取 #infb: rm 行末移除指令 ----------
    $removeLines = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($comment in $commentTokens) {
        # 只处理单行注释（行注释 #...），避免误判多行块注释内的内容
        if ($comment.Extent.StartLineNumber -eq $comment.Extent.EndLineNumber) {
            $trimmedComment = $comment.Text.Trim()
            if ($trimmedComment -match '^#\s*infb\s*:\s*rm\b') {
                $lineToRemove = $comment.Extent.StartLineNumber
                [void]$removeLines.Add($lineToRemove)
                $Script:BuildLogger.Debug("  #infb:rm 移除行: $lineToRemove")
            }
        }
    }

    # ---------- 3. 构建每行需移除的注释区间（基于 token 位置） ----------
    # 使用 Dictionary<int, List<区间>> ，区间为 [startColumn, endColumn) 半开区间（1-based）
    $lineCommentRanges = @{}
    foreach ($comment in $commentTokens) {
        $extent = $comment.Extent
        $startLine = $extent.StartLineNumber
        $startCol  = $extent.StartColumnNumber
        $endLine   = $extent.EndLineNumber
        $endCol    = $extent.EndColumnNumber   # 注释结束位置的下一列

        if ($startLine -eq $endLine) {
            # 单行注释
            if (-not $lineCommentRanges.ContainsKey($startLine)) {
                $lineCommentRanges[$startLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$startLine].Add([PSCustomObject]@{Start = $startCol; End = $endCol})
        }
        else {
            # 多行注释：
            # 起始行：从 startCol 到行尾（以极大值表示）
            if (-not $lineCommentRanges.ContainsKey($startLine)) {
                $lineCommentRanges[$startLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$startLine].Add([PSCustomObject]@{Start = $startCol; End = [int]::MaxValue})

            # 中间完整行：整行注释
            for ($line = $startLine + 1; $line -lt $endLine; $line++) {
                if (-not $lineCommentRanges.ContainsKey($line)) {
                    $lineCommentRanges[$line] = [System.Collections.Generic.List[object]]::new()
                }
                $lineCommentRanges[$line].Add([PSCustomObject]@{Start = 1; End = [int]::MaxValue})
            }

            # 结束行：从列1到 endCol
            if (-not $lineCommentRanges.ContainsKey($endLine)) {
                $lineCommentRanges[$endLine] = [System.Collections.Generic.List[object]]::new()
            }
            $lineCommentRanges[$endLine].Add([PSCustomObject]@{Start = 1; End = $endCol})
        }
    }

    # ---------- 4. 按行剔除注释，构建 Code 与行映射 ----------
    [string[]]$Lines = $FileContent -split '\r?\n'
    for ([int]$i = 0; $i -lt $Lines.Count; ++$i) {
        $lineNum = $i + 1
        $lineText = $Lines[$i]
        $ranges = $lineCommentRanges[$lineNum]

        $filteredLine = if ($ranges) {
            # 合并/排序区间，移除注释部分
            $sorted = $ranges | Sort-Object Start
            $result = ''
            $currentPos = 1
            foreach ($range in $sorted) {
                $start = $range.Start
                $end   = [Math]::Min($range.End, $lineText.Length + 1)  # 限制在行范围内
                if ($start -gt $currentPos) {
                    $result += $lineText.Substring($currentPos - 1, $start - $currentPos)
                }
                $currentPos = $end
            }
            # 最后一段
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
            # 检查该空白行是否位于多行字符串（如 here-string）内部
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

        # 跳过 #infb: rm 标记的移除行
        if ($removeLines.Contains($lineNum)) {
            continue
        }

        $InfinityModule.Code.Add($trimmedLine)
        $InfinityModule.LineMappings[$InfinityModule.Code.Count] = $lineNum
    }

    $Script:BuildLogger.Info("模块 '$($InfinityModule.Name)' 读取完成: $($InfinityModule.Code.Count) 行代码, $($InfinityModule.Requires.Count) 个依赖")
    return $InfinityModule
}
#endregion
