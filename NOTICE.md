# 第三方说明

## Windows 应用图标

Windows 应用使用本次用户提供的透明 PNG，原图保存在 `windows/Mazhu/Assets/AppIcon.png`。`AppIcon.ico` 仅作等比尺寸转换，包含 16、24、32、48、64、128、256 像素版本，用于 EXE、窗口及任务栏图标。

## Windows 工具图标

Windows 工具栏中的 Image Add、Clipboard Paste、Grid、Paint Brush、Lasso、Line、Blur 图标来自 [Microsoft Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons)，使用 20 px Regular 版本，按 MIT 许可证分发。原始 SVG 与许可证保存在 `windows/Mazhu/Assets/Icons/`；XAML 中的 PathIcon 使用这些 SVG 的路径数据，以跟随原生控件的主题与选中颜色。

## 图标制作工具

当前图标的平面 SVG 素材和 7×7 灰度图案保存在 `IconDesign/Selected7x7/`。玻璃效果由 [frontedu/liquid-composer](https://github.com/frontedu/liquid-composer) 渲染，使用的提交为 `3184413f7d267e260f84b080295450229485665a`。

本仓库保留该工具的输入配方与输出图标，不包含其引擎、着色器、依赖或源码副本。App 运行时不依赖该工具。图标的复现步骤见 `IconDesign/README.md`。

## 系统框架

App 使用 SwiftUI、AppKit、Core Image、Core Graphics、ImageIO 等 Apple 系统框架。系统框架和 SF Symbols 不作为本项目的原创代码重新许可。
