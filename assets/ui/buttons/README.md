# 可替换的按钮背景

三种样式：common（通用）、dialogue（对话选项）、save_slot（存档卡片）。common／dialogue各6张PNG，save_slot通过配置共用common。直接覆盖同名图，Godot导入后重启游戏即可；无需运行生成器。

每套均为normal、hover、pressed、hover_pressed、disabled、focus。当前使用20261124交付的common／dialogue皮肤，save_slot复用common六态。交付focus中心不透明，配置focus_draw_center=false仅绘制焦点边缘；改成透明中心叠加图后才可启用中心绘制。其他图不含文字，九宫格与内容边距读取data/button_skins.json。

完整说明见 [美术与音频](../../../docs/美术与音频.md)。路径和边距配置在 `data/button_skins.json`。save_slot直接共用common六态，实际保留12张PNG；请勿运行export_button_skins工具覆盖已编辑贴图。
