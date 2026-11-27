# 许可证与素材来源

## 项目内容

项目的原创代码、配置、文档及由项目贡献者提供并有权授权的内容按根目录 [MIT许可证](LICENSE) 开源。第三方内容遵守其自身许可证；根MIT协议不覆盖第三方的保留权利，也不将素材来源记录当作外部权利人的授权证明。

AI主要参与代码编写和图片生成。当前美术与音频由项目协作交付接入，没有依据认定音乐为AI生成，不填写未提供的作者身份、模型名称或额外素材授权。新增外部素材时，应同时提交其来源与许可；已有第三方许可不得移除。

## Noto Sans SC中文字体

- 运行文件：`assets/fonts/NotoSansSC.woff2`。
- 来源：[Google Fonts / Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)。
- 许可证：[SIL Open Font License 1.1](assets/fonts/OFL.txt)。原许可声明为Copyright 2014–2021 Adobe，保留名称为Source；以随附OFL原文为准。
- 由完整可变TTF转换为WOFF2，保留31,036字形及字重，仅Web版加载；没有裁剪台词子集。转换记录和哈希在[字体说明](assets/fonts/README.md)。
- 分发字体或包含字体的Web包时须保留原许可证，不能将字体重新许可为MIT。

## Godot引擎

工程使用[Godot 4.5.1](https://godotengine.org/)，引擎采用[MIT许可证](https://godotengine.org/license/)，其集成库分别使用自身许可。本仓库不包含编辑器或导出模板二进制；发布游戏时应同时保留引擎与相应第三方组件的版权和许可说明。

引擎版权声明：Copyright (c) 2014-present Godot Engine contributors；Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur。完整引擎条款及依赖清单可从[对应版本LICENSE](https://github.com/godotengine/godot/blob/4.5.1-stable/LICENSE.txt)和[COPYRIGHT](https://github.com/godotengine/godot/blob/4.5.1-stable/COPYRIGHT.txt)取得；不能用项目MIT替代这些声明。

## 协作素材批次

| 内容 | 来源记录 | 当前保留位置 |
| --- | --- | --- |
| 酒馆、道具、顾客与初始角色卡 | 2026-11-22 dark贴图交付 | `assets/`及图片索引。 |
| 木金按钮与面板 | 2026-11-24 UI皮肤交付 | `assets/ui/`；存档按钮直接共用common纹理。 |
| 商人、银行家、富豪立绘 | 2026-11-27同行立绘交付 | `assets/portraits/companions/`。 |
| 15份操作音 | 2026-11-24音效交付 | `assets/audio/sfx/`。 |
| 4首BGM | 2026-11-27 BGM交付 | `assets/audio/music/`。 |
| 剧情与玩法策划 | 保留的最新方案及当前数据 | `docs/sources/`、`data/story.json`及相关规则JSON。 |

已展开并接入的交付ZIP及其重复文件在文档整理中移除；运行素材仍保留。清单是来源追溯，不承诺未提供的外部授权条款。
