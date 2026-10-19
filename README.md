# 码住

<img src="docs/icon.png" width="160" alt="码住图标">

面向 macOS 和 Windows 的原生批量图片打码工具。macOS 使用 Swift、SwiftUI 和 AppKit，Windows 使用 C#、WinUI 3 和 Win2D。导入一批图片，逐张涂抹、确认，最后统一导出。图片在本机处理，无需上传服务器。

[下载最新版本](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/latest) · [GPL-3.0 许可证](LICENSE)

当前正式版本为 [v1.6.6](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/tag/v1.6.6)：

| 平台 | 下载 | 系统要求 |
| --- | --- | --- |
| macOS | [DMG](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/download/v1.6.6/Mazhu-1.6.6-macOS-arm64.dmg) | Apple Silicon，macOS 26 或更高版本 |
| Windows | [x64 安装 EXE](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/download/v1.6.6/Mazhu-1.6.6-windows-x64.exe) | Windows 11 x64 |

Windows 的详细操作和开发说明见 [windows/README.md](windows/README.md)。ARM64 目前仅有构建验证，没有正式安装包；Actions 中的临时构建产物供开发检查使用。Release 页面另外两个 Source code 文件由 GitHub 自动生成，属于源码下载。

## 功能

- 批量导入图片、拖入文件，或用 **⌘V / Ctrl+V** 粘贴图片。
- 马赛克、画笔、圈选、直线、高斯模糊五种工具。
- 圈选区域可填充马赛克或高斯模糊；画笔支持圆形、方形、颜色和不透明度。
- 侧栏支持框选、修饰键多选与拖动排序；Windows 支持 Ctrl 多选、Shift 连选和右键移除。
- 撤销、重做、缩放和滚轮快捷调整。
- 本地保存原图、笔画和完成状态；退出后可继续编辑。
- 已确认图片可批量导出为 PNG 或 ZIP，保留像素尺寸。

## 系统要求

macOS 版面向 **Apple Silicon Mac，macOS 26 或更高版本**；Windows 版面向 **Windows 11 x64**。部分 macOS 27 玻璃交互使用运行时能力检测，在较早版本上采用可用的原生控件行为。

macOS 下载 DMG 后，将“码住”拖到 Applications。Windows 下载 EXE 后运行安装，从开始菜单打开“码住”，无需另装 .NET 或 Windows App SDK。Windows 默认安装到 `%LOCALAPPDATA%\Programs\Mazhu`，可在系统设置的“已安装的应用”中卸载。

macOS App 使用临时签名（ad-hoc），未经过 Apple Developer ID 签名或公证；Windows 安装 EXE 尚未进行代码签名。系统首次打开时可能显示安全提示，也可以从源码自行构建。

## 使用

1. 用 **⌘O（macOS）/ Ctrl+O（Windows）** 批量导入，或直接拖入、粘贴图片。
2. 选择工具，在图片上拖动打码，通过参数面板调整效果。
3. 按回车确认当前图片并进入下一张。
4. 通过右上角导出菜单导出已确认的图片。

| 功能 | macOS | Windows |
| --- | --- | --- |
| 从剪贴板导入 | ⌘V | Ctrl+V |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z | Ctrl+Z / Ctrl+Shift+Z 或 Ctrl+Y |
| 上一张 / 下一张 | ← / → | 画布聚焦后 ← / → |
| 确认并下一张 | 回车 | 画布聚焦后回车 |
| 适应窗口 / 实际大小 | ⌘0 / ⌘1 | Ctrl+0 / Ctrl+1 |
| 指针位置缩放 | ⌘+滚轮 | Ctrl+滚轮 |
| 调整笔刷或线宽 | ⌥+滚轮 | 画布内 Alt+滚轮，或 [ / ] |
| 调整颗粒、不透明度或模糊强度 | ⌥⇧+滚轮 | 悬停对应参数滑条后滚轮 |

macOS 参数快捷键会随当前工具切换，可在“图片 → 滚轮快捷操作”中查看。Windows 支持滚轮上下平移、Shift+滚轮左右平移、右键或中键拖动图片，以及悬停任意参数／缩放滑条后滚轮调整。

Windows 笔刷大小按窗口逻辑像素计量，缩放图片不改变新笔刷的屏幕大小；已有笔画随图片缩放。切图时仅画布显示加载提示，连续涂抹复用已完成的画面。

**遮盖敏感信息时，建议使用完全不透明的画笔。** 马赛克、模糊和半透明涂抹不能保证隐藏内容无法被推测。

## 从源码构建

### macOS

需要 Apple Silicon Mac、支持 macOS 26 SDK 的 Xcode 或 Command Line Tools。当前构建脚本以 `arm64-apple-macos26.0` 为目标；没有第三方 Swift 依赖。

```sh
git clone https://github.com/wzuivcsyuiopas-cmd/mazhu.git
cd mazhu
./scripts/check.sh
./scripts/build.sh
open dist/码住.app
```

默认中间文件位于 `.build-local/`，App 位于 `dist/码住.app`。可通过 `TUMA_BUILD_DIR`、`TUMA_APP_PATH` 覆盖路径。`Package.swift` 可用于在 Xcode 中浏览和开发；生成完整 App 包请使用构建脚本。

`check.sh` 在独立临时目录使用自动生成的图片，检查渲染、历史恢复、剪贴板、批量操作、导出和部分 AppKit 行为，不读取用户工作区。

### Windows

需要 Windows 11、.NET 8 SDK 和 PowerShell 7。在仓库根目录运行：

```powershell
./windows/build.ps1 -Architecture x64 -Check
./windows/dist/x64/Mazhu.exe
```

输出目录包含运行时和界面资源，手动分发需要保留完整目录。生成正式安装 EXE 还需要 Inno Setup 6，运行 `./scripts/package-windows.ps1`，输出到 `release/`。ARM64 交叉编译、交互检查及性能检查见 [Windows 开发说明](windows/README.md)。

## 发布

完整步骤见 [发布指南](docs/RELEASING.md)。在 GitHub Actions 中运行 **Release packages**，流程从同一提交构建并验证 macOS DMG 和 Windows x64 安装 EXE，两者成功后一起发布；SHA-256 校验值写在发行说明中。

## 本地数据

macOS 为兼容改名前的版本，应用标识沿用 `local.tuma.native`。两端工作区位置如下：

```text
macOS:   ~/Library/Application Support/TuMa/
Windows: %LOCALAPPDATA%\Mazhu\
```

其中包含导入的原图和编辑记录，两端格式独立，不自动互相迁移。Windows 卸载程序保留该工作区。不要把这些目录提交到仓库或附到公开问题中；反馈问题时请使用可以公开的示例图片。

## 源码结构

- `Sources/TuMa/`：界面、图像处理、工作区和窗口行为。
- `Tests/CoreChecks.swift`：核心回归检查。
- `windows/Mazhu/`：Windows 界面、Win2D 渲染、工作区及自动检查。
- `scripts/`：检查和打包脚本。
- `packaging/windows.iss`：Windows 安装 EXE 配置。
- `docs/releases/`：各版本发行说明。
- `IconDesign/`：当前 7×7 图标的素材与渲染配方。

## 贡献与许可

欢迎提交问题和 Pull Request，参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

Copyright © 2026 码住 contributors。项目按 **GNU GPL version 3 only（GPL-3.0-only）** 发布，完整条款见 [LICENSE](LICENSE)。第三方工具来源见 [NOTICE.md](NOTICE.md)。
