# 第三方说明

## 图标制作工具

当前图标的平面 SVG 素材和 7×7 灰度图案保存在 `IconDesign/Selected7x7/`。玻璃效果由 [frontedu/liquid-composer](https://github.com/frontedu/liquid-composer) 渲染，使用的提交为 `3184413f7d267e260f84b080295450229485665a`。

本仓库保留该工具的输入配方与输出图标，不包含其引擎、着色器、依赖或源码副本。App 运行时不依赖该工具。图标的复现步骤见 `IconDesign/README.md`。

## 系统框架

App 使用 SwiftUI、AppKit、Core Image、Core Graphics、ImageIO 等 Apple 系统框架。系统框架和 SF Symbols 不作为本项目的原创代码重新许可。
