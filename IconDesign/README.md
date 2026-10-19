# 当前图标

白色圆角底板、圆形玻璃透镜和 7×7 灰度马赛克。当前配方使用正向折射 70、边缘高度 6%、色散 45。

- `Selected7x7/mosaic.svg`：49 块平面灰度矩形。
- `Selected7x7/lens.svg`：圆形透镜形状。
- `Selected7x7/outside.svg`：圆外白色遮罩。
- `Selected7x7/recipe.json`：完整材质与导出配方。
- `AppIcon-1024.png`：最终渲染图。
- 根目录 `AppIcon.icns`：App 使用的静态图标。

用 [Liquid Composer](https://github.com/frontedu/liquid-composer) 提交 `3184413f7d267e260f84b080295450229485665a`，按其文档安装、构建后运行：

```sh
node scripts/agent/cli.mjs apply /绝对路径/Selected7x7/recipe.json --out /绝对路径/输出目录
```

配方不依赖个人目录。图标来自该项目 WebGL2 引擎的实际渲染，底图素材没有预画扭曲或彩边。
