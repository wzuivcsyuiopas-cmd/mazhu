# 码住 Windows 原生版

Windows 原生版已随 [v1.6.6](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/tag/v1.6.6) 正式发布，支持 Windows 11 x64。ARM64 已完成交叉编译，尚未在 ARM64 设备启动，也未提供正式安装包。

## 下载与安装

下载 [Mazhu-1.6.6-windows-x64.exe](https://github.com/wzuivcsyuiopas-cmd/mazhu/releases/download/v1.6.6/Mazhu-1.6.6-windows-x64.exe)，运行安装后从开始菜单打开“码住”。安装包包含 .NET 和 Windows App SDK，无需单独安装运行时，默认安装到 `%LOCALAPPDATA%\Programs\Mazhu`，不需要管理员权限。

安装程序尚未进行代码签名。可从系统设置的“已安装的应用”卸载；卸载保留 `%LOCALAPPDATA%\Mazhu` 中的原图和编辑记录。安装目录与工作区是两个不同目录。Release 的 Source code 是源码，Actions 的 ZIP 是开发产物；日常安装使用上述 EXE。

采用 C# / .NET 8、WinUI 3 XAML、Windows App SDK 1.8 稳定分支和 Win2D 1.4。界面使用原生控件，画布通过 Win2D 调用 Direct2D，图片解码使用 Windows Imaging，文件选择、拖放和剪贴板使用 Windows API。应用依赖 .NET 运行时，发布配置携带 .NET 与 Windows App SDK；这里的原生指原生界面与图形栈，不代表已生成 Native AOT 二进制。

## 当前范围

- 批量导入、文件拖放和剪贴板图片。
- 马赛克、画笔、圈选、直线、高斯模糊；颜色、不透明度、圆／方形笔刷及圈选填充选择。
- 撤销／重做、逐张确认、PNG 文件夹和 ZIP 批量导出。
- 原图与笔画分离保存到 `%LOCALAPPDATA%\Mazhu`，保留原图，工作区原子替换写入。
- EXIF 方向规范化、sRGB 编辑，按像素尺寸重新编码 PNG。
- 标准窗口行为、Mica 背景、系统主题和原生控件可访问性标签。
- 参考 2026 年 10 月新版 Photos Editor：集成顶栏、圆角画布容器、右侧工具分组、底部缩放条；图片列表按需展开。设计参考和响应式约定见 [DESIGN.md](DESIGN.md)。
- 半透明笔刷光标按窗口逻辑像素显示，新笔刷的屏幕大小不随图片缩放改变；切图只在画布内显示加载提示，连续切图以最后选择为准。
- 单实例保护，防止两个进程同时写工作区。

Windows 与 macOS 目前使用独立的工作区格式，不自动读取或迁移 Mac 数据。HEIC、WebP 等解码能力取决于 Windows 安装的编解码器；文件选择列表不代表所有机器都能解码。

## 构建

使用 Windows 11、.NET 8 SDK 和 PowerShell 7。命令行构建所需的 Windows 工具由 NuGet 还原，也可使用 Visual Studio 2022 的 WinUI 应用开发组件。工程的 API 最低目标为 Windows 10 2004，但当前验收目标是 Windows 11，Windows 10 尚未验证。

```powershell
./windows/build.ps1 -Architecture x64 -Check
./windows/build.ps1 -Architecture ARM64
```

生成目录为 `windows/dist/x64` 或 `windows/dist/ARM64`，启动 `Mazhu.exe`。直接分发构建目录时需要完整目录，包括 `.xbf` 和 `Mazhu.pri` 界面资源。正式发行通过安装 EXE 将这些文件一起安装。GitHub Actions 支持两种架构构建，x64 另执行生成图片的渲染检查；检查失败时脚本输出异常详情，日志位于对应构建目录的 `render-checks-failure.txt`。

本地生成安装包还需要 Inno Setup 6：

```powershell
./scripts/package-windows.ps1
```

脚本执行 x64 构建及渲染检查、核对运行文件、编译安装程序并输出 SHA-256，生成 `release/Mazhu-1.6.6-windows-x64.exe`。后续版本的文件名跟随项目版本。配置见 `packaging/windows.iss`；双平台正式发布步骤见 [发布指南](../docs/RELEASING.md)。

## 操作

| 操作 | 快捷键 |
| --- | --- |
| 导入／粘贴 | Ctrl+O / Ctrl+V |
| 撤销／重做 | Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y |
| 适应窗口／实际像素 | Ctrl+0 / Ctrl+1 |
| 指针位置缩放 | Ctrl+滚轮 |
| 放大／缩小 | Ctrl++（也支持 Ctrl+=）/ Ctrl+-，支持数字小键盘 |
| 笔刷缩小／放大 | 画布聚焦后 [ / ]，每次 4 DIP |
| 鼠标调整笔刷 | 画布内 Alt+滚轮，每次 4 DIP |
| 上下移动图片 | 滚轮上下滚动 |
| 左右移动图片 | Shift+滚轮，或横向滚轮／触控板横向滚动 |
| 拖动图片 | 按住鼠标右键或中键拖动 |
| 上／下一张，确认 | 画布聚焦后 ← / → / Enter |
| 取消当前笔画 | Escape |

圈选工具使用十字指针；按住左键绘制时显示实线路径及返回起点的闭合虚线，松开后应用效果并隐藏提示线，Escape 取消。提示线只用于编辑定位，不会写入导出图片。笔刷指针使用半透明填充和单层细描边。

笔刷／线宽按窗口逻辑像素计量，图片缩放不改变新笔刷的屏幕大小；落笔时换算为原图坐标保存，已画好的笔画仍随图片一起缩放。图片导入时统一为 96 DPI 的编辑坐标，不重采样原像素，避免照片的 DPI 元数据造成原图和马赛克错位。

鼠标悬停在任意参数滑条或底部缩放滑条上即可滚轮调节，无需先单击；向上增加、向下减少，到达上下限后停止。每格滚轮分别调整笔刷／线条宽度 4 DIP、马赛克颗粒 2 px、模糊强度 1、不透明度 5 个百分点；缩放按滑条的对数刻度调整。滑条会消耗滚轮事件，避免同时滚动面板或移动画布。

可以从资源管理器把一张或多张图片拖到 App 的画布、侧栏或其他内容区域；拖入时显示“添加到图片列表”，松开后追加导入，自动展开图片列表并显示第一张新图片。源文件保留。

## 验证状态与后续工作

2026-10-19 在 Windows 11 x64 使用 .NET SDK 8.0.426 完成 Release 发布，并实际启动检查进程，通过 `RenderChecks.cs` 的全部断言，覆盖遮盖区域、圈选外像素不变、方形连续笔画、模糊保留先前遮盖、历史重放、PNG 导出尺寸及透明度。ARM64 已交叉编译成功，尚未在 ARM64 设备启动。检查只使用临时生成的图片，不读取用户工作区。这些结果不代表鼠标、触控笔、可访问性或全部导入导出流程已经人工验收。

v1.6.6 的云端 x64／ARM64 构建、x64 渲染检查、安装 EXE 编译和运行文件核对均已通过。尚未完成所有设备和交互场景的人工验收；后续回归清单为：

1. x64 / ARM64 编译与启动，确认无缺失的运行时依赖。
2. 鼠标、触控笔、失去指针捕获、缩放平移及高 DPI 跨屏验证。
3. 中文路径、透明图、带方向照片、编解码器缺失、大图导入及导出像素核对。
4. 工作区恢复、写入失败、损坏数据保留、重复启动及多图导出验证。
5. Narrator、键盘操作、深浅色、高对比度和窄窗口可用性检查。

已在实际窗口检查浅色宽窗口、深色窄窗口、空工作区、工具参数切换、侧栏、确认后进入下一张和末张导航禁用状态；实际涂抹与 Ctrl+Z 撤销还核对了临时工作区的保存记录。图片列表目前以内联侧栏展开，切图后保持展开。完整人工验收清单仍适用。独立视觉检查模式与生成示例图片的使用方式见 [DESIGN.md](DESIGN.md#视觉检查)。

左侧列表支持 Ctrl 多选、Shift 连选、空白处框选及拖动排序。右键图片卡片可从当前批次移除图片；多选后右键已选卡片可一起移除，原文件保留。移除当前图片后优先显示后面的图片，末张则回到前一张，全部移除后恢复空画布。顶栏的非按钮区域交由系统处理拖动、双击最大化／还原及系统菜单，保留原生窗口按钮和贴靠能力。

切换图片最多保留最近 3 张的解码及编辑预览，估算 GPU 缓存预算 256 MiB，超出后释放最久未使用项；单张超预算时只保留当前图片，不降低画质。编辑与撤销同步更新缓存。模糊笔画改用 GPU 内复制，避免逐笔读回整张图片再上传。2026-10-20 本机合成 3840×2160 JPEG、含 6 笔模糊的三轮测试，完成渲染的中位耗时从 361 ms 降至 81 ms；这不是所有用户图片的通用耗时。生成 1200×800 图片的缓存切换逻辑检查约 5.6 ms／次，不含屏幕呈现。可用 `Mazhu.exe --ui-checks --switch-benchmark` 复测，结果写入工作目录的 `switch-performance.json`；用 `--ui-checks --slow-load --workflow-checks` 检查切图队列、缓存编辑一致性、窗口命中区域及移除后的工作区持久化。

尚未与 Mac 版对齐的功能包括重置等。持续涂抹时复用已完成的画面和临时渲染目标，每帧只绘制当前笔画；松开时直接采用最后一帧，撤销／重做仍按历史重建。侧栏缩略图显示导入的原图；完整人工验收清单仍适用。

设计与 API 参考：[WinUI](https://learn.microsoft.com/windows/apps/winui/winui3/)、[Win2D](https://learn.microsoft.com/windows/apps/develop/win2d/quick-start)、[DPI](https://learn.microsoft.com/windows/apps/develop/win2d/dpi-and-dips)。沿用仓库根目录的 GPL-3.0-only 许可。

持续涂抹性能检查：`Mazhu.exe --ui-checks --stroke-benchmark`，使用合成 3840×2160 图片、30 笔历史记录和 20 次当前笔画更新，同时对比完整重放与当前笔画渲染，并核对最终像素完全一致。2026-10-20 本机中位完成耗时约 20.2 ms → 2.8 ms；不等同于所有图片的屏幕帧率。结果写入工作目录的 `stroke-performance.json`。
