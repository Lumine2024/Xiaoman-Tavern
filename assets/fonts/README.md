# Web 中文字体

`NotoSansSC.woff2` 来自 Google Fonts 发布的 Noto Sans SC 完整可变字库，保留全部字形与字重，仅用 FontTools / Brotli 转换为 WOFF2 容器，未做台词子集裁剪。

- 来源：https://github.com/google/fonts/tree/main/ofl/notosanssc
- 原始文件：https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf
- 许可证：同目录 `OFL.txt`（SIL Open Font License 1.1）。Web 交付目录同时附带该许可证。
- 用途：`main.gd._setup_theme()` 仅在 `web` 特性启用时加载；Windows 保持原系统字体，Windows 导出过滤此目录。

字体自身为运行资源，不能将本目录标记为 `.gdignore`。许可证由 Web 预设的 `include_filter` 显式保留。字体的导入设置 `.import` 需保留；二进制缓存仍在 `.godot/`。

原始TTF的SHA256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。
WOFF2的SHA256：`bc91cca665dd087211bafb59e9dcfe19e5d3cd4991ed0b086d6741fb4073cbbf`。
