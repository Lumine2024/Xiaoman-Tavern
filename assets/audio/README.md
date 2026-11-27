# 音频交付入口

完整清单与制作规格：[美术与音频](../../docs/美术与音频.md)。

已接入15份操作音Ogg和4首BGM，共19份Ogg覆盖21个ID，另18个待交付。标题／开场用title.ogg、接待用bar.ogg、商店用shop.ogg、对手上门用rival.ogg；选人／挂牌／结局回退bar，环境声仍缺，抽签两声为试听稿。映射以data/audio.json为准；来源与许可证见根THIRD_PARTY_NOTICES.md。重复交付ZIP已移除。

- `music/`：7个音乐ID，已交付4首Ogg；music.market读取shop.ogg。
- `ambience/`：3条环境声，默认Ogg。
- `sfx/`：29类音效，15份现有文件为Ogg，其余接口默认WAV。

路径、变体、循环及单条音量在 `data/audio.json`。按清单同名放入，打开Godot完成导入再运行即可；没有文件的项目保持静音。请勿把交付中的“待制作”理解为已经有正式音频。

检查：`godot --headless --path . --script tools/check_audio.gd`。
