##Module Std.Tui.Core

<#
.NOTES
    Name: infinity_tui_core
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    TUI 核心绘制原语模块
.DESCRIPTION
    提供终端 UI 的基础绘制能力：
    1. 终端尺寸检测与缓冲区管理
    2. ANSI 转义序列封装（光标、颜色、擦除）
    3. 矩形区域与边框绘制
    4. 样式系统（前景色、背景色、文字效果）
    5. 画布抽象（支持离屏渲染后批量输出）
#>

#region ANSI 转义序列常量

class TuiAnsi {
    # 光标控制
    static [string]$CursorHome        = "`u{001b}[H"
    static [string]$CursorHide        = "`u{001b}[?25l"
    static [string]$CursorShow        = "`u{001b}[?25h"
    static [string]$CursorSave        = "`u{001b}[s"
    static [string]$CursorRestore     = "`u{001b}[u"
    static [string]$CursorUp          = "`u{001b}[1A"
    static [string]$CursorDown        = "`u{001b}[1B"
    static [string]$CursorForward     = "`u{001b}[1C"
    static [string]$CursorBack        = "`u{001b}[1D"

    # 擦除
    static [string]$EraseToEnd        = "`u{001b}[0K"
    static [string]$EraseToStart      = "`u{001b}[1K"
    static [string]$EraseLine         = "`u{001b}[2K"
    static [string]$EraseDown         = "`u{001b}[0J"
    static [string]$EraseUp           = "`u{001b}[1J"
    static [string]$EraseScreen       = "`u{001b}[2J"

    # 重置
    static [string]$Reset             = "`u{001b}[0m"

    # 滚动
    static [string]$ScrollUp          = "`u{001b}[1S"
    static [string]$ScrollDown        = "`u{001b}[1T"

    # 光标定位
    static [string] CursorPos([int]$Row, [int]$Col) {
        return "`u{001b}[${Row};${Col}H"
    }
}

#endregion

#region 文字效果枚举

<#
.SYNOPSIS
    文字效果位标志枚举
.DESCRIPTION
    支持的 ANSI SGR 效果组合，可用 -bor 组合。
#>
[Flags()]
enum TuiTextEffect {
    None        = 0
    Bold        = 1      # 粗体
    Dim         = 2      # 暗淡
    Italic      = 4      # 斜体
    Underline   = 8      # 下划线
    Blink       = 16     # 闪烁
    Inverse     = 32     # 反色
    Hidden      = 64     # 隐藏
    Strikethrough = 128  # 删除线
    DoubleUnderline = 256 # 双下划线
    Overline    = 512    # 上划线
}

#endregion

#region 颜色定义

<#
.SYNOPSIS
    TUI 颜色类（支持 4-bit / 8-bit / 24-bit 色）
#>
class TuiColor {
    [string]$AnsiCode

    # 4-bit 标准色
    TuiColor([string]$AnsiCode) {
        $this.AnsiCode = $AnsiCode
    }

    # 8-bit (256 色)
    static [TuiColor] From256([int]$Index) {
        if ($Index -lt 0 -or $Index -gt 255) {
            throw "256 色索引必须在 0-255 之间"
        }
        return [TuiColor]::new("38;5;${Index}")
    }

    # 24-bit 真彩色
    static [TuiColor] FromRgb([int]$R, [int]$G, [int]$B) {
        if ($R -lt 0 -or $R -gt 255 -or $G -lt 0 -or $G -gt 255 -or $B -lt 0 -or $B -gt 255) {
            throw "RGB 值必须在 0-255 之间"
        }
        return [TuiColor]::new("38;2;${R};${G};${B}")
    }

    [string] ToFgCode() { return "`u{001b}[$($this.AnsiCode)m" }
    [string] ToBgCode() { return "`u{001b}[$($this.AnsiCode -replace '^38', '48')m" }

    #region 4-bit 预设前景色
    static [TuiColor] $Black       = [TuiColor]::new("30")
    static [TuiColor] $Red         = [TuiColor]::new("31")
    static [TuiColor] $Green       = [TuiColor]::new("32")
    static [TuiColor] $Yellow      = [TuiColor]::new("33")
    static [TuiColor] $Blue        = [TuiColor]::new("34")
    static [TuiColor] $Magenta     = [TuiColor]::new("35")
    static [TuiColor] $Cyan        = [TuiColor]::new("36")
    static [TuiColor] $White       = [TuiColor]::new("37")
    static [TuiColor] $BrightBlack = [TuiColor]::new("90")
    static [TuiColor] $BrightRed   = [TuiColor]::new("91")
    static [TuiColor] $BrightGreen = [TuiColor]::new("92")
    static [TuiColor] $BrightYellow= [TuiColor]::new("93")
    static [TuiColor] $BrightBlue  = [TuiColor]::new("94")
    static [TuiColor] $BrightMagenta=[TuiColor]::new("95")
    static [TuiColor] $BrightCyan  = [TuiColor]::new("96")
    static [TuiColor] $BrightWhite = [TuiColor]::new("97")
    #endregion
}

<#
.SYNOPSIS
    TUI 背景色类
#>
class TuiBgColor {
    [string]$AnsiCode

    TuiBgColor([string]$AnsiCode) {
        $this.AnsiCode = $AnsiCode
    }

    static [TuiBgColor] From256([int]$Index) {
        if ($Index -lt 0 -or $Index -gt 255) {
            throw "256 色索引必须在 0-255 之间"
        }
        return [TuiBgColor]::new("48;5;${Index}")
    }

    static [TuiBgColor] FromRgb([int]$R, [int]$G, [int]$B) {
        if ($R -lt 0 -or $R -gt 255 -or $G -lt 0 -or $G -gt 255 -or $B -lt 0 -or $B -gt 255) {
            throw "RGB 值必须在 0-255 之间"
        }
        return [TuiBgColor]::new("48;2;${R};${G};${B}")
    }

    [string] ToCode() { return "`u{001b}[$($this.AnsiCode)m" }

    #region 4-bit 预设背景色
    static [TuiBgColor] $Black       = [TuiBgColor]::new("40")
    static [TuiBgColor] $Red         = [TuiBgColor]::new("41")
    static [TuiBgColor] $Green       = [TuiBgColor]::new("42")
    static [TuiBgColor] $Yellow      = [TuiBgColor]::new("43")
    static [TuiBgColor] $Blue        = [TuiBgColor]::new("44")
    static [TuiBgColor] $Magenta     = [TuiBgColor]::new("45")
    static [TuiBgColor] $Cyan        = [TuiBgColor]::new("46")
    static [TuiBgColor] $White       = [TuiBgColor]::new("47")
    static [TuiBgColor] $BrightBlack = [TuiBgColor]::new("100")
    static [TuiBgColor] $BrightRed   = [TuiBgColor]::new("101")
    static [TuiBgColor] $BrightGreen = [TuiBgColor]::new("102")
    static [TuiBgColor] $BrightYellow= [TuiBgColor]::new("103")
    static [TuiBgColor] $BrightBlue  = [TuiBgColor]::new("104")
    static [TuiBgColor] $BrightMagenta=[TuiBgColor]::new("105")
    static [TuiBgColor] $BrightCyan  = [TuiBgColor]::new("106")
    static [TuiBgColor] $BrightWhite = [TuiBgColor]::new("107")
    #endregion
}

#endregion

#region 样式类

<#
.SYNOPSIS
    TUI 样式类，封装前景色、背景色、文字效果
#>
class TuiStyle {
    [TuiColor]$Foreground
    [TuiBgColor]$Background
    [TuiTextEffect]$Effect

    TuiStyle() {
        $this.Foreground = $null
        $this.Background = $null
        $this.Effect = [TuiTextEffect]::None
    }

    TuiStyle([TuiColor]$Fg) {
        $this.Foreground = $Fg
        $this.Background = $null
        $this.Effect = [TuiTextEffect]::None
    }

    TuiStyle([TuiColor]$Fg, [TuiBgColor]$Bg) {
        $this.Foreground = $Fg
        $this.Background = $Bg
        $this.Effect = [TuiTextEffect]::None
    }

    TuiStyle([TuiColor]$Fg, [TuiBgColor]$Bg, [TuiTextEffect]$Effect) {
        $this.Foreground = $Fg
        $this.Background = $Bg
        $this.Effect = $Effect
    }

    [string] ToAnsiPrefix() {
        $codes = [System.Collections.Generic.List[string]]::new()
        if ($this.Foreground) { $codes.Add($this.Foreground.AnsiCode) }
        if ($this.Background) { $codes.Add($this.Background.AnsiCode) }
        if ($this.Effect -band [TuiTextEffect]::Bold)        { $codes.Add("1") }
        if ($this.Effect -band [TuiTextEffect]::Dim)         { $codes.Add("2") }
        if ($this.Effect -band [TuiTextEffect]::Italic)       { $codes.Add("3") }
        if ($this.Effect -band [TuiTextEffect]::Underline)    { $codes.Add("4") }
        if ($this.Effect -band [TuiTextEffect]::Blink)        { $codes.Add("5") }
        if ($this.Effect -band [TuiTextEffect]::Inverse)      { $codes.Add("7") }
        if ($this.Effect -band [TuiTextEffect]::Hidden)       { $codes.Add("8") }
        if ($this.Effect -band [TuiTextEffect]::Strikethrough){ $codes.Add("9") }
        if ($this.Effect -band [TuiTextEffect]::DoubleUnderline){ $codes.Add("21") }
        if ($this.Effect -band [TuiTextEffect]::Overline)     { $codes.Add("53") }

        if ($codes.Count -eq 0) { return "" }
        return "`u{001b}[$($codes -join ';')m"
    }

    # 预设样式
    static [TuiStyle] $Default      = [TuiStyle]::new()
    static [TuiStyle] $Error        = [TuiStyle]::new([TuiColor]::BrightRed, $null, [TuiTextEffect]::Bold)
    static [TuiStyle] $Warning      = [TuiStyle]::new([TuiColor]::BrightYellow)
    static [TuiStyle] $Success      = [TuiStyle]::new([TuiColor]::BrightGreen)
    static [TuiStyle] $Info         = [TuiStyle]::new([TuiColor]::BrightCyan)
    static [TuiStyle] $Highlight    = [TuiStyle]::new([TuiColor]::BrightWhite, [TuiBgColor]::Blue, [TuiTextEffect]::Bold)
    static [TuiStyle] $Muted        = [TuiStyle]::new([TuiColor]::BrightBlack)
    static [TuiStyle] $Title        = [TuiStyle]::new([TuiColor]::BrightCyan, $null, [TuiTextEffect]::Bold -bor [TuiTextEffect]::Underline)
}

#endregion

#region 边框样式

<#
.SYNOPSIS
    边框字符集
#>
class TuiBorder {
    [string]$TopLeft
    [string]$TopRight
    [string]$BottomLeft
    [string]$BottomRight
    [string]$Horizontal
    [string]$Vertical
    [string]$Cross
    [string]$TeeDown
    [string]$TeeUp
    [string]$TeeLeft
    [string]$TeeRight

    TuiBorder(
        [string]$TL, [string]$TR, [string]$BL, [string]$BR,
        [string]$H,  [string]$V,  [string]$Cross,
        [string]$TeeDown, [string]$TeeUp,
        [string]$TeeLeft, [string]$TeeRight
    ) {
        $this.TopLeft = $TL; $this.TopRight = $TR
        $this.BottomLeft = $BL; $this.BottomRight = $BR
        $this.Horizontal = $H; $this.Vertical = $V
        $this.Cross = $Cross
        $this.TeeDown = $TeeDown; $this.TeeUp = $TeeUp
        $this.TeeLeft = $TeeLeft; $this.TeeRight = $TeeRight
    }

    # 预设：单线
    static [TuiBorder] $Single = [TuiBorder]::new(
        "┌", "┐", "└", "┘", "─", "│", "┼", "┬", "┴", "├", "┤"
    )
    # 预设：双线
    static [TuiBorder] $Double = [TuiBorder]::new(
        "╔", "╗", "╚", "╝", "═", "║", "╬", "╦", "╩", "╠", "╣"
    )
    # 预设：粗线（圆角）
    static [TuiBorder] $Rounded = [TuiBorder]::new(
        "╭", "╮", "╰", "╯", "─", "│", "┼", "┬", "┴", "├", "┤"
    )
    # 预设：纯 ASCII（兼容性好）
    static [TuiBorder] $Ascii = [TuiBorder]::new(
        "+", "+", "+", "+", "-", "|", "+", "+", "+", "+", "+"
    )
    # 预设：无边框
    static [TuiBorder] $None = [TuiBorder]::new(
        " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " "
    )
}

#endregion

#region 矩形与终端尺寸

<#
.SYNOPSIS
    TUI 矩形区域
#>
class TuiRect {
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height

    TuiRect([int]$X, [int]$Y, [int]$Width, [int]$Height) {
        $this.X = $X
        $this.Y = $Y
        $this.Width = [Math]::Max(0, $Width)
        $this.Height = [Math]::Max(0, $Height)
    }

    [int] Right()  { return $this.X + $this.Width - 1 }
    [int] Bottom() { return $this.Y + $this.Height - 1 }

    [TuiRect] Shrink([int]$Margin) {
        return [TuiRect]::new(
            $this.X + $Margin,
            $this.Y + $Margin,
            $this.Width - 2 * $Margin,
            $this.Height - 2 * $Margin
        )
    }

    [TuiRect] InnerRect() {
        return $this.Shrink(1)
    }

    [bool] Contains([int]$X, [int]$Y) {
        return $X -ge $this.X -and $X -le $this.Right() -and
               $Y -ge $this.Y -and $Y -le $this.Bottom()
    }

    [string] ToString() {
        return "({0},{1}) {2}x{3}" -f $this.X, $this.Y, $this.Width, $this.Height
    }
}

<#
.SYNOPSIS
    终端尺寸信息
#>
class TuiTerminal {
    static [int] Width() {
        try { return [Console]::BufferWidth } catch { return 80 }
    }
    static [int] Height() {
        try { return [Console]::WindowHeight } catch { return 24 }
    }
    static [TuiRect] FullRect() {
        return [TuiRect]::new(0, 0, [TuiTerminal]::Width(), [TuiTerminal]::Height())
    }
}

#endregion

#region 画布类

<#
.SYNOPSIS
    TUI 画布 — 离屏渲染缓冲区
.DESCRIPTION
    构建一个二维字符网格，支持像素级绘制，最后一次性输出到终端。
    用于避免逐行 Write-Host 造成的闪烁问题。
#>
class TuiCanvas {
    hidden [string[][]]$Buffer
    hidden [int]$Width
    hidden [int]$Height
    [string]$DefaultChar = " "

    TuiCanvas([int]$Width, [int]$Height) {
        $this.Width = $Width
        $this.Height = $Height
        $this.InitBuffer()
    }

    TuiCanvas([TuiRect]$Rect) {
        $this.Width = $Rect.Width
        $this.Height = $Rect.Height
        $this.InitBuffer()
    }

    hidden [void] InitBuffer() {
        $this.Buffer = [string[][]]::new($this.Height)
        for ($y = 0; $y -lt $this.Height; $y++) {
            $this.Buffer[$y] = [string[]]::new($this.Width)
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this.Buffer[$y][$x] = $this.DefaultChar
            }
        }
    }

    [void] Clear() {
        for ($y = 0; $y -lt $this.Height; $y++) {
            for ($x = 0; $x -lt $this.Width; $x++) {
                $this.Buffer[$y][$x] = $this.DefaultChar
            }
        }
    }

    [void] ClearRect([TuiRect]$Rect) {
        $xMin = [Math]::Max(0, $Rect.X)
        $yMin = [Math]::Max(0, $Rect.Y)
        $xMax = [Math]::Min($this.Width - 1, $Rect.Right())
        $yMax = [Math]::Min($this.Height - 1, $Rect.Bottom())
        for ($y = $yMin; $y -le $yMax; $y++) {
            for ($x = $xMin; $x -le $xMax; $x++) {
                $this.Buffer[$y][$x] = $this.DefaultChar
            }
        }
    }

    [void] Put([int]$X, [int]$Y, [string]$Char) {
        if ($X -ge 0 -and $X -lt $this.Width -and $Y -ge 0 -and $Y -lt $this.Height) {
            if ($Char.Length -gt 0) {
                $this.Buffer[$Y][$X] = $Char[0].ToString()
            }
        }
    }

    [void] Write([int]$X, [int]$Y, [string]$Text) {
        for ($i = 0; $i -lt $Text.Length; $i++) {
            $cx = $X + $i
            if ($cx -ge $this.Width) { break }
            if ($cx -ge 0 -and $Y -ge 0 -and $Y -lt $this.Height) {
                $this.Buffer[$Y][$cx] = $Text[$i].ToString()
            }
        }
    }

    [void] WriteAligned([int]$Y, [string]$Text, [string]$Align) {
        $x = switch ($Align) {
            "Center" { [Math]::Floor(($this.Width - $Text.Length) / 2) }
            "Right"  { $this.Width - $Text.Length }
            default  { 0 }
        }
        $this.Write([Math]::Max(0, $x), $Y, $Text)
    }

    [void] DrawHLine([int]$X, [int]$Y, [int]$Length, [string]$Char) {
        for ($i = 0; $i -lt $Length; $i++) {
            $this.Put($X + $i, $Y, $Char)
        }
    }

    [void] DrawVLine([int]$X, [int]$Y, [int]$Length, [string]$Char) {
        for ($i = 0; $i -lt $Length; $i++) {
            $this.Put($X, $Y + $i, $Char)
        }
    }

    <#
    .SYNOPSIS
        在画布上绘制带边框的矩形
    #>
    [void] DrawRect([TuiRect]$Rect, [TuiBorder]$Border) {
        if ($Rect.Width -lt 2 -or $Rect.Height -lt 2) { return }

        # 四角
        $this.Put($Rect.X, $Rect.Y, $Border.TopLeft)
        $this.Put($Rect.Right(), $Rect.Y, $Border.TopRight)
        $this.Put($Rect.X, $Rect.Bottom(), $Border.BottomLeft)
        $this.Put($Rect.Right(), $Rect.Bottom(), $Border.BottomRight)

        # 上下水平线
        for ($x = $Rect.X + 1; $x -lt $Rect.Right(); $x++) {
            $this.Put($x, $Rect.Y, $Border.Horizontal)
            $this.Put($x, $Rect.Bottom(), $Border.Horizontal)
        }

        # 左右垂直线
        for ($y = $Rect.Y + 1; $y -lt $Rect.Bottom(); $y++) {
            $this.Put($Rect.X, $y, $Border.Vertical)
            $this.Put($Rect.Right(), $y, $Border.Vertical)
        }
    }

    # 渲染到终端
    [void] Render() {
        $sb = [System.Text.StringBuilder]::new()
        for ($y = 0; $y -lt $this.Height; $y++) {
            $line = -join $this.Buffer[$y]
            if ($y -lt $this.Height - 1) {
                [void]$sb.AppendLine($line)
            } else {
                [void]$sb.Append($line)
            }
        }
        Write-Host $sb.ToString() -NoNewline
    }

    # 渲染到终端（增量模式：仅输出与上次不同的行）
    hidden [string[]]$LastRender = @()

    [void] RenderDiff() {
        $lines = [string[]]::new($this.Height)
        for ($y = 0; $y -lt $this.Height; $y++) {
            $lines[$y] = -join $this.Buffer[$y]
        }

        for ($y = 0; $y -lt $this.Height; $y++) {
            if ($y -ge $this.LastRender.Length -or $lines[$y] -ne $this.LastRender[$y]) {
                $esc = [TuiAnsi]::CursorPos($y + 1, 1)
                Write-Host -NoNewline "$esc$([TuiAnsi]::EraseLine)$($lines[$y])"
            }
        }
        $this.LastRender = $lines
    }

    [int] GetWidth()  { return $this.Width }
    [int] GetHeight() { return $this.Height }

    [string] GetRowString([int]$Y) {
        if ($Y -ge 0 -and $Y -lt $this.Height) {
            return -join $this.Buffer[$Y]
        }
        return ""
    }
}

#endregion

#region 便捷绘制函数

<#
.SYNOPSIS
    在指定位置写入带样式的文本
#>
function Write-Tui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [int]$X = 0,
        [int]$Y = 0,
        [TuiStyle]$Style,
        [switch]$NoNewline
    )

    $prefix = if ($Style) { $Style.ToAnsiPrefix() } else { "" }
    $suffix = if ($Style) { [TuiAnsi]::Reset } else { "" }

    if ($X -gt 0 -or $Y -gt 0) {
        $cursorPos = [TuiAnsi]::CursorPos($Y + 1, $X + 1)
        Write-Host -NoNewline "$cursorPos$prefix$Text$suffix"
    } else {
        Write-Host -NoNewline "$prefix$Text$suffix"
    }
    if (-not $NoNewline) { Write-Host "" }
}

<#
.SYNOPSIS
    绘制带边框的文本块
#>
function Write-TuiBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Content,

        [string]$Title,
        [int]$X = 0,
        [int]$Y = 0,
        [int]$MinWidth = 20,
        [TuiBorder]$Border = [TuiBorder]::Single,
        [TuiStyle]$BorderStyle,
        [TuiStyle]$TitleStyle = [TuiStyle]::Title,
        [int]$Padding = 1
    )

    # 计算所需宽度
    $maxContentWidth = 0
    foreach ($line in $Content) {
        $maxContentWidth = [Math]::Max($maxContentWidth, $line.Length)
    }
    if ($Title) {
        $maxContentWidth = [Math]::Max($maxContentWidth, $Title.Length + 2)
    }
    $innerWidth = [Math]::Max($MinWidth - 2 - 2 * $Padding, $maxContentWidth)
    $totalWidth = $innerWidth + 2 * $Padding + 2
    $totalHeight = $Content.Count + 2 * $Padding + 2

    $canvas = [TuiCanvas]::new($totalWidth, $totalHeight)

    # 绘制边框
    $rect = [TuiRect]::new(0, 0, $totalWidth, $totalHeight)
    $canvas.DrawRect($rect, $Border)

    # 绘制标题（居中，位于顶部边框）
    if ($Title -and $totalWidth -gt $Title.Length + 4) {
        $titleX = [Math]::Floor(($totalWidth - $Title.Length - 2) / 2)
        $canvas.Write($titleX, 0, " $Title ")
    }

    # 绘制内容
    for ($i = 0; $i -lt $Content.Count; $i++) {
        $canvas.Write(1 + $Padding, 1 + $Padding + $i, $Content[$i])
    }

    # 终端输出（此处暂不集成样式，直接 Render）
    $lines = @()
    for ($y = 0; $y -lt $totalHeight; $y++) {
        $lines += $canvas.GetRowString($y)
    }

    # 逐行输出
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $prefix = if ($BorderStyle) { $BorderStyle.ToAnsiPrefix() } else { "" }
        $suffix = if ($BorderStyle) { [TuiAnsi]::Reset } else { "" }
        $lineText = $prefix + $lines[$i] + $suffix
        if ($X -gt 0 -or $Y -gt 0) {
            $cursorPos = [TuiAnsi]::CursorPos($Y + $i + 1, $X + 1)
            Write-Host "$cursorPos$lineText"
        } else {
            Write-Host $lineText
        }
    }
}

<#
.SYNOPSIS
    绘制水平分隔线
#>
function Write-TuiSeparator {
    [CmdletBinding()]
    param(
        [string]$Char = "─",
        [int]$Width = 0,
        [TuiStyle]$Style = [TuiStyle]::Muted,
        [string]$Text
    )

    $termWidth = if ($Width -le 0) { [TuiTerminal]::Width() } else { $Width }

    if ($Text) {
        $totalDecor = $termWidth - $Text.Length - 2
        $leftLen = [Math]::Floor($totalDecor / 2)
        $rightLen = $totalDecor - $leftLen
        $line = ($Char * $leftLen) + " $Text " + ($Char * $rightLen)
    } else {
        $line = $Char * $termWidth
    }

    Write-Tui -Text $line -Style $Style
}

<#
.SYNOPSIS
    清屏
#>
function Clear-TuiScreen {
    Write-Host -NoNewline ([TuiAnsi]::EraseScreen + [TuiAnsi]::CursorHome)
}

<#
.SYNOPSIS
    隐藏光标
#>
function Hide-TuiCursor {
    Write-Host -NoNewline ([TuiAnsi]::CursorHide)
}

<#
.SYNOPSIS
    显示光标
#>
function Show-TuiCursor {
    Write-Host -NoNewline ([TuiAnsi]::CursorShow)
}

#endregion
