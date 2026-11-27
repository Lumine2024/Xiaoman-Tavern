extends CanvasLayer
## Always processes so the modal owns Esc while the rest of the tree is paused.
var game
var settings: Dictionary
var panel: Control
var content: VBoxContainer
var opened = false
var prior_focus: Control
var fullscreen = false
var reduced_motion = false
var title_mode = false
var view = "menu"
var page_transition
var journal

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = game.interface.menu
	journal = preload("res://scripts/ui/journal_view.gd").new(self)
	layer = int(settings.layer)
	var config = ConfigFile.new()
	if config.load(settings.settings_path) == OK:
		fullscreen = bool(config.get_value("display", "fullscreen", false))
		reduced_motion = bool(config.get_value("display", "reduced_motion", false))
	_apply_display()
	panel = ColorRect.new()
	panel.color = Color(0.015, 0.03, 0.04, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center = CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content = game._panel(center, 520)
	content.get_parent().add_theme_stylebox_override("panel", preload("res://scripts/ui/button_skin.gd").panel(game.button_skins.panel))
	panel.theme = game.theme
	panel.hide()
	page_transition = preload("res://scripts/ui/scene_transition.gd").new()
	page_transition.game = game
	page_transition.provide_backdrop = false
	page_transition.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(page_transition)
	page_transition.layer = int(game.bar_ui.transitions.menu_layer)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB and game.screen == "game":
		if opened and view == "journal": close()
		else: open_journal()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if opened: close()
		elif game.screen not in ["title", "selection"]: open()
		get_viewport().set_input_as_handled()

func open(only_settings = false) -> void:
	if opened: return
	prior_focus = get_viewport().gui_get_focus_owner()
	opened = true
	title_mode = only_settings
	get_tree().paused = true
	game.sound.set_paused(true)
	panel.show()
	if only_settings: show_settings()
	else: show_menu()
	if not page_transition.busy: page_transition.begin()

func close() -> void:
	if not opened: return
	page_transition.cancel()
	opened = false
	panel.hide()
	get_tree().paused = false
	game.sound.set_paused(false)
	game._sfx("sfx.ui_back")
	if is_instance_valid(game.scene_transition) and not game.scene_transition.busy:
		game.scene_transition.begin()
	if is_instance_valid(prior_focus) and prior_focus.is_visible_in_tree(): prior_focus.grab_focus()

func show_menu() -> void:
	view = "menu"
	content.get_parent().custom_minimum_size.x = 520
	game._clear(content)
	game._label(content, settings.heading, 30, game.GOLD)
	game._label(content, "第 %d 周目 · 第 %d 日" % [game.progress.cycle, game.day], 18)
	game._label(content, settings.checkpoint, 15, game.MUTED).custom_minimum_size.x = 470
	game._button(content, settings.resume, close).grab_focus()
	game._button(content, settings.save, show_slots.bind("save"))
	game._button(content, settings.load, show_slots.bind("load"))
	game._button(content, settings.settings, show_settings)
	game._button(content, settings.title, func():
		if game._save_manual():
			close()
			game.show_start())
	game._button(content, settings.quit, func():
		if game._save_manual():
			close()
			get_tree().quit())

func show_settings() -> void:
	view = "settings"
	content.get_parent().custom_minimum_size.x = 520
	game._clear(content)
	game._label(content, settings.settings, 30, game.GOLD)
	var full = CheckButton.new()
	full.text = settings.fullscreen
	full.button_pressed = fullscreen
	content.add_child(full)
	full.toggled.connect(func(value):
		fullscreen = value
		_apply_display()
		_store_settings())
	var motion = CheckButton.new()
	motion.text = settings.reduced_motion
	motion.button_pressed = reduced_motion
	content.add_child(motion)
	motion.toggled.connect(func(value):
		reduced_motion = value
		_store_settings())
	for group in game.sound.levels:
		game._label(content, game.sound.manifest.settings.labels[group], 16)
		var slider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = float(game.sound.manifest.settings.volume_step)
		slider.value = float(game.sound.levels[group])
		slider.name = "Audio_" + str(group)
		content.add_child(slider)
		slider.value_changed.connect(func(value):
			game.sound.set_level(group, value)
			_store_settings())
	game._button(content, settings.back, close if title_mode else show_menu).grab_focus()

func show_slots(kind: String) -> void:
	view = kind
	game._clear(content)
	content.get_parent().custom_minimum_size.x = 940
	var labels: Dictionary = game.interface.slots
	game._label(content, labels["heading_" + kind], 28, game.GOLD)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for i in labels.auto_paths.size():
		_slot_card(grid, labels.auto_paths[i], labels.auto % (i + 1), kind, -1)
	for i in labels.manual_paths.size():
		_slot_card(grid, labels.manual_paths[i], labels.slot % (i + 1), kind, i)
	game._button(content, settings.back, close if title_mode else show_menu).grab_focus()

func _slot_card(grid: GridContainer, path: String, heading: String, kind: String, index: int) -> void:
	var document = game.save_slots.read(path)
	var occupied = game.save_slots.exists(path)
	var text = game.interface.slots.empty if not occupied else (game.interface.slots.invalid if document.is_empty() else game.save_slots.describe(document))
	var button = game._button(grid, heading + "\n" + text, func(): _slot_action(kind, path, index, occupied), false, "save_slot")
	button.custom_minimum_size = Vector2(415, 165)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = (kind in ["new", "save"] and index < 0) or (kind == "load" and document.is_empty())
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if occupied:
		var remove = game._button(button, game.interface.slots.delete, _confirm_delete.bind(path, heading, kind))
		remove.name = "DeleteSlot"
		remove.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		remove.offset_left = -95
		remove.offset_right = -10
		remove.offset_top = -43
		remove.offset_bottom = -8
		remove.disabled = game.screen != "title" and path == game.config.save_path
		if remove.disabled: remove.tooltip_text = game.interface.slots.delete_active

func _confirm_delete(path: String, heading: String, kind: String) -> void:
	var confirm = ConfirmationDialog.new()
	confirm.name = "DeleteSlotConfirm"
	confirm.theme = game.theme
	confirm.title = game.interface.slots.delete_title
	confirm.dialog_text = game.interface.slots.delete_confirm.format({"slot": heading})
	confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(confirm)
	confirm.confirmed.connect(func():
		var deleted = game.save_slots.delete_slot(path)
		if game.screen == "title": game.show_start()
		show_slots(kind)
		game._label(content, game.interface.slots.deleted if deleted else game.save_slots.store.last_error, 16)
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()


func _slot_action(kind: String, path: String, index: int, occupied: bool) -> void:
	var action = func():
		if kind == "new":
			close()
			game._begin_new_slot(index)
		elif kind == "load":
			var document = game.save_slots.read(path)
			if document.is_empty():
				game._label(content, game.save_slots.store.last_error, 16)
				return
			close()
			game._load_game(path)
		else:
			var snapshot = game.reception_checkpoint if game.playing and not game.reception_checkpoint.is_empty() else game._snapshot(game.current_phase)
			if game.save_store.write_snapshot(path, game.save_slots.stamped(snapshot, index), game.save_schema.decode):
				game.save_slots.active_slot = index
				game.config.save_path = path
				show_slots("save")
				game._label(content, settings.saved, 16, game.MINT)
			else: game._label(content, game.save_store.last_error, 16)
	if occupied and kind in ["new", "save"]:
		var confirm = ConfirmationDialog.new()
		confirm.theme = game.theme
		confirm.dialog_text = game.interface.slots.overwrite
		confirm.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(confirm)
		confirm.confirmed.connect(func():
			action.call()
			confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free)
		confirm.popup_centered()
	else: action.call()

func open_journal(section = "") -> void:
	if not opened: open()
	view = "journal"
	game._clear(content)
	content.get_parent().custom_minimum_size.x = float(game.interface.journal.panel_width)
	game._label(content, game.interface.journal.heading, 30, game.GOLD)
	journal.build(content, section)
	game._button(content, game.interface.journal.close, close).grab_focus()

func _journal_sections() -> Dictionary:
	var sections = {}
	var lines: Array[String] = []
	lines.append("同行者 · %s\n%s" % [game.companion.get("name", "尚未选择"), game.companion.get("description", "")])
	var captain: Dictionary = game.competition.state.street.captain
	if int(captain.visits) > 0: lines.append("船长 · 来过%d次\n上次说到：%s" % [captain.visits, captain.last_line])
	lines.append_array(game.companion_progress.lines(game))
	sections.companion = lines
	lines = []
	if game.challenge.state.phase in ["preparation", "active", "result"]:
		game.challenge.update_net(game.stock_ledger, game.day)
		for metric in game.challenge.rules.rivals[game.challenge.state.rival].metrics: lines.append(game.challenge_view.metric_text(metric))
	var rival = game.competition.rival()
	lines.append("\n同行竞争 · %s\n%s\n%s" % [rival.get("name", "暂无"), rival.get("change", ""), rival.get("pitch", "")])
	for template in ([] if game.competition.narrative() else game.interface.effect_templates.get(game.competition.state.rival, [])):
		lines.append(str(template).format(game.competition.profile()))
	if game.competition.narrative():
		var street: Dictionary = game.competition.state.street
		lines.append("开业对策：" + str(game.competition.street.data.cards.get(street.card, {}).get("name", "尚未选择")))
	lines.append("竞争声望 %d · 合作进度 %d · 永久客流 %+d" % [game.competition.state.reputation, game.competition.state.cooperation_days.size(), game.competition.state.permanent_traffic])
	lines.append("价策：%s · 市场原料涨跌 %+.0f%%" % [game.competition.content.policy_labels.get(game.competition.state.strategy, game.competition.state.strategy), float(game.competition.market(game.day).variation) * 100])
	lines.append("今日客流：%d · 顾客队列：%d\n%s" % [game.competition.state.today_traffic, game.queue.size(), game.competition.summary(game.day)])
	if not game.promotion.is_empty():
		lines.append("当前主推的综合客流增减：%+d（按规则上下限合并）" % game.competition.traffic_delta(game.promotion, game.day, game.pricing.calculate(game.promotion, game.tiers).price))
	if game.brew != null and game.guest_index < game.queue.size():
		var quote: Dictionary = game.queue[game.guest_index].get("quote", {})
		if not quote.is_empty():
			var modifiers = game.competition.modifiers(quote, game._find_recipe(game.brew.recipe.id), game.brew.cup != game.brew.recipe.cup, game.brew.ice != game.brew.expected_ice(), quote.tiers)
			lines.append("当前订单：%s · 标准价 ¥%d · 锁定价 ¥%d\n竞争收益倍率 ×%.2f · 小费倍率 ×%.2f" % [game.brew.recipe.name, quote.standard_price, quote.price, modifiers.revenue_multiplier, modifiers.tip_multiplier])
	sections.rival = lines
	lines = []
	lines.append("\n采购效果（普通 / 应急）：")
	for name in game.stock:
		var factor = game.competition.procurement_factor(name, game.day, game.tiers)
		var emergency = game.competition.procurement_factor(name, game.day, game.tiers, true)
		if factor != 1.0 or emergency != 1.0: lines.append("%s ×%.2f / ×%.2f" % [name, factor, emergency])
	lines.append("市场断货：")
	for name in game.competition.market(game.day).outages:
		if game.competition.sold_out(name, game.day): lines.append("%s · 持续至第 %d 日前" % [name, game.competition.market(game.day).outages[name]])
	lines.append("赊购 %d / %d · 还款日 %d\n锁价合同 %d · 结局 %s" % [game.competition.state.credit_used, game.competition.state.credit_limit, game.competition.state.credit_due_day, game.competition.state.locks.size(), game.competition.state.ending])
	for contract_day in game.competition.state.locks:
		var contract: Dictionary = game.competition.state.locks[contract_day]
		for name in contract.packs:
			lines.append("第 %s 日 · %s %d 包 · 已用 %d 包 · 基础包价 ¥%s" % [contract_day, name, contract.packs[name], contract.used.get(name, 0), str(contract.base_prices.get(name, ""))])
	sections.market = lines
	lines = []
	lines.append("\n经营记录\n第 %d 周目 · 第 %d 日 · ¥%d · 完成 %d / 接待 %d\n同行能力与难度：尚无额外效果" % [game.progress.cycle, game.day, game.money, game.day_success, game.day_served])
	lines.append("基酒等级：")
	for name in game.tiers: lines.append("%s Lv.%d" % [name, int(game.tiers[name]) + 1])
	lines.append("器材 Lv.%d · 经营贡献 ¥%.2f" % [game.equipment, game.stock_ledger.contribution()])
	lines.append("本日收入 ¥%d · 小费 ¥%d · 原料消耗 ¥%.2f · 采购现金 ¥%d · 隔夜损耗 ¥%.2f · 事件费用 ¥%d" % [game.stock_ledger.daily.liquor, game.stock_ledger.daily.tips, game.stock_ledger.daily.ingredients, game.stock_ledger.daily.procurement, game.stock_ledger.daily.spoilage, game.stock_ledger.daily.events])
	if game.stock_ledger.unknown_basis: lines.append("部分旧库存进价未知，成本基础不完整。")
	for record in game.competition.state.history:
		lines.append("竞争记录 · 第 %d 日 · 主推 %s" % [record.day, game._find_recipe(record.recipe_id).get("name", record.recipe_id)])
	for record in game.stock_ledger.history:
		lines.append("第 %d 日 · 贡献 ¥%.2f" % [record.day, record.contribution])
	sections.records = lines
	sections.messages = game.rumors.map(func(note): return game._journal_speaker_text(note) + "\n" + note)
	return sections

func _journal_text(section = "") -> String:
	var sections = _journal_sections()
	if not section.is_empty(): return "\n".join(sections.get(section, []))
	var lines: Array = []
	for key in game.interface.journal.sections: lines.append_array(sections[key])
	return "\n".join(lines)

func _apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _store_settings() -> void:
	var config = ConfigFile.new()
	config.load(settings.settings_path)
	for group in game.sound.levels: config.set_value("audio", group, game.sound.levels[group])
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "reduced_motion", reduced_motion)
	if config.save(settings.settings_path) != OK:
		game._label(content, settings.settings_error, 16)

func _exit_tree() -> void:
	if opened: get_tree().paused = false
