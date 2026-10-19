# 参与开发

1. Fork 仓库并建立分支。
2. 保持平台原生交互：macOS 使用 SwiftUI / AppKit，Windows 使用 WinUI 3 / Win2D；新增功能同时考虑撤销、保存恢复和批量处理。
3. 修改图像处理或数据模型时，补充有意义的回归检查。macOS 运行 `./scripts/check.sh`；Windows 运行 `./windows/build.ps1 -Architecture x64 -Check`。
4. macOS 运行 `./scripts/build.sh`，Windows 启动 `windows/dist/x64/Mazhu.exe`，在实际窗口检查相关交互。Windows 的临时工作区、交互检查和性能复测方式见 [Windows 开发说明](windows/README.md) 与 [界面检查](windows/DESIGN.md#视觉检查)。
5. 提交 Pull Request，说明问题、变化和验证结果。

请不要提交真实用户图片、工作区、令牌或个人路径。界面问题请使用可公开的样本，并注明操作系统版本、CPU 架构、显示缩放及复现步骤。发布维护见 [发布指南](docs/RELEASING.md)。

提交贡献即表示你同意该贡献按本项目的 GPL-3.0-only 许可证发布。
