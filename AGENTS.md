# 小漫特调：Agent与开发协作入口

核对日期：2026-11-28。适用于本目录及所有子目录。这里保存当前实现约定，不追加重复的逐日流水账；功能变更时同步更新对应主题文档和测试。

## 先建立正确上下文

1. 阅读根 [README.md](README.md)，理解玩家流程。
2. 阅读 [docs/README.md](docs/README.md)，按任务选择专题。
3. 以运行代码、`data/` 和当前专题指南核实行为；`docs/sources/` 是策划依据，不代表其中全部提案已经实现。

Godot **4.5.1标准版**、纯GDScript、Compatibility渲染；入口 `project.godot` → `scenes/main.tscn` → `scripts/game/main.gd`。逻辑1440×900、默认1280×800、`canvas_items`缩放。Windows使用系统中文字体，Web单独加载随仓库分发的开源字库。无需C#或.NET构建。

当前规模：32款配方、14位顾客、恰好5位同行者、6位对手，经营存档仅v8。当前版本为验收版；未量化的规则不自行补完，不能将提案、离线模拟或接口接通写成已完成内容。

## 不可擅改的业务约定

- 主题是「同行（hang）」。叙事依靠关系、陪伴、交谈与情境推动；教程由老酒保陪玩家接待，不用脱离人物的机械说明替代现有叙事。
- 普通新轮次：抽对手 → 选同行 → D0采购／升级与对策准备 → D1挂牌。同行锁定十四晚，下一轮才可重选。固定首夜教程独立于普通竞争。
- 普通开局360金，六个基酒家族各600mL，辅料为零；朗姆等级共用库存与FIFO成本。正常订单不按可制酒筛选、不自动补货；缺料送客，不扣料／收入／推进剧情或抽消息。
- 接待有三段交谈：段二普通行情、段三对手动作及顾客长线；特殊顾客、固定教程和鉴定师遵守各自现有流程。不能只依据策划原稿把段位改回旧顺序。
- 原料D日预告、D+1改价，涨3晚／跌2晚从生效日计算；潮流不因玩家听见才生效。商店价签必须对应真实包价和实际扣款。
- 挑战D0不计天，D14最后一客结束后结算。保留世界日历、资产、等级、顾客记忆及普通事件；只重置本轮成绩与对手压力。失败重试使用D0快照，不能重复领取富豪投资或银行家利息。
- 所有采购和消耗按实际FIFO成本，失误明细与收入、质量计分使用同一总数；不能通过改参考结果掩盖数值回归。
- 接待中保存使用顾客起点检查点。消息整理只同步手账字段，不保存半杯经济／RNG状态。无效当前档不得污染内存或覆盖健康备份；v1–7旧经营档按现规则删除。
- 没有定义的永久成长、递增难度、奖励、供货处罚、替代原料或救济金继续留空。扩展规则必须有明确业务依据，不能把待选对策占位实现成自造机制。

## 目录与入口

| 路径 | 用途 |
| --- | --- |
| `scripts/game/` | main主流程、resource_data JSON深复制、story_catalog文本装配、daily_events每日事件、companion_progress同行进度、run_progress周目。 |
| `scripts/brewing/` | brew调酒与原始失误、mistake_report最终失误汇总。 |
| `scripts/economy/` | pricing实时定价、stock_ledger FIFO及日报；order_planner仅保留教学／独立规则试算，非普通订单入口。 |
| `scripts/competition/` | competition既有竞争集成、street_rival卡恩压力与船长回访、challenge十四天公开目标。 |
| `scripts/persistence/` | save_schema v8校验、save_store原子写入及备份、save_slots栏位与共享教程。 |
| `scripts/audio/` | audio_director：独立RNG、音乐淡变、循环、音效池及四路音量。 |
| `scripts/ui/` | shop_view、journal_view、challenge_view、pause_menu、button_skin、scene_transition；bar/真实物件，focus/原场景镜头，tutorial/聚光，selection/选人。 |
| `data/` | 25份运行JSON及1份开发图片索引元数据；职责见开发指南。 |
| `assets/` | 实际运行的图片、Shader、Ogg与Web字体；路径通过JSON或代码引用。 |
| `tests/suites/`、`tests/fixtures/` | 回归脚本、外置输入、独立金标准；均属源码。 |
| `tools/` | 标准库Python导入／索引／定价参考，以及Godot音频检查／显式按钮模板导出。 |
| `docs/` | 当前主题指南、Word报告与必要策划原稿；总文档数控制在20以内。 |
| `exports/` | 本地构建产物，Git忽略，不作为运行源码或测试依据。 |

## 修改方式

所有台词优先改 `data/story.json`；按钮与界面文案在 `interface.json`，同行阈值在 `companions.json`，公开目标在 `challenges.json`，价格权威为 `prices.json`，具体顾客裁决在 `rulings.json`。不要用旧DOCX整文件重导覆盖已合并台词与次日行情。

运行JSON统一经 `resource_data.gd` 的ResourceLoader读取并深复制，不能把共享缓存对象暴露给局内修改。FileAccess主要用于 `user://`；新增原始 `res://` 文本读取时须设置导出包含／Keep File并验包。

资源先检查代码、场景和运行JSON的动态引用。`asset_index_labels.json` 是开发索引，不能单凭索引引用判定运行资源在用；测试夹具也不能冒充实际使用。后备图、朗姆等级图、条件加载的Web字体属于有效引用。删除资源时一并删除该资源自己的 `.import`／`.uid`，同步映射和图片索引；其余稳定UID与导入参数必须保留。新增素材说明来源及许可证。

三套按钮样式仍为common／dialogue／save_slot；save_slot直接复用common六态路径，实际按钮PNG共12张。不要恢复六份相同纹理副本。`export_button_skins.gd`只在明确重建模板时运行，会覆盖手绘皮肤。

脚本输入、测试数据、预期结果及可变配置放入外部参数／JSON；除固定接口与格式约定外，不硬编码。文档使用仓库相对路径，命令以 `godot`／`python` 为入口；不写本机盘符、用户名、绝对目录或私人临时日志位置。

## 验证与导出

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/suites/smoke.gd
godot --headless --path . --script tests/suites/save_system.gd
```

按修改范围补专项：定价／成本跑economy并核对独立定价参考；同行跑companions；挑战跑challenge_rules、update_20261125；文本跑story_catalog、tutorial；界面跑对应图形专项。命令、测试重点和验收边界见 [docs/验收与边界.md](docs/验收与边界.md)。长文案／布局需实际查看1280×800及1440×900，headless通过不能代替画面验收。不要运行测试时覆盖或清理玩家真实存档；日志／截图放调用者提供的输出位置或系统临时目录。

预设 `Windows Desktop` 导出x86_64单EXE内嵌PCK；预设 `Web` 导出单线程HTML／JS／WASM／PCK整目录。必须使用同版本标准编辑器和导出模板；.NET编辑器即使面对纯GDScript也拒绝Web导出。全资源模式保障JSON动态引用，docs／tests／tools／exports等由 `.gdignore` 和过滤器排除。只在源码目录外测试发行包，防止误读工作区资源。Web通过HTTP服务验证中文、首次点击音频解锁和IndexedDB恢复。

## 当前边界与维护

五位同行均有立绘，三位经济同行有独立目标及成功收束；普通／失败只实现现有标题，法官／教皇没有新造专属目标。六位对手都有公开十四天目标，实质压力首批为卡恩；其余五位完整营业AI、六条完整顾客长线、温控和复杂演出未接入。共有19份Ogg覆盖21个音频ID，另18个ID未交付；选人／挂牌／结局回退接待曲，环境声缺失。完整说明见验收文档。

本轮清理将历史接入记录合并为主题指南，保留最新版策划原稿，删除重复交付ZIP、退役旧贴图归档、展开的音频／UI副本及旧黑色抠像材质，并去重存档按钮纹理。不要恢复失效历史文档作为入口。根许可证为MIT，字体及引擎等第三方条款见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

清理后实跑smoke 5147、按钮195、美术96、存档54、商店音频55项零断言失败；存档退出仍有ObjectDB／资源清理提示。19份文档的链接与绝对文件路径检查通过，Word四页已渲染查看；未重新导出已有发行包。详细边界和工具验证见验收文档。
