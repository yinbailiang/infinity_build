##Module Std.Tui.Prompt

<#
.NOTES
    Name: infinity_tui_prompt
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    TUI 用户输入提示模块
.DESCRIPTION
    提供丰富的终端交互式输入组件：
    1. 文本输入（Read-TuiLine）
    2. 密码输入（Read-TuiPassword）
    3. 单选菜单（Show-TuiMenu）
    4. 多选菜单（Show-TuiMultiSelect）
#>

#region 内部辅助函数

<#
.SYNOPSIS
    刷新当前行：擦除后重绘提示符 + 输入内容 + 光标定位
#>
function Invoke-TuiRefreshLine {
    param(
        [string]$Prompt,
        [string]$Value,
        [int]$CursorPos,
        [TuiStyle]$PromptStyle,
        [TuiStyle]$InputStyle
    )
    $reset = [TuiAnsi]::Reset
    $line = $PromptStyle.ToAnsiPrefix() + $Prompt + $reset +
            $InputStyle.ToAnsiPrefix() + $Value + $reset
    Write-Host -NoNewline ("`r$([TuiAnsi]::EraseLine)$line")
    if ($CursorPos -lt $Value.Length) {
        $back = $Value.Length - $CursorPos
        Write-Host -NoNewline ("`u{001b}[${back}D")
    }
}

<#
.SYNOPSIS
    仅调整光标位置（不重绘内容）
#>
function Invoke-TuiRefreshCursor {
    param(
        [string]$Prompt,
        [string]$Value,
        [int]$CursorPos
    )
    $col = $Prompt.Length + $CursorPos + 1
    Write-Host -NoNewline ("`u{001b}[${col}G")
}

#endregion

#region 文本输入

<#
.SYNOPSIS
    带样式的单行文本输入
.DESCRIPTION
    支持方向键编辑、默认值、输入验证器。
.EXAMPLE
    $name = Read-TuiLine -Prompt "用户名: " -DefaultValue "admin"
#>
function Read-TuiLine {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = "> ",

        [string]$DefaultValue,
        [TuiStyle]$PromptStyle = [TuiStyle]::Info,
        [TuiStyle]$InputStyle = [TuiStyle]::new([TuiColor]::BrightWhite),
        [ValidateRange(1, 1024)]
        [int]$MaxLength = 256,
        [scriptblock]$Validator
    )

    $inputValue = if ($DefaultValue) { $DefaultValue } else { "" }
    $cursorPos = $inputValue.Length

    Invoke-TuiRefreshLine -Prompt $Prompt -Value $inputValue `
        -CursorPos $cursorPos -PromptStyle $PromptStyle -InputStyle $InputStyle

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'Enter' {
                if ($Validator) {
                    $valid = & $Validator $inputValue
                    if (-not $valid) { continue }
                }
                Write-Host ""
                return $inputValue
            }
            'Escape' {
                Write-Host ""
                return $null
            }
            'Backspace' {
                if ($cursorPos -gt 0) {
                    $inputValue = $inputValue.Remove($cursorPos - 1, 1)
                    $cursorPos--
                    Invoke-TuiRefreshLine -Prompt $Prompt -Value $inputValue `
                        -CursorPos $cursorPos -PromptStyle $PromptStyle -InputStyle $InputStyle
                }
            }
            'Delete' {
                if ($cursorPos -lt $inputValue.Length) {
                    $inputValue = $inputValue.Remove($cursorPos, 1)
                    Invoke-TuiRefreshLine -Prompt $Prompt -Value $inputValue `
                        -CursorPos $cursorPos -PromptStyle $PromptStyle -InputStyle $InputStyle
                }
            }
            'LeftArrow' {
                if ($cursorPos -gt 0) { $cursorPos-- }
                Invoke-TuiRefreshCursor -Prompt $Prompt -Value $inputValue -CursorPos $cursorPos
            }
            'RightArrow' {
                if ($cursorPos -lt $inputValue.Length) { $cursorPos++ }
                Invoke-TuiRefreshCursor -Prompt $Prompt -Value $inputValue -CursorPos $cursorPos
            }
            'Home' {
                $cursorPos = 0
                Invoke-TuiRefreshCursor -Prompt $Prompt -Value $inputValue -CursorPos $cursorPos
            }
            'End' {
                $cursorPos = $inputValue.Length
                Invoke-TuiRefreshCursor -Prompt $Prompt -Value $inputValue -CursorPos $cursorPos
            }
            default {
                $char = $key.KeyChar
                if ($char -ge 32 -and $char -le 126 -and $inputValue.Length -lt $MaxLength) {
                    $inputValue = $inputValue.Insert($cursorPos, $char)
                    $cursorPos++
                    Invoke-TuiRefreshLine -Prompt $Prompt -Value $inputValue `
                        -CursorPos $cursorPos -PromptStyle $PromptStyle -InputStyle $InputStyle
                }
            }
        }
    }
}

#endregion

#region 密码输入

<#
.SYNOPSIS
    密码输入（回显遮罩）
.EXAMPLE
    $pwd = Read-TuiPassword -Prompt "输入密码: "
#>
function Read-TuiPassword {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = "Password: ",

        [string]$MaskChar = "*",
        [TuiStyle]$PromptStyle = [TuiStyle]::Warning,
        [ValidateRange(1, 256)]
        [int]$MaxLength = 128
    )

    Write-Host -NoNewline ($PromptStyle.ToAnsiPrefix() + $Prompt + [TuiAnsi]::Reset)

    $password = ""
    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'Enter' {
                Write-Host ""
                return $password
            }
            'Escape' {
                Write-Host ""
                return $null
            }
            'Backspace' {
                if ($password.Length -gt 0) {
                    $password = $password.Substring(0, $password.Length - 1)
                    Write-Host -NoNewline "`b `b"
                }
            }
            default {
                $char = $key.KeyChar
                if ($char -ge 32 -and $char -le 126 -and $password.Length -lt $MaxLength) {
                    $password += $char
                    Write-Host -NoNewline $MaskChar
                }
            }
        }
    }
}

#endregion

#region 菜单绘制辅助

<#
.SYNOPSIS
    绘制单选菜单
#>
function Invoke-TuiDrawMenu {
    param(
        [string[]]$Items,
        [int]$Selected,
        [string]$Title,
        [TuiStyle]$TitleStyle,
        [TuiStyle]$SelectedStyle,
        [TuiStyle]$ItemStyle,
        [TuiStyle]$CursorStyle,
        [string]$CursorSymbol
    )

    Write-Host ""
    Write-Host ($TitleStyle.ToAnsiPrefix() + "  $Title" + [TuiAnsi]::Reset)
    Write-Host ""

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($i -eq $Selected) {
            $line = $CursorStyle.ToAnsiPrefix() + " $CursorSymbol " + [TuiAnsi]::Reset
            $line += $SelectedStyle.ToAnsiPrefix() + $Items[$i] + [TuiAnsi]::Reset
        } else {
            $line = "   " + $ItemStyle.ToAnsiPrefix() + $Items[$i] + [TuiAnsi]::Reset
        }
        Write-Host $line
    }
}

<#
.SYNOPSIS
    绘制多选菜单
#>
function Invoke-TuiDrawMultiSelect {
    param(
        [string[]]$Items,
        [bool[]]$Checked,
        [int]$Cursor,
        [string]$Title,
        [TuiStyle]$TitleStyle,
        [TuiStyle]$SelectedStyle,
        [TuiStyle]$ItemStyle,
        [TuiStyle]$CursorStyle,
        [TuiStyle]$CheckedStyle,
        [string]$CheckedSymbol,
        [string]$UncheckedSymbol,
        [string]$CursorSymbol
    )

    Write-Host ""
    Write-Host ($TitleStyle.ToAnsiPrefix() + "  $Title" + [TuiAnsi]::Reset)
    Write-Host ""

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $check = if ($Checked[$i]) {
            $CheckedStyle.ToAnsiPrefix() + $CheckedSymbol + [TuiAnsi]::Reset
        } else {
            $UncheckedSymbol
        }

        if ($i -eq $Cursor) {
            $line = $CursorStyle.ToAnsiPrefix() + " $CursorSymbol " + [TuiAnsi]::Reset
            $line += $SelectedStyle.ToAnsiPrefix() + "$check $($Items[$i])" + [TuiAnsi]::Reset
        } else {
            $line = "   " + $ItemStyle.ToAnsiPrefix() + "$check $($Items[$i])" + [TuiAnsi]::Reset
        }
        Write-Host $line
    }
}

#endregion

#region 交互式菜单

<#
.SYNOPSIS
    交互式单选菜单
.DESCRIPTION
    使用方向键选择，Enter 确认，Esc 取消。
.EXAMPLE
    $result = Show-TuiMenu -Items @("编译", "测试", "部署") -Title "选择操作"
    Write-Host "选择了: $($result.Value)"
#>
function Show-TuiMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Items,

        [string]$Title = "请选择:",
        [int]$DefaultIndex = 0,
        [TuiStyle]$TitleStyle = [TuiStyle]::Title,
        [TuiStyle]$SelectedStyle = [TuiStyle]::new([TuiColor]::Black, [TuiBgColor]::Cyan, [TuiTextEffect]::Bold),
        [TuiStyle]$ItemStyle = [TuiStyle]::Default,
        [TuiStyle]$CursorStyle = [TuiStyle]::Info,
        [string]$CursorSymbol = "❯",
        [switch]$AllowCancel
    )

    $selected = [Math]::Max(0, [Math]::Min($DefaultIndex, $Items.Count - 1))
    $startTop = [Console]::CursorTop

    Hide-TuiCursor

    try {
        Invoke-TuiDrawMenu -Items $Items -Selected $selected -Title $Title `
            -TitleStyle $TitleStyle -SelectedStyle $SelectedStyle `
            -ItemStyle $ItemStyle -CursorStyle $CursorStyle -CursorSymbol $CursorSymbol

        while ($true) {
            $key = [Console]::ReadKey($true)
            $oldSelected = $selected

            switch ($key.Key) {
                'UpArrow'   { if ($selected -gt 0) { $selected-- } }
                'DownArrow' { if ($selected -lt $Items.Count - 1) { $selected++ } }
                'Home'      { $selected = 0 }
                'End'       { $selected = $Items.Count - 1 }
                'Enter'     {
                    Show-TuiCursor
                    return @{ Index = $selected; Value = $Items[$selected] }
                }
                'Escape' {
                    if ($AllowCancel) {
                        Show-TuiCursor
                        return $null
                    }
                }
            }

            if ($selected -ne $oldSelected) {
                [Console]::CursorTop = $startTop
                Invoke-TuiDrawMenu -Items $Items -Selected $selected -Title $Title `
                    -TitleStyle $TitleStyle -SelectedStyle $SelectedStyle `
                    -ItemStyle $ItemStyle -CursorStyle $CursorStyle -CursorSymbol $CursorSymbol
            }
        }
    }
    finally {
        Show-TuiCursor
    }
}

<#
.SYNOPSIS
    交互式多选菜单
.DESCRIPTION
    空格切换选中，Enter 确认。
.EXAMPLE
    $results = Show-TuiMultiSelect -Items @("A", "B", "C") -Title "选择多个"
    $results | ForEach-Object { Write-Host $_.Value }
#>
function Show-TuiMultiSelect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Items,

        [string]$Title = "请选择 (空格切换, Enter确认):",
        [bool[]]$DefaultSelected,
        [TuiStyle]$TitleStyle = [TuiStyle]::Title,
        [TuiStyle]$SelectedStyle = [TuiStyle]::new([TuiColor]::Black, [TuiBgColor]::Cyan, [TuiTextEffect]::Bold),
        [TuiStyle]$ItemStyle = [TuiStyle]::Default,
        [TuiStyle]$CursorStyle = [TuiStyle]::Info,
        [TuiStyle]$CheckedStyle = [TuiStyle]::Success,
        [string]$CheckedSymbol = "[✔]",
        [string]$UncheckedSymbol = "[ ]",
        [string]$CursorSymbol = "❯"
    )

    $checked = if ($DefaultSelected -and $DefaultSelected.Count -eq $Items.Count) {
        [bool[]]$DefaultSelected
    } else {
        [bool[]]::new($Items.Count)
    }

    $cursor = 0
    $startTop = [Console]::CursorTop
    Hide-TuiCursor

    try {
        Invoke-TuiDrawMultiSelect -Items $Items -Checked $checked -Cursor $cursor -Title $Title `
            -TitleStyle $TitleStyle -SelectedStyle $SelectedStyle -ItemStyle $ItemStyle `
            -CursorStyle $CursorStyle -CheckedStyle $CheckedStyle `
            -CheckedSymbol $CheckedSymbol -UncheckedSymbol $UncheckedSymbol -CursorSymbol $CursorSymbol

        while ($true) {
            $key = [Console]::ReadKey($true)
            $oldCursor = $cursor

            switch ($key.Key) {
                'UpArrow'   { if ($cursor -gt 0) { $cursor-- } }
                'DownArrow' { if ($cursor -lt $Items.Count - 1) { $cursor++ } }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $Items.Count - 1 }
                'Spacebar'  { $checked[$cursor] = -not $checked[$cursor] }
                'Enter'     {
                    $result = @()
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        if ($checked[$i]) {
                            $result += @{ Index = $i; Value = $Items[$i] }
                        }
                    }
                    Show-TuiCursor
                    return $result
                }
                'Escape' {
                    Show-TuiCursor
                    return $null
                }
            }

            if ($cursor -ne $oldCursor -or $key.Key -eq 'Spacebar') {
                [Console]::CursorTop = $startTop
                Invoke-TuiDrawMultiSelect -Items $Items -Checked $checked -Cursor $cursor -Title $Title `
                    -TitleStyle $TitleStyle -SelectedStyle $SelectedStyle -ItemStyle $ItemStyle `
                    -CursorStyle $CursorStyle -CheckedStyle $CheckedStyle `
                    -CheckedSymbol $CheckedSymbol -UncheckedSymbol $UncheckedSymbol -CursorSymbol $CursorSymbol
            }
        }
    }
    finally {
        Show-TuiCursor
    }
}

#endregion
