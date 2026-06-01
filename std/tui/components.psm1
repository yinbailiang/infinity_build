##Module Std.Tui.Components

<#
.NOTES
    Name: infinity_tui_components
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    TUI 组件模块
.DESCRIPTION
    提供常用的终端 UI 组件：
    1. 进度条（Progress Bar）
    2. 旋转指示器（Spinner）
    3. 表格（Table）
    4. 列表（List）
    5. 树形结构（Tree）
    6. 状态栏（Status Bar）
    7. 通知横幅（Banner / Toast）
#>

#region 进度条

<#
.SYNOPSIS
    TUI 进度条类
.DESCRIPTION
    可自定义宽度、样式、颜色。支持确定模式和不确定模式（脉冲）。
#>
class TuiProgressBar {
    [int]$Total
    [int]$Current
    [int]$Width
    [TuiStyle]$CompleteStyle
    [TuiStyle]$RemainingStyle
    [TuiStyle]$TextStyle
    [string]$CompleteChar
    [string]$RemainingChar
    [string]$Prefix
    [string]$Suffix

    TuiProgressBar([int]$Total, [int]$Width) {
        $this.Total = [Math]::Max(1, $Total)
        $this.Current = 0
        $this.Width = [Math]::Max(10, $Width)
        $this.CompleteStyle = [TuiStyle]::new([TuiColor]::Black, [TuiBgColor]::BrightGreen)
        $this.RemainingStyle = [TuiStyle]::new([TuiColor]::BrightBlack)
        $this.TextStyle = [TuiStyle]::Default
        $this.CompleteChar = "█"
        $this.RemainingChar = "░"
        $this.Prefix = "["
        $this.Suffix = "]"
    }

    [void] SetProgress([int]$Current) {
        $this.Current = [Math]::Min($Current, $this.Total)
    }

    [void] Increment([int]$Amount = 1) {
        $this.Current = [Math]::Min($this.Current + $Amount, $this.Total)
    }

    [string] Render() {
        $ratio = $this.Current / $this.Total
        $barWidth = $this.Width - $this.Prefix.Length - $this.Suffix.Length
        $filled = [Math]::Floor($barWidth * $ratio)
        $empty = $barWidth - $filled

        $percent = [Math]::Floor($ratio * 100)

        $bar = $this.Prefix
        $bar += $this.CompleteStyle.ToAnsiPrefix() + ($this.CompleteChar * $filled)
        $bar += $this.RemainingStyle.ToAnsiPrefix() + ($this.RemainingChar * $empty)
        $bar += [TuiAnsi]::Reset
        $bar += $this.Suffix
        $bar += " $percent% ($($this.Current)/$($this.Total))"

        return $bar
    }

    [void] Write() {
        Write-Host -NoNewline "`r$([TuiAnsi]::EraseLine)$($this.Render())"
    }

    [void] Finish() {
        $this.Current = $this.Total
        $this.Write()
        Write-Host ""  # 换行
    }
}

<#
.SYNOPSIS
    创建一个进度条并返回控制对象
#>
function New-TuiProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Total,

        [int]$Width = 40,
        [string]$Prefix = "[",
        [string]$Suffix = "]",
        [string]$CompleteChar = "█",
        [string]$RemainingChar = "░",
        [TuiColor]$CompleteColor = [TuiColor]::BrightGreen,
        [TuiColor]$RemainingColor = [TuiColor]::BrightBlack
    )

    $bar = [TuiProgressBar]::new($Total, $Width)
    $bar.Prefix = $Prefix
    $bar.Suffix = $Suffix
    $bar.CompleteChar = $CompleteChar
    $bar.RemainingChar = $RemainingChar
    $bar.CompleteStyle = [TuiStyle]::new($CompleteColor)
    $bar.RemainingStyle = [TuiStyle]::new($RemainingColor)

    return $bar
}

#endregion

#region 旋转指示器 (Spinner)

<#
.SYNOPSIS
    TUI 旋转动画类
.DESCRIPTION
    在后台运行脚本块期间显示旋转动画。
#>
class TuiSpinner {
    hidden [string[]]$Frames
    hidden [int]$FrameIndex
    hidden [System.Threading.CancellationTokenSource]$Cts
    [string]$Message
    [TuiStyle]$Style
    [int]$IntervalMs
    hidden [System.Threading.Tasks.Task]$AnimationTask

    TuiSpinner() {
        $this.Frames = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
        $this.FrameIndex = 0
        $this.Message = ""
        $this.Style = [TuiStyle]::Info
        $this.IntervalMs = 80
        $this.Cts = $null
        $this.AnimationTask = $null
    }

    TuiSpinner([string[]]$Frames) {
        $this.Frames = $Frames
        $this.FrameIndex = 0
        $this.Message = ""
        $this.Style = [TuiStyle]::Info
        $this.IntervalMs = 80
    }

    [void] Start([string]$Message) {
        $this.Message = $Message
        $this.Cts = [System.Threading.CancellationTokenSource]::new()
        $token = $this.Cts.Token

        # 隐藏光标
        Hide-TuiCursor

        $this.AnimationTask = [System.Threading.Tasks.Task]::Run({
            while (-not $token.IsCancellationRequested) {
                $frame = $this.Frames[$this.FrameIndex % $this.Frames.Count]
                $prefix = $this.Style.ToAnsiPrefix()
                Write-Host -NoNewline "`r$([TuiAnsi]::EraseLine)$prefix$frame [TuiAnsi]::Reset $($this.Message)"
                $this.FrameIndex++

                try {
                    [System.Threading.Tasks.Task]::Delay($this.IntervalMs, $token).Wait()
                } catch {
                    break
                }
            }
        }, $token)
    }

    [void] Stop([string]$FinalMessage) {
        if ($this.Cts) {
            $this.Cts.Cancel()
        }
        if ($this.AnimationTask) {
            try {
                $this.AnimationTask.Wait(500)
            } catch {}
        }
        Show-TuiCursor

        if ($FinalMessage) {
            Write-Host "`r$([TuiAnsi]::EraseLine)$FinalMessage"
        } else {
            Write-Host "`r$([TuiAnsi]::EraseLine)"
        }
    }

    [void] Success([string]$Message) {
        $icon = [TuiStyle]::Success.ToAnsiPrefix() + "✔" + [TuiAnsi]::Reset
        $this.Stop("$icon $Message")
    }

    [void] Error([string]$Message) {
        $icon = [TuiStyle]::Error.ToAnsiPrefix() + "✘" + [TuiAnsi]::Reset
        $this.Stop("$icon $Message")
    }

    [void] Warn([string]$Message) {
        $icon = [TuiStyle]::Warning.ToAnsiPrefix() + "⚠" + [TuiAnsi]::Reset
        $this.Stop("$icon $Message")
    }

    [void] Info([string]$Message) {
        $icon = [TuiStyle]::Info.ToAnsiPrefix() + "ℹ" + [TuiAnsi]::Reset
        $this.Stop("$icon $Message")
    }
}

#endregion

#region 表格

<#
.SYNOPSIS
    TUI 表格列定义
#>
class TuiColumn {
    [string]$Name
    [int]$Width
    [string]$Align        # Left, Center, Right
    [TuiStyle]$HeaderStyle
    [TuiStyle]$CellStyle

    TuiColumn([string]$Name, [int]$Width) {
        $this.Name = $Name
        $this.Width = [Math]::Max($Name.Length + 2, $Width)
        $this.Align = "Left"
        $this.HeaderStyle = [TuiStyle]::new([TuiColor]::BrightWhite, $null, [TuiTextEffect]::Bold)
        $this.CellStyle = [TuiStyle]::Default
    }

    TuiColumn([string]$Name, [int]$Width, [string]$Align) {
        $this.Name = $Name
        $this.Width = [Math]::Max($Name.Length + 2, $Width)
        $this.Align = $Align
        $this.HeaderStyle = [TuiStyle]::new([TuiColor]::BrightWhite, $null, [TuiTextEffect]::Bold)
        $this.CellStyle = [TuiStyle]::Default
    }
}

<#
.SYNOPSIS
    TUI 表格类
.DESCRIPTION
    支持列定义、边框样式、行颜色交替。
#>
class TuiTable {
    [System.Collections.Generic.List[TuiColumn]]$Columns
    [System.Collections.Generic.List[string[]]]$Rows
    [TuiBorder]$Border
    [TuiStyle]$BorderStyle
    [TuiStyle]$AltRowStyle
    [bool]$ShowHeader
    [string]$Title

    TuiTable() {
        $this.Columns = [System.Collections.Generic.List[TuiColumn]]::new()
        $this.Rows = [System.Collections.Generic.List[string[]]]::new()
        $this.Border = [TuiBorder]::Single
        $this.BorderStyle = [TuiStyle]::Muted
        $this.AltRowStyle = [TuiStyle]::new([TuiColor]::BrightBlack)
        $this.ShowHeader = $true
        $this.Title = $null
    }

    [void] AddColumn([TuiColumn]$Column) {
        $this.Columns.Add($Column)
    }

    [void] AddColumn([string]$Name, [int]$Width) {
        $this.Columns.Add([TuiColumn]::new($Name, $Width))
    }

    [void] AddColumn([string]$Name, [int]$Width, [string]$Align) {
        $this.Columns.Add([TuiColumn]::new($Name, $Width, $Align))
    }

    [void] AddRow([string[]]$Cells) {
        if ($Cells.Count -ne $this.Columns.Count) {
            throw "行单元格数量 ($($Cells.Count)) 与列数 ($($this.Columns.Count)) 不匹配"
        }
        $this.Rows.Add($Cells)
    }

    [string] FormatCell([string]$Text, [int]$Width, [string]$Align) {
        if ($Text.Length -gt $Width - 2) {
            $Text = $Text.Substring(0, $Width - 3) + "…"
        }
        switch ($Align) {
            "Center" {
                $padding = $Width - $Text.Length
                $left = [Math]::Floor($padding / 2)
                $right = $padding - $left
                return (" " * $left) + $Text + (" " * $right)
            }
            "Right" {
                return $Text.PadLeft($Width)
            }
            default {
                return $Text.PadRight($Width)
            }
        }
    }

    [string[]] Render() {
        if ($this.Columns.Count -eq 0) { return @() }

        $lines = [System.Collections.Generic.List[string]]::new()
        $totalWidth = ($this.Columns | ForEach-Object { $_.Width } | Measure-Object -Sum).Sum + $this.Columns.Count + 1

        $borderOn = $this.BorderStyle.ToAnsiPrefix()
        $borderOff = [TuiAnsi]::Reset

        # 顶部边框
        if ($this.Border -ne [TuiBorder]::None) {
            $topLine = $borderOn + $this.Border.TopLeft
            for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                $topLine += $this.Border.Horizontal * $this.Columns[$i].Width
                if ($i -lt $this.Columns.Count - 1) {
                    $topLine += $this.Border.TeeDown
                }
            }
            $topLine += $this.Border.TopRight + $borderOff
            $lines.Add($topLine)
        }

        # 标题行（可选）
        if ($this.Title) {
            $titleLine = $borderOn + $this.Border.Vertical + $borderOff
            $titleText = $this.Title
            $availableWidth = $totalWidth - 2
            if ($titleText.Length -gt $availableWidth) {
                $titleText = $titleText.Substring(0, $availableWidth - 3) + "…"
            }
            $titlePadding = [Math]::Floor(($availableWidth - $titleText.Length) / 2)
            $titleLine += (" " * $titlePadding) + $titleText
            $titleLine += " " * ($availableWidth - $titlePadding - $titleText.Length)
            $titleLine += $borderOn + $this.Border.Vertical + $borderOff
            $lines.Add($titleLine)

            # 标题与表头之间的分隔线
            if ($this.ShowHeader) {
                $sepLine = $borderOn + $this.Border.TeeRight
                for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                    $sepLine += $this.Border.Horizontal * $this.Columns[$i].Width
                    if ($i -lt $this.Columns.Count - 1) {
                        $sepLine += $this.Border.Cross
                    }
                }
                $sepLine += $this.Border.TeeLeft + $borderOff
                $lines.Add($sepLine)
            }
        }

        # 表头
        if ($this.ShowHeader) {
            $headerLine = $borderOn + $this.Border.Vertical + $borderOff
            for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                $col = $this.Columns[$i]
                $cellText = $this.FormatCell($col.Name, $col.Width, $col.Align)
                $headerLine += $col.HeaderStyle.ToAnsiPrefix() + $cellText + [TuiAnsi]::Reset
                $headerLine += $borderOn + $this.Border.Vertical + $borderOff
            }
            $lines.Add($headerLine)

            # 表头分隔线
            $sepLine = $borderOn + $this.Border.TeeRight
            for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                $sepLine += $this.Border.Horizontal * $this.Columns[$i].Width
                if ($i -lt $this.Columns.Count - 1) {
                    $sepLine += $this.Border.Cross
                }
            }
            $sepLine += $this.Border.TeeLeft + $borderOff
            $lines.Add($sepLine)
        }

        # 数据行
        for ($r = 0; $r -lt $this.Rows.Count; $r++) {
            $row = $this.Rows[$r]
            $isAlt = ($r % 2 -eq 1) -and ($this.AltRowStyle -ne $null)

            $rowLine = $borderOn + $this.Border.Vertical + $borderOff
            for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                $col = $this.Columns[$i]
                $cellText = $this.FormatCell($row[$i], $col.Width, $col.Align)

                if ($isAlt) {
                    $rowLine += $this.AltRowStyle.ToAnsiPrefix() + $cellText + [TuiAnsi]::Reset
                } else {
                    $rowLine += $col.CellStyle.ToAnsiPrefix() + $cellText + [TuiAnsi]::Reset
                }
                $rowLine += $borderOn + $this.Border.Vertical + $borderOff
            }
            $lines.Add($rowLine)
        }

        # 底部边框
        if ($this.Border -ne [TuiBorder]::None) {
            $bottomLine = $borderOn + $this.Border.BottomLeft
            for ($i = 0; $i -lt $this.Columns.Count; $i++) {
                $bottomLine += $this.Border.Horizontal * $this.Columns[$i].Width
                if ($i -lt $this.Columns.Count - 1) {
                    $bottomLine += $this.Border.TeeUp
                }
            }
            $bottomLine += $this.Border.BottomRight + $borderOff
            $lines.Add($bottomLine)
        }

        return $lines.ToArray()
    }

    [void] Write() {
        $lines = $this.Render()
        foreach ($line in $lines) {
            Write-Host $line
        }
    }
}

#endregion

#region 列表

<#
.SYNOPSIS
    TUI 列表类
#>
class TuiList {
    [System.Collections.Generic.List[string]]$Items
    [string]$Bullet
    [TuiStyle]$BulletStyle
    [TuiStyle]$ItemStyle
    [TuiStyle]$AltRowStyle
    [int]$Indent

    TuiList() {
        $this.Items = [System.Collections.Generic.List[string]]::new()
        $this.Bullet = "●"
        $this.BulletStyle = [TuiStyle]::Info
        $this.ItemStyle = [TuiStyle]::Default
        $this.AltRowStyle = $null
        $this.Indent = 2
    }

    [void] Add([string]$Item) {
        $this.Items.Add($Item)
    }

    [void] AddRange([string[]]$Items) {
        $this.Items.AddRange($Items)
    }

    [string[]] Render() {
        $lines = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $this.Items.Count; $i++) {
            $prefix = $this.BulletStyle.ToAnsiPrefix() + $this.Bullet + [TuiAnsi]::Reset
            $indent = " " * $this.Indent
            $content = $this.ItemStyle.ToAnsiPrefix() + $this.Items[$i] + [TuiAnsi]::Reset

            if ($this.AltRowStyle -and ($i % 2 -eq 1)) {
                $lines.Add($indent + $prefix + " " + $this.AltRowStyle.ToAnsiPrefix() + $this.Items[$i] + [TuiAnsi]::Reset)
            } else {
                $lines.Add($indent + $prefix + " " + $content)
            }
        }
        return $lines.ToArray()
    }

    [void] Write() {
        foreach ($line in $this.Render()) {
            Write-Host $line
        }
    }
}

#endregion

#region 树形结构

<#
.SYNOPSIS
    TUI 树节点
#>
class TuiTreeNode {
    [string]$Label
    [TuiStyle]$Style
    [System.Collections.Generic.List[TuiTreeNode]]$Children
    [bool]$Expanded

    TuiTreeNode([string]$Label) {
        $this.Label = $Label
        $this.Style = [TuiStyle]::Default
        $this.Children = [System.Collections.Generic.List[TuiTreeNode]]::new()
        $this.Expanded = $true
    }

    [void] AddChild([TuiTreeNode]$Node) {
        $this.Children.Add($Node)
    }

    [TuiTreeNode] AddChild([string]$Label) {
        $node = [TuiTreeNode]::new($Label)
        $this.Children.Add($node)
        return $node
    }
}

<#
.SYNOPSIS
    TUI 树形渲染器
#>
class TuiTree {
    [TuiTreeNode]$Root
    [string]$BranchChar
    [string]$LastBranchChar
    [string]$VerticalChar
    [string]$IndentChar
    [TuiStyle]$BranchStyle

    TuiTree([TuiTreeNode]$Root) {
        $this.Root = $Root
        $this.BranchChar = "├── "
        $this.LastBranchChar = "└── "
        $this.VerticalChar = "│   "
        $this.IndentChar = "    "
        $this.BranchStyle = [TuiStyle]::Muted
    }

    [string[]] Render() {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add($this.Root.Style.ToAnsiPrefix() + $this.Root.Label + [TuiAnsi]::Reset)
        if ($this.Root.Expanded) {
            $this.RenderNode($this.Root, "", $lines)
        }
        return $lines.ToArray()
    }

    hidden [void] RenderNode(
        [TuiTreeNode]$Node,
        [string]$Prefix,
        [System.Collections.Generic.List[string]]$Lines
    ) {
        $count = $Node.Children.Count
        for ($i = 0; $i -lt $count; $i++) {
            $child = $Node.Children[$i]
            $isLast = ($i -eq $count - 1)
            $connector = if ($isLast) { $this.LastBranchChar } else { $this.BranchChar }
            $branchPrefix = $this.BranchStyle.ToAnsiPrefix() + $Prefix + $connector + [TuiAnsi]::Reset
            $labelText = $child.Style.ToAnsiPrefix() + $child.Label + [TuiAnsi]::Reset
            $Lines.Add($branchPrefix + $labelText)

            if ($child.Expanded -and $child.Children.Count -gt 0) {
                $newPrefix = $Prefix + (if ($isLast) { $this.IndentChar } else { $this.VerticalChar })
                $this.RenderNode($child, $newPrefix, $Lines)
            }
        }
    }

    [void] Write() {
        foreach ($line in $this.Render()) {
            Write-Host $line
        }
    }
}

#endregion

#region 状态栏

<#
.SYNOPSIS
    TUI 状态栏
.DESCRIPTION
    在终端底部显示固定状态栏，左侧显示主信息，右侧显示辅助信息。
#>
class TuiStatusBar {
    [string]$LeftText
    [string]$RightText
    [TuiStyle]$LeftStyle
    [TuiStyle]$RightStyle
    [TuiStyle]$BackgroundStyle
    [int]$Height
    [string]$Separator

    TuiStatusBar() {
        $this.LeftText = ""
        $this.RightText = ""
        $this.LeftStyle = [TuiStyle]::new([TuiColor]::BrightWhite, [TuiBgColor]::Blue)
        $this.RightStyle = [TuiStyle]::new([TuiColor]::BrightWhite, [TuiBgColor]::Blue)
        $this.BackgroundStyle = [TuiStyle]::new([TuiColor]::White, [TuiBgColor]::Blue)
        $this.Height = 1
        $this.Separator = " │ "
    }

    [string] Render() {
        $width = [TuiTerminal]::Width()
        $bgPrefix = $this.BackgroundStyle.ToAnsiPrefix()
        $reset = [TuiAnsi]::Reset

        $availableLeft = $width - $this.RightText.Length - $this.Separator.Length
        if ($availableLeft -lt 10) { $availableLeft = 10 }

        $leftDisplay = $this.LeftText
        if ($leftDisplay.Length -gt $availableLeft) {
            $leftDisplay = $leftDisplay.Substring(0, $availableLeft - 3) + "…"
        }

        $rightPadding = $width - $leftDisplay.Length - $this.Separator.Length - $this.RightText.Length
        if ($rightPadding -lt 0) { $rightPadding = 0 }

        $line = $bgPrefix
        $line += $leftDisplay
        $line += (" " * $rightPadding)
        $line += $this.Separator
        $line += $this.RightText
        $line += $reset

        return $line
    }

    [void] Write() {
        Write-Host $this.Render()
    }
}

#endregion

#region 通知横幅 (Banner/Toast)

<#
.SYNOPSIS
    通知横幅类型
#>
enum TuiBannerType {
    Info
    Success
    Warning
    Error
}

<#
.SYNOPSIS
    显示通知横幅
#>
function Write-TuiBanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [TuiBannerType]$Type = [TuiBannerType]::Info,
        [int]$Width = 60,
        [switch]$NoPrefix
    )

    $icon = switch ($Type) {
        ([TuiBannerType]::Info)    { "ℹ" }
        ([TuiBannerType]::Success) { "✔" }
        ([TuiBannerType]::Warning) { "⚠" }
        ([TuiBannerType]::Error)   { "✘" }
    }

    $style = switch ($Type) {
        ([TuiBannerType]::Info)    { [TuiStyle]::Info }
        ([TuiBannerType]::Success) { [TuiStyle]::Success }
        ([TuiBannerType]::Warning) { [TuiStyle]::Warning }
        ([TuiBannerType]::Error)   { [TuiStyle]::Error }
    }

    $bgStyle = switch ($Type) {
        ([TuiBannerType]::Info)    { [TuiStyle]::new([TuiColor]::BrightWhite, [TuiBgColor]::Blue) }
        ([TuiBannerType]::Success) { [TuiStyle]::new([TuiColor]::Black, [TuiBgColor]::BrightGreen, [TuiTextEffect]::Bold) }
        ([TuiBannerType]::Warning) { [TuiStyle]::new([TuiColor]::Black, [TuiBgColor]::BrightYellow, [TuiTextEffect]::Bold) }
        ([TuiBannerType]::Error)   { [TuiStyle]::new([TuiColor]::BrightWhite, [TuiBgColor]::Red, [TuiTextEffect]::Bold) }
    }

    $maxMsgWidth = $Width - 4  # 留出图标和边距

    $displayMsg = if ($NoPrefix) {
        $Message
    } else {
        " $icon $Message "
    }

    if ($displayMsg.Length -gt $Width) {
        $displayMsg = $displayMsg.Substring(0, $Width - 3) + "…"
    }

    $padding = $Width - $displayMsg.Length
    $leftPad = [Math]::Floor($padding / 2)
    $rightPad = $padding - $leftPad

    $line = (" " * $leftPad) + $displayMsg + (" " * $rightPad)

    Write-Host ""
    Write-Host ($bgStyle.ToAnsiPrefix() + $line + [TuiAnsi]::Reset)
    Write-Host ""
}

#endregion

#region 确认对话框

<#
.SYNOPSIS
    显示确认提示
.DESCRIPTION
    显示 [Y/n] 或 [y/N] 确认提示，返回布尔值。
#>
function Read-TuiConfirm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [switch]$DefaultYes
    )

    $prompt = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $style = [TuiStyle]::new([TuiColor]::BrightYellow, $null, [TuiTextEffect]::Bold)

    Write-Host -NoNewline "$($style.ToAnsiPrefix())? $Message $prompt $([TuiAnsi]::Reset)"

    $key = [Console]::ReadKey($true)
    Write-Host $key.KeyChar

    switch ($key.Key) {
        'Y'    { return $true }
        'N'    { return $false }
        'Enter' { return $DefaultYes }
        default { return -not $DefaultYes }
    }
}

#endregion
