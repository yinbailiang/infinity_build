##Module Std.Tui
##Import Std.Tui.Core
##Import Std.Tui.Components
##Import Std.Tui.Prompt

<#
.NOTES
    Name: infinity_tui
    Author: YinBailiang
    Version: 1.0.0
.SYNOPSIS
    Infinity Build 的终端 UI 库
.DESCRIPTION
    这个模块提供功能完善的 TUI 组件系统，包含以下特性：
    1. 终端屏幕管理（缓冲渲染、画布、光标控制）
    2. ANSI 转义序列封装（颜色、效果、边框字符集）
    3. 基础组件（进度条、旋转指示器、表格、列表、树形结构）
    4. 交互式输入（文本输入、密码输入、单选/多选菜单）
    5. 通知横幅与确认对话框
    6. 完整样式系统（前景色/背景色/文字效果）

    子模块：
    - Std.Tui.Core       : ANSI 原语、样式、画布、边框绘制
    - Std.Tui.Components : 进度条、表格、列表、树、状态栏、横幅
    - Std.Tui.Prompt     : 文本/密码输入、菜单选择

    设计原则：
    - 纯 PowerShell 实现，无外部依赖
    - 跨平台兼容（Windows / Linux / macOS 终端均支持）
    - 逐帧渲染 + 差值刷新，避免画面闪烁
    - 样式与内容分离，主题化友好
#>