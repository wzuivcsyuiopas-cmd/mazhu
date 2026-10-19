# 发布指南

正式 Release 提供两个安装文件：`Mazhu-<版本>-macOS-arm64.dmg` 和 `Mazhu-<版本>-windows-x64.exe`。GitHub 自动附加的 Source code ZIP／tar.gz 是对应标签的源码，不是安装包。

## 准备版本

1. 更新 `Info.plist` 的 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。
2. 同步 `windows/Mazhu/Mazhu.csproj` 的 `Version` 和 `windows/Mazhu/app.manifest` 的四段版本号。两端发行版本必须相同，格式为 `主版本.次版本.修订号`。
3. 新建 `docs/releases/v<版本>.md`，写清下载文件名、系统要求、变化和已知限制，并同步根目录及 Windows README 中的版本和下载链接。
4. 在 Pull Request 中验证构建及打包，再合并到 `main`。修改发布工作流、打包脚本、安装配置或项目版本会触发 **Release packages** 的打包检查；PR 检查不会发布 Release。

## 正式发布

在 GitHub 仓库的 **Actions → Release packages → Run workflow** 中选择 `main`，运行工作流。两端均从该次运行的同一提交构建：

- macOS：执行核心检查和 App 构建，生成 DMG，验证镜像校验、挂载后的 App 签名、ARM64 架构、版本和 Applications 链接。
- Windows：构建自带运行时的 x64 应用并运行渲染检查，核对界面资源和运行文件，使用 Inno Setup 6 编译安装 EXE，验证文件头并输出 SHA-256。
- 发布：等待两端成功，下载两个产物，核对版本和文件，创建对应标签的草稿并上传两个文件；确认资产数量后才公开并设为 Latest。校验值自动追加到发行说明。

工作流见 [release.yml](../.github/workflows/release.yml)。Actions 的临时产物即使显示为 ZIP，正式 Release 中上传的仍是解包后的 DMG 和 EXE。

发布后核对 Release 的版本、Latest 标记、两个文件名、SHA-256 和对应标签提交。v1.6.6 已按此流程发布；构建检查通过不代表所有硬件、触控笔及可访问性场景都已人工验收。

## 本地打包

在仓库根目录运行，输出均位于 `release/`：

```sh
# Apple Silicon Mac，具备 macOS 26 SDK
zsh ./scripts/package-macos.sh
```

```powershell
# Windows，具备 .NET 8 SDK、PowerShell 7 和 Inno Setup 6
./scripts/package-windows.ps1
```

macOS 包目前使用 ad-hoc 签名，未进行 Apple 公证；Windows 安装包尚未进行代码签名。Windows 安装按当前用户进行，安装目录为 `%LOCALAPPDATA%\Programs\Mazhu`，运行依赖随包提供，卸载保留 `%LOCALAPPDATA%\Mazhu` 的工作区。

## 失败处理

构建或检查失败时，先查看对应任务日志并修复，未满足两端成功条件不会进入发布。发布过程中断时先检查是否留下草稿；同一提交的草稿允许重新上传，但已公开版本不会被工作流覆盖。已有标签指向其他提交时工作流会停止，应使用新的版本号，不要移动已公开的版本标签。仅文档更新无需重新运行发布或改动现有二进制包。
