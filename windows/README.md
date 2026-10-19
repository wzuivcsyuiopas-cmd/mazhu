# 码住 Windows 原生版

首版源码实现，尚未在 Windows 编译或运行验证，不是可直接分发的发行版。

采用 C# / .NET 8、WinUI 3 XAML、Windows App SDK 1.8 稳定分支和 Win2D 1.4。界面使用原生控件，画布通过 Win2D 调用 Direct2D，图片解码使用 Windows Imaging，文件选择、拖放和剪贴板使用 Windows API。应用依赖 .NET 运行时，发布配置携带 .NET 与 Windows App SDK；这里的原生指原生界面与图形栈，不代表已生成 Native AOT 二进制。

## 当前范围

- 批量导入、文件拖放和剪贴板图片。
- 马赛克、画笔、圈选、直线、高斯模糊；颜色、不透明度、圆／方形笔刷及圈选填充选择。
- 撤销／重做、逐张确认、PNG 文件夹和 ZIP 批量导出。
- 原图与笔画分离保存到 `%LOCALAPPDATA%\Mazhu`，保留原图，工作区原子替换写入。
- EXIF 方向规范化、sRGB 编辑，按像素尺寸重新编码 PNG。
- 系统标题栏、Mica 背景、系统主题和原生控件可访问性标签。
- 单实例保护，防止两个进程同时写工作区。

Windows 与 macOS 目前使用独立的工作区格式，不自动读取或迁移 Mac 数据。HEIC、WebP 等解码能力取决于 Windows 安装的编解码器；文件选择列表不代表所有机器都能解码。

## 构建

使用 Windows 11、Visual Studio 2022 的 WinUI 应用开发组件、.NET 8 SDK 和 PowerShell 7。工程的 API 最低目标为 Windows 10 2004，但当前验收目标是 Windows 11，Windows 10 尚未验证。

```powershell
./windows/build.ps1 -Architecture x64 -Check
./windows/build.ps1 -Architecture ARM64
```

生成目录为 `windows/dist/x64` 或 `windows/dist/ARM64`，启动 `Mazhu.exe`。分发时需要完整目录，不能只复制 EXE。尚未制作 MSIX 安装包或 Windows 代码签名。GitHub Actions 配置支持两种架构构建，x64 另执行生成图片的渲染检查；实际构建结果请查看仓库的 Actions 页面。

## 操作

| 操作 | 快捷键 |
| --- | --- |
| 导入／粘贴 | Ctrl+O / Ctrl+V |
| 撤销／重做 | Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y |
| 适应窗口／实际像素 | Ctrl+0 / Ctrl+1 |
| 指针位置缩放 | Ctrl+滚轮 |
| 平移画布 | 按住鼠标中键拖动 |
| 上／下一张，确认 | 画布聚焦后 ← / → / Enter |
| 取消当前笔画 | Escape |

## 验证状态与后续工作

macOS 上目前只完成 XML 解析、XAML 事件对应和差异格式检查，无法执行 WinUI XAML 编译器或验证窗口。`RenderChecks.cs` 已编写但尚未运行，覆盖遮盖区域、圈选外像素不变、方形连续笔画、模糊保留先前遮盖、撤销重放和 PNG 导出尺寸。

发布前必须在 Windows 11 上完成：

1. x64 / ARM64 编译与启动，确认无缺失的运行时依赖。
2. 鼠标、触控笔、失去指针捕获、缩放平移及高 DPI 跨屏验证。
3. 中文路径、透明图、带方向照片、编解码器缺失、大图导入及导出像素核对。
4. 工作区恢复、写入失败、损坏数据保留、重复启动及多图导出验证。
5. Narrator、键盘操作、深浅色、高对比度和窄窗口可用性检查。

尚未与 Mac 版对齐的功能：图片缩略图、多选／框选、列表拖动排序、删除与重置、滚轮参数快捷调整。当前绘制预览会重放整张图的笔画，大图性能尚未优化或测量；不能把这份初版当作已达到 Mac 版完成度的产品。

设计与 API 参考：[WinUI](https://learn.microsoft.com/windows/apps/winui/winui3/)、[Win2D](https://learn.microsoft.com/windows/apps/develop/win2d/quick-start)、[DPI](https://learn.microsoft.com/windows/apps/develop/win2d/dpi-and-dips)。沿用仓库根目录的 GPL-3.0-only 许可。
