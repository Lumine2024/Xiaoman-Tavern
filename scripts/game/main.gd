extends Control

const BrewModel = preload("res://scripts/brewing/brew.gd")
const Workbench = preload("res://scripts/ui/bar/workbench.gd")
const SaveStore = preload("res://scripts/persistence/save_store.gd")
const SaveSchema = preload("res://scripts/persistence/save_schema.gd")
const RunProgress = preload("res://scripts/game/run_progress.gd")
const Pricing = preload("res://scripts/economy/pricing.gd")
const Competition = preload("res://scripts/competition/competition.gd")
const OrderPlanner = preload("res://scripts/economy/order_planner.gd")
const StockLedger = preload("res://scripts/economy/stock_ledger.gd")
const JournalNotes = preload("res://scripts/game/journal_notes.gd")
const MistakeReport = preload("res://scripts/brewing/mistake_report.gd")
const GOLD = Color("dcb779")
const TEXT = Color("eee5d2")
const MUTED = Color("99b0ab")
const MINT = Color("91cbb5")

var config: Dictionary
var recipes: Array
var customers: Array
var companion: Dictionary
var money = 0
var day = 1
var equipment = 0
var tiers: Dictionary = {}
var stock: Dictionary = {}
var rumors: Array = []
var journal_favorites: Array = []
var journal_speakers: Dictionary = {}
var last_mistake_report: Dictionary = {}
var promotion: Dictionary
var queue: Array = []
var guest_index = 0
var brew
var guest: Dictionary
var remaining = 0.0
var guest_cost_start = 0.0
var stock_only_mode = false
var selection_step = "rival"
var dialogue = 0
var rapport = false
var pouring = false
var pouring_liquid = ""
var mixing = false
var mix_time = 0.0
var mix_position = 0.0
var playing = false
var day_income = 0
var day_served = 0
var day_success = 0
var selected_cup = ""
var selected_ice = ""
var page: VBoxContainer
var left: VBoxContainer
var right: VBoxContainer
var header_stats: Label
var time_label: Label
var timer_bar: ProgressBar
var dialogue_box: VBoxContainer
var shake_bar: Control
var status_line: Label
var recipe_option: OptionButton
var recipe_text: RichTextLabel
var ledger: RichTextLabel
var workbench: Control
var bar_assets: Dictionary
var character_art: Dictionary
var button_skins: Dictionary
var bar_ui: Dictionary
var active_tab = ""
var rng = RandomNumberGenerator.new()
var log_file: FileAccess
var save_store = SaveStore.new()
var save_schema
var progress = RunProgress.new()
var run_rules: Dictionary
var current_phase = "promotion"
var last_save_ok = true
var run_effects: Dictionary = {}
var storage_dialog: AcceptDialog
var pricing
var competition
var dialogue_rules: Dictionary
var dialogue_remaining = 0.0
var dialogue_effect: Dictionary = {}
var intel_level = "full"
var day_consumable_budget = 0.0
var daily_costs = 0
var dialogue_clock: Label
var stock_ledger = StockLedger.new()
var policy_option: OptionButton
var pending_open_plan: Dictionary = {}
var tutorial: Dictionary
var story_catalog
var tutorial_story: Dictionary
var tutorial_active = false
var tutorial_measure_read = false
var tutorial_hint: Label
var tutorial_director
var tutorial_context = ""
var tutorial_action: BaseButton
var tutorial_purchase_button: BaseButton
var interface: Dictionary
var pause_menu
var screen = "title"
var reception_checkpoint: Dictionary = {}
var save_slots
var drink_colors: Dictionary
var effects_label: Label
var scene_transition
var sound
var companion_progress = preload("res://scripts/game/companion_progress.gd").new()
var challenge = preload("res://scripts/competition/challenge.gd").new()
var challenge_view
var rulings: Dictionary

func _ready() -> void:
	config = _read_json("res://data/settings.json")
	rulings = _read_json("res://data/rulings.json")
	challenge_view = preload("res://scripts/ui/challenge_view.gd").new(self)
	interface = _read_json("res://data/interface.json")
	config.save_slot_count = interface.slots.manual_paths.size()
	sound = preload("res://scripts/audio/audio_director.gd").new()
	sound.game = self
	add_child(sound)
	bar_assets = _read_json("res://data/bar_assets.json")
	character_art = _read_json("res://data/character_art.json")
	bar_ui = _read_json("res://data/bar_ui.json")
	recipes = _read_json("res://data/recipes.json")
	customers = _read_json("res://data/customers.json")
	story_catalog = preload("res://scripts/game/story_catalog.gd").new(_read_json("res://data/story.json"))
	if not story_catalog.apply_customers(customers):
		push_error(story_catalog.last_error)
		return
	tutorial_story = story_catalog.content.tutorial
	pricing = Pricing.new(_read_json("res://data/prices.json"))
	# prices.json is authoritative; settings keeps only a migration-compatible shape.
	config.base_tiers = {}
	for family in pricing.catalog.base_families:
		config.base_tiers[family] = []
		for tier in pricing.catalog.base_families[family].tiers:
			config.base_tiers[family].append({"name": tier.label, "pack_price": tier.pack_price, "unlock_fee": tier.unlock_fee})
	config.equipment_price = pricing.catalog.other_prices.equipment_upgrade.price
	competition = Competition.new(_read_json("res://data/competition.json"))
	if not competition.dependency_ok():
		push_error("竞争规则要求的商品版本不匹配，已停止开局。")
		_setup_theme()
		_label(page, "商品或事件配置不匹配，请先核对配置与日志。", 24, GOLD)
		return
	dialogue_rules = _read_json("res://data/dialogue_rules.json")
	config.order_seconds = dialogue_rules.base_patience
	for recipe in recipes:
		recipe.price = pricing.calculate(recipe).price
	run_rules = _read_json("res://data/run_rules.json")
	save_schema = SaveSchema.new(config, recipes, customers)
	save_store.obsolete_check = save_schema.is_obsolete
	tutorial = _read_json("res://data/tutorial.json")
	drink_colors = _read_json("res://data/drink_colors.json")
	if not _valid_drink_colors():
		push_error("酒液颜色配置不完整或格式错误。")
		_setup_theme()
		_label(page, "请核对 data/drink_colors.json 的名称及八位色值。", 24, GOLD)
		return
	save_slots = preload("res://scripts/persistence/save_slots.gd").new()
	save_slots.game = self
	save_slots.store.obsolete_check = save_schema.is_obsolete
	save_slots.settings = interface.slots
	save_slots.default_path = config.save_path
	_setup_theme()
	tutorial_director = preload("res://scripts/ui/tutorial/tutorial_director.gd").new()
	tutorial_director.game = self
	add_child(tutorial_director)
	pause_menu = preload("res://scripts/ui/pause_menu.gd").new()
	pause_menu.game = self
	add_child(pause_menu)
	scene_transition = preload("res://scripts/ui/scene_transition.gd").new()
	scene_transition.game = self
	add_child(scene_transition)
	log_file = FileAccess.open(config.log_path, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(config.log_path, FileAccess.WRITE)
	if log_file == null:
		log_file = FileAccess.open("user://game.log", FileAccess.WRITE)
	if log_file:
		log_file.seek_end()
	_log("session_start", {"version": Engine.get_version_info().string})
	_initialize_stock()
	show_start()

func _read_json(path: String):
	return preload("res://scripts/game/resource_data.gd").read(path)

func _valid_drink_colors() -> bool:
	var pattern = RegEx.new()
	pattern.compile("^[0-9a-fA-F]{8}$")
	var expected = {"liquids": bar_assets.liquids.keys(), "drinks": recipes.map(func(recipe): return recipe.name)}
	for group in expected:
		if not drink_colors.get(group) is Dictionary or drink_colors[group].size() != expected[group].size(): return false
		for name in expected[group]:
			var value = drink_colors[group].get(name)
			if not value is String or pattern.search(value) == null: return false
	return true

func _setup_theme() -> void:
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
	ui_theme.default_font = font
	if OS.has_feature("web"):
		var web_font = FontVariation.new()
		web_font.base_font = load("res://assets/fonts/NotoSansSC.woff2")
		web_font.variation_opentype = {"wght": 400.0}
		ui_theme.default_font = web_font
	ui_theme.default_font_size = 17
	ui_theme.set_color("font_color", "Label", TEXT)
	ui_theme.set_color("font_outline_color", "Label", Color(interface.theme.outline))
	ui_theme.set_constant("outline_size", "Label", int(interface.theme.outline_size))
	ui_theme.set_color("default_color", "RichTextLabel", TEXT)
	button_skins = _read_json("res://data/button_skins.json")
	preload("res://scripts/ui/button_skin.gd").apply(ui_theme, button_skins)
	ui_theme.set_color("font_color", "Button", TEXT)
	ui_theme.set_color("font_outline_color", "Button", Color(interface.theme.outline))
	ui_theme.set_constant("outline_size", "Button", int(interface.theme.outline_size))
	ui_theme.set_color("font_disabled_color", "Button", Color(interface.theme.disabled))
	ui_theme.set_color("font_color", "OptionButton", TEXT)
	for control in ["CheckButton", "PopupMenu", "TabBar", "OptionButton"]:
		ui_theme.set_color("font_color", control, Color(interface.theme.font))
		ui_theme.set_color("font_disabled_color", control, Color(interface.theme.disabled))
	theme = ui_theme
	page = $Margin/Page

func _clear(node: Node) -> void:
	if node == page and is_instance_valid(sound): sound.stop_world_loops()
	if node == page and is_instance_valid(workbench):
		workbench.measure_focus.dismiss()
		workbench.mix_focus.dismiss()
		workbench.straight_focus.dismiss()
	if node == page and node.get_child_count() > 0 and is_instance_valid(scene_transition):
		scene_transition.begin()
	elif is_instance_valid(pause_menu) and node == pause_menu.content and node.get_child_count() > 0 and is_instance_valid(pause_menu.page_transition):
		pause_menu.page_transition.begin()
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String, font_size = 17, color = TEXT) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, disabled = false, skin = "common") -> Button:
	var button = Button.new()
	if skin != "common": button.theme_type_variation = button_skins.profiles[skin].theme_types[0]
	button.text = text
	button.disabled = disabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _row(parent: Node) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row

func _panel(parent: Node, min_width = 0) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = min_width
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.12, 0.135, 0.94)
	style.border_color = Color("3e5550")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column

func _scroll_column(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	return column

func _rich(parent: Node, text: String, min_height = 0) -> RichTextLabel:
	var rich = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.text = text
	rich.fit_content = true
	rich.custom_minimum_size.y = min_height
	rich.scroll_active = false
	parent.add_child(rich)
	return rich

func _header(section: String) -> void:
	var header = PanelContainer.new()
	header.name = "GameHeader"
	var header_style = _bar_style(Color("10282bf2"))
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header.add_theme_stylebox_override("panel", header_style)
	page.add_child(header)
	var row = _row(header)
	var title = _label(row, "小漫特调  /  " + section, 26, GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_stats = _label(row, "第 %d 周目 · 第 %d 日 · ¥%d" % [progress.cycle, day, money], 18, MINT)
	header_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	_button(row, interface.menu.journal, func(): pause_menu.open_journal())
	_button(row, interface.menu.hint, func(): pause_menu.open())
	effects_label = _label(page, _effects_summary(), 14, Color(interface.theme.muted))
	effects_label.name = "ActiveEffects"
	effects_label.add_theme_stylebox_override("normal", _bar_style(Color("11282bee")))
	if challenge.active():
		challenge.update_net(stock_ledger, day)
		var metrics: Array[String] = []
		for metric in challenge.rules.rivals[challenge.state.rival].metrics:
			metrics.append("%s %s/%s" % [metric.label, challenge_view.metric_number(metric.key, challenge.value(metric.key)), challenge_view.metric_number(metric.key, float(metric.target))])
		var score_line = _label(page, challenge.rules.text.progress.format({"day": challenge.day(day), "days": int(challenge.rules.days), "calendar": day}) + "　|　" + " · ".join(metrics), 14, MINT)
		score_line.add_theme_stylebox_override("normal", _bar_style(Color("11282bee")))

func _effects_summary() -> String:
	if companion.is_empty(): return ""
	var rival = competition.rival()
	if competition.narrative():
		return "同行者 %s：%s　|　街灯那头 %s · %s" % [companion.name, companion.description, rival.get("name", ""), competition.street.data.cards.get(competition.state.street.card, {}).get("name", "尚未选对策")]
	return "同行者 %s：%s　|　同行竞争 %s：%s" % [companion.name, companion.description, rival.get("name", "暂无"), (("生效中 · " if competition.active(day) else "待生效 · ") + rival.get("change", "")) if not rival.is_empty() else "无竞争效果"]

func _initialize_stock() -> void:
	money = int(config.starting_money)
	tiers.clear()
	stock.clear()
	for family in config.base_tiers:
		tiers[family] = 0
	for recipe in recipes:
		for item in recipe.ingredients + recipe.topup:
			stock[item.name] = float(config.opening_stock.base_ml if item.name in config.base_names else config.opening_stock.auxiliary_ml) if stock_only_mode else float(config.initial_stock)
	stock_ledger.reset(stock)
	if stock_only_mode:
		for name in rulings.rum.names:
			if name != rulings.rum.canonical: stock[name] = 0.0
		stock_ledger.reset(stock)

func show_start() -> void:
	sound.enter("title")
	screen = "title"
	tutorial_context = ""
	playing = false
	_clear(page)
	var layout = Control.new()
	layout.name = "TitleScreen"
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(layout)
	var title = _label(layout, interface.title.name, 48, GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size = Vector2(500, 100)
	title.position = Vector2(35, 25)
	var narration = _label(layout, story_catalog.content.opening.title, 23, TEXT)
	narration.position = Vector2(35, 170)
	narration.size = Vector2(650, 240)
	var buttons = VBoxContainer.new()
	buttons.name = "TitleActions"
	layout.add_child(buttons)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	buttons.position = Vector2(-330, -130)
	buttons.custom_minimum_size.x = 280
	buttons.add_theme_constant_override("separation", 22)
	_button(buttons, interface.title.start, _new_game_browser)
	_button(buttons, interface.title.continue, _load_browser, not _has_save())
	_button(buttons, interface.title.settings, func(): pause_menu.open(true))
	_button(buttons, interface.title.quit, func(): get_tree().quit())

func _has_save() -> bool:
	if save_slots.managed(): return save_slots.any_exists()
	return FileAccess.file_exists(config.save_path) or FileAccess.file_exists(config.save_path + ".bak")

func _new_game_browser() -> void:
	pause_menu.open(true)
	pause_menu.show_slots("new")

func _load_browser() -> void:
	pause_menu.open(true)
	pause_menu.show_slots("load")

func _begin_new_slot(index: int) -> void:
	var shared = save_slots.profile_state()
	if shared.is_empty():
		_storage_notice(interface.slots.profile_error)
		return
	if shared.tutorial_completed and not save_slots.complete_tutorial():
		_storage_notice(save_slots.store.last_error)
		return
	save_slots.active_slot = index
	config.save_path = interface.slots.manual_paths[index]
	if shared.tutorial_completed:
		progress.reset()
		progress.advance()
		competition.reset("")
		_reset_run(config.companions[0], true)
	else: _show_opening(0)

func _show_opening(index: int) -> void:
	screen = "opening"
	tutorial_context = ""
	playing = false
	_clear(page)
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var box = _panel(center, int(interface.opening.text_width))
	_label(box, story_catalog.content.opening.speaker, 22, GOLD)
	_label(box, story_catalog.content.opening.pages[index], int(interface.opening.font_size))
	var last = index == story_catalog.content.opening.pages.size() - 1
	_button(box, interface.opening.finish if last else interface.opening.next, func():
		if last: _begin_tutorial()
		else: _show_opening(index + 1)).grab_focus()
	_button(box, interface.opening.back, show_start)

func _choose_companion(item: Dictionary) -> void:
	progress.reset()
	progress.advance()
	tutorial_active = progress.cycle == 1
	competition.reset("")
	_reset_run(item)

func _show_rival_selection(_item: Dictionary = {}) -> void:
	sound.enter("selection")
	screen = "selection"
	tutorial_context = ""
	_clear(page)
	var selection = preload("res://scripts/ui/selection/character_selection.gd").new()
	selection.settings = _read_json("res://data/character_selection.json")
	selection.sound = sound
	selection.artwork = character_art
	if pause_menu.reduced_motion: selection.settings.spin_seconds = 0.0
	selection.rival_mode = true
	for id in competition.data.rivals:
		var entry: Dictionary = competition.data.rivals[id].duplicate(true)
		entry.id = id
		selection.entries.append(entry)
	page.add_child(selection)
	selection.confirmed.connect(_rival_drawn)
	selection.back_requested.connect(show_start)

func _show_companion_selection() -> void:
	sound.enter("selection")
	screen = "selection"
	tutorial_context = ""
	_clear(page)
	var selection = preload("res://scripts/ui/selection/character_selection.gd").new()
	selection.settings = _read_json("res://data/character_selection.json")
	selection.sound = sound
	selection.artwork = character_art
	if pause_menu.reduced_motion: selection.settings.select_seconds = 0.0
	selection.settings.companion_hint = "街灯那头是%s。选一位与你同行的人。" % competition.rival().get("name", "")
	selection.entries = config.companions.duplicate(true)
	page.add_child(selection)
	selection.confirmed.connect(func(item): _begin_rival_run(item, competition.state.rival))
	selection.back_requested.connect(show_start)

func _begin_rival_run(item: Dictionary, id: String, skip_preparation = false) -> void:
	if progress.cycle == 1: progress.advance()
	tutorial_active = progress.cycle == 1
	competition.reset(id)
	_reset_run(item, false, skip_preparation)

func _begin_tutorial() -> void:
	tutorial_measure_read = false
	progress.reset()
	tutorial_active = progress.cycle == 1
	competition.reset("")
	_reset_run(config.companions[int(tutorial.companion_index)])

func _reset_run(item: Dictionary, select_characters = false, skip_preparation = false) -> void:
	challenge.state = challenge.fresh()
	companion_progress.state = companion_progress.fresh(item.id)
	competition.round_offset = 0
	competition.street.challenge_mode = false
	tutorial_active = progress.cycle == 1
	reception_checkpoint = {}
	rng.seed = int(tutorial.seed) if tutorial_active else int(Time.get_unix_time_from_system() * 1000000.0)
	_log("run_seed", {"seed": str(rng.seed), "tutorial": tutorial_active})
	pending_open_plan = {}
	competition.reset("" if select_characters else competition.state.rival)
	selection_step = "rival"
	stock_only_mode = not tutorial_active and not skip_preparation and (select_characters or not competition.state.rival.is_empty())
	playing = false
	pouring = false
	mixing = false
	brew = null
	guest = {}
	companion = item
	day = 0 if stock_only_mode else 1
	equipment = 0
	rumors.clear()
	journal_favorites.clear()
	journal_speakers.clear()
	last_mistake_report = {}
	if is_instance_valid(pause_menu): pause_menu.journal.reset()
	queue.clear()
	guest_index = 0
	day_income = 0
	day_served = 0
	day_success = 0
	day_consumable_budget = 0.0
	daily_costs = 0
	promotion = _find_recipe(tutorial.promotion_id) if tutorial_active else {}
	remaining = 0.0
	dialogue = 0
	rapport = false
	selected_cup = ""
	selected_ice = ""
	pouring_liquid = ""
	mix_time = 0.0
	mix_position = 0.0
	active_tab = ""
	_initialize_stock()
	if not tutorial_active and not competition.state.rival.is_empty(): competition.state.street.enabled = true
	_save("selection" if select_characters else ("preparation" if day == 0 else "promotion"))
	if select_characters: _show_rival_selection()
	else:
		if not tutorial_active and not competition.state.rival.is_empty(): competition.state.street.enabled = true
		show_promotion()

func _finish_tutorial() -> void:
	if not tutorial_active or current_phase != "shop": return
	# Keep the completed first cycle recoverable if committing the next one fails.
	var completed = _snapshot("shop")
	progress.advance()
	_reset_run(companion, true)
	if not last_save_ok:
		progress.restore(completed.meta)
		tutorial_active = progress.cycle == 1
		# Restore all business fields from the already validated completion snapshot.
		_restore_document(completed)
	elif save_slots.managed() and not save_slots.complete_tutorial():
		_storage_notice(save_slots.store.last_error)

func _restart_cycle() -> void:
	_reset_run(companion)

func _next_cycle() -> void:
	var select_again = competition.narrative()
	progress.advance()
	_reset_run(companion, select_again)

func _confirm_cycle_action(advance: bool) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.theme = theme
	dialog.title = "进入下一周目" if advance else "重开当前周目"
	dialog.dialog_text = "重置金币、营业日、库存、基酒等级、器材、订单和本局消息；保留同行者。"
	dialog.dialog_text += "\n周目编号加一，重新开始经营。" if advance else "\n周目编号和已有周目记录保留。"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if advance:
			_next_cycle()
		else:
			_restart_cycle()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _show_cycle_menu() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	dialog.title = "存档与周目"
	dialog.dialog_text = "第 %d 周目 · 第 %d 日\n本周目强化：无\n关卡难度变化：无" % [progress.cycle, day]
	dialog.add_button("保存并返回标题", false, "save")
	dialog.add_button("重开当前周目", false, "restart")
	dialog.add_button("手动进入下一周目", false, "advance")
	dialog.custom_action.connect(func(action):
		dialog.hide()
		dialog.queue_free()
		if action == "save":
			if _save(current_phase):
				show_start()
		else:
			_confirm_cycle_action(action == "advance"))
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _recipe_description(recipe: Dictionary, compact = false) -> String:
	recipe = _normalize_recipe(recipe)
	var current_quote = competition.quote(recipe, pricing.calculate(_find_recipe(recipe.id), tiers), day, tiers, recipe.id.split("-")[0])
	var lines = ["[color=#dcb779][b]%s · %s[/b][/color]  %s / ¥%d" % [recipe.id, recipe.name, recipe.difficulty, current_quote.price]]
	if compact:
		lines.clear()
	for item in recipe.ingredients:
		lines.append("%s   %s ml" % [ingredient_label(item.name), item.amount])
	for item in recipe.pre_solids:
		lines.append("%s   %s 叶（调和前加入）" % [item.name, item.amount])
	for item in recipe.topup:
		lines.append("[color=#91cbb5]＋后注 %s  %s ml[/color]" % [item.name, item.amount])
	lines.append("%s  ·  %s / %s" % [recipe.method, recipe.cup, recipe.ice])
	lines.append("装饰：" + ("无" if recipe.garnish.is_empty() else "、".join(recipe.garnish)))
	if stock_only_mode and competition.daily_events.margin_loss(day) > 0:
		lines.append("差评应对中：按本杯正毛利让利 %.0f%% 结算" % (competition.daily_events.margin_loss(day) * 100))
	return "\n".join(lines)

func show_promotion() -> void:
	if stock_only_mode and _in_preparation():
		show_shop()
		return
	if competition.narrative() and (competition.state.street.card.is_empty() or (competition.round_day(day) == int(competition.street.data.numbers.change_day) and not competition.state.street.changed and not competition.state.receipts.has("keep_card"))):
		_show_counter_cards()
		return
	if competition.narrative() and competition.state.rival == "karn" and competition.round_day(day) == int(competition.street.data.numbers.visit_day) and competition.state.street.visit_answer.is_empty() and competition.state.street.upper_hand:
		_show_street_visit()
		return
	screen = "game"
	tutorial_context = "promotion"
	playing = false
	current_phase = "promotion"
	sound.enter("promotion")
	run_effects = progress.effects(day, run_rules)
	_clear(page)
	_header("白天 · 挂牌")
	if tutorial_active:
		tutorial_hint = _label(_panel(page), tutorial_story.speaker + "\n" + story_catalog.tutorial_text("promotion"), 16, MINT)
	var body = _row(page)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var intro = _panel(body)
	challenge_view.progress(intro)
	_label(intro, "今日，主推什么？", 34, GOLD)
	_label(intro, "黑板上的一行字，会把同好带到你面前。\n街面平静时，至少三位客人点主推；同行动作会改变客流。", 20)
	_label(intro, "同行者  /  " + companion.name, 19, MINT)
	_label(intro, "先从简单款开始。", 17, MUTED)
	_label(intro, "采购与升级在打烊后开放。基酒等级提高售价与偏好奖励；辅料隔夜损耗 20%。", 17, MUTED)
	_button(intro, "翻阅已收集的消息（%d）" % rumors.size(), _show_rumors)
	if tutorial_active:
		_button(intro, "设置 / 存档（Esc）", func(): pause_menu.open())
	else:
		_button(intro, "存档与周目", _show_cycle_menu)
	policy_option = OptionButton.new()
	policy_option.item_selected.connect(func(index):
		competition.state.strategy = policy_option.get_item_metadata(index)
		pending_open_plan = {}
		recipe_text.text = _recipe_description(recipes[recipe_option.selected])
		_save("promotion"))
	intro.add_child(policy_option)
	policy_option.visible = not competition.narrative()
	var menu = _panel(body)
	_label(menu, "BAR MENU  /  32 款酒谱", 20, GOLD)
	recipe_option = OptionButton.new()
	for recipe in recipes:
		recipe_option.add_item("%s  %s · %s" % [recipe.id, recipe.name, recipe.difficulty])
	if not promotion.is_empty():
		for index in range(recipes.size()):
			if recipes[index].id == promotion.id:
				recipe_option.select(index)
	recipe_option.disabled = tutorial_active
	menu.add_child(recipe_option)
	var recipe_scroll = _scroll_column(menu)
	recipe_text = _rich(recipe_scroll, _recipe_description(recipes[recipe_option.selected]))
	recipe_option.item_selected.connect(func(index):
		promotion = recipes[index]
		pending_open_plan = {}
		_refresh_policies()
		recipe_text.text = _recipe_description(promotion)
		_save("promotion"))
	_refresh_policies()
	tutorial_action = _button(menu, "挂上招牌，点亮夜灯  →", _open_day)
	status_line = _label(page, "配方用量可随时查阅 · 气泡类后注不进入摇壶 · 失误会扣分，仍可继续出杯", 15, MUTED)

func _refresh_policies() -> void:
	policy_option.clear()
	for id in competition.available_policies(recipes[recipe_option.selected], day):
		policy_option.add_item(competition.content.policy_labels[id])
		var index = policy_option.item_count - 1
		policy_option.set_item_metadata(index, id)
		if id == competition.state.strategy:
			policy_option.select(index)
	competition.state.strategy = policy_option.get_item_metadata(policy_option.selected)

func _open_day(approve_purchase = false) -> void:
	promotion = _find_recipe(recipes[recipe_option.selected].id)
	if stock_only_mode:
		_open_stock_day()
		return
	if approve_purchase and not pending_open_plan.is_empty() and pending_open_plan.signature == _plan_signature():
		competition.state = pending_open_plan.state.duplicate(true)
		_commit_open_plan(pending_open_plan.plan)
		return
	competition.apply_pending_ending(day)
	if competition.narrative():
		if competition.state.street.card.is_empty(): return
		if competition.street.effective(competition.state.street, competition.round_day(day)) == "offset" and promotion.id.begins_with("S-"):
			status_line.text = "错位要避开对面的简单档。请选择中等或困难款。"
			return
	var planner = OrderPlanner.new(competition, pricing, day, tiers)
	if planner.three(promotion, stock, money).is_empty():
		competition.state.blocked_promotion = promotion.id
		var feasible = recipes.filter(func(recipe): return not planner.three(recipe, stock, money).is_empty())
		status_line.text = "该主推无法备齐三杯。可换：" + "、".join(feasible.map(func(recipe): return recipe.name)) if not feasible.is_empty() else "库存和现金不足，暂无可开主推。请补货或重开周目；救济内容待补充。"
		_save("promotion")
		return
	var before = competition.state.duplicate(true)
	competition.begin_day(promotion, day, tiers)
	if not competition.state.blocked_promotion.is_empty() and competition.state.blocked_promotion != promotion.id:
		competition.state.traffic_sources.switch = -1
	var count = rng.randi_range(int(config.customers_min), int(config.customers_max)) + competition.traffic_delta(promotion, day, pricing.calculate(promotion, tiers).price)
	var plan = planner.empty_plan(stock, money)
	var guaranteed = int(competition.rules.limits.promotion_guaranteed_orders)
	if competition.narrative():
		if competition.street.effective(competition.state.street, competition.round_day(day)) == "offset": guaranteed = int(competition.street.data.numbers.offset_slots) + int(competition.street.data.numbers.offset_hit)
		guaranteed = maxi(1, guaranteed - int(competition.state.street.hit_loss))
	var slots: Array = []
	for index in range(maxi(guaranteed, count)):
		slots.append({"recipe_id": promotion.id, "customer_index": (index + day - 1)%customers.size()})
	competition.shift_queue(slots, customers, day)
	if competition.narrative() and competition.state.street.captain.left:
		for slot in slots:
			while customers[int(slot.customer_index)].story_id == competition.street.data.captain.id:
				slot.customer_index = (int(slot.customer_index) + 1) % customers.size()
	for index in range(maxi(guaranteed, count)):
		var customer_index = int(slots[index].customer_index)
		if index < guaranteed:
			plan = planner.reserve(plan, promotion, customer_index, _customer_recipe(promotion, customers[customer_index]))
			if plan.is_empty():
				competition.state = before
				status_line.text = "本轮顾客的定制用量无法备齐，请补货或调整主推。"
				return
		else:
			var choices: Array = []
			for recipe in recipes:
				var trial = planner.reserve(plan, recipe, customer_index, _customer_recipe(recipe, customers[customer_index]))
				if not trial.is_empty():
					choices.append(trial)
			if choices.is_empty():
				break
			plan = choices[rng.randi_range(0, choices.size() - 1)]
	if int(plan.cost) > 0 and not approve_purchase:
		pending_open_plan = {"plan": plan.duplicate(true), "state": competition.state.duplicate(true), "signature": _plan_signature()}
		competition.state = before
		var dialog = ConfirmationDialog.new()
		dialog.theme = theme
		dialog.title = "备料后开店"
		dialog.dialog_text = "需补齐本轮订单原料，采购共 ¥%d。确认后按此价采购并开店。" % int(plan.cost)
		add_child(dialog)
		dialog.confirmed.connect(func():
			_open_day(true)
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
		return
	_commit_open_plan(plan)

func _plan_signature() -> String:
	return JSON.stringify([day, promotion.id, competition.state.strategy, money, stock, tiers])

func _commit_open_plan(plan: Dictionary) -> void:
	stock_ledger.new_day()
	for bill in plan.bills.values():
		_commit_stock_bill(bill)
	queue = plan.orders
	for index in range(queue.size() - 1, 0, -1):
		var swap = rng.randi_range(0, index)
		var order = queue[index]
		queue[index] = queue[swap]
		queue[swap] = order
	guest_index = 0
	day_income = 0
	day_served = 0
	day_success = 0
	day_consumable_budget = 0.0
	competition.state.blocked_promotion = ""
	pending_open_plan = {}
	_log("day_open", {"day": day, "promotion": promotion.id, "queue": queue})
	_save("reception")
	_start_guest()

func _find_recipe(id: String) -> Dictionary:
	for recipe in recipes:
		if recipe.id == id:
			return _normalize_recipe(recipe)
	return recipes[0]

func _normalize_recipe(source: Dictionary) -> Dictionary:
	if not stock_only_mode: return source
	var recipe = source.duplicate(true)
	for item in recipe.ingredients:
		if item.name in rulings.rum.names:
			recipe.minimum_rum_tier = maxi(int(recipe.get("minimum_rum_tier", 1)), rulings.rum.names.find(item.name) + 1)
			item.name = rulings.rum.canonical
	return recipe

func selectable_liquids() -> Array:
	return stock.keys().filter(func(name): return not stock_only_mode or name == rulings.rum.canonical or name not in rulings.rum.names)

func ingredient_label(name: String) -> String:
	return str(rulings.rum.names[int(tiers.get(rulings.rum.family, 0))]) if stock_only_mode and name == rulings.rum.canonical else name

func _customer_recipe(original: Dictionary, client: Dictionary, order: Dictionary = {}) -> Dictionary:
	var recipe = _normalize_recipe(original).duplicate(true)
	var spec: Dictionary = client.get("order_spec", {})
	if spec.get("recipe", "") == recipe.id:
		for group in ["ingredients", "topup"]:
			var portions: Array = []
			for item in recipe[group]:
				if item.name in spec.get("remove_liquids", []):
					continue
				item.amount = float(item.amount) * float(spec.get("scale", 1))
				item.amount = spec.get("amounts", {}).get(item.name, item.amount)
				item.amount += float(spec.get("add_amounts", {}).get(item.name, 0))
				portions.append(item)
			recipe[group] = portions
		if spec.has("garnish"): recipe.garnish = spec.garnish.duplicate()
	if order.has("reservation_spec"):
		for item in recipe.ingredients:
			item.amount = order.reservation_spec.amounts.get(item.name, item.amount)
		recipe.garnish = order.reservation_spec.garnish.duplicate()
	return recipe

func _start_guest() -> void:
	last_mistake_report = {}
	sound.enter("ending" if competition.narrative() and not competition.state.street.ending.is_empty() else "reception")
	current_phase = "reception"
	run_effects = progress.effects(day, run_rules)
	guest = customers[int(queue[guest_index].customer_index)].duplicate(true)
	var appraisal = queue[guest_index].has("event_appraisal")
	if appraisal:
		guest = competition.daily_events.prose.appraiser_guest.duplicate(true)
		guest.merge({"id": "appraiser", "story_id": "appraiser", "favorite": "", "request": "standard", "topic": "", "answers": [], "reply": "", "rumor": "", "good_answer": 0})
	stock_ledger.order_discounted.clear()
	guest_cost_start = float(stock_ledger.daily.ingredients)
	var base_recipe = _find_recipe(queue[guest_index].recipe_id)
	var recipe = _customer_recipe(base_recipe, guest, queue[guest_index])
	if queue[guest_index].has("reservation_spec"):
		guest.reservation_optional = base_recipe.ingredients.filter(func(item): return item.name in queue[guest_index].reservation_spec.amounts).reduce(func(values, item): values[item.name] = item.amount; return values, {})
	if stock_only_mode and not _can_serve(recipe):
		queue[guest_index].unavailable = true
		brew = null
		playing = false
		_save("reception")
		_show_unavailable_guest(recipe)
		return
	if not queue[guest_index].has("quote"):
		queue[guest_index].quote = competition.quote(base_recipe, pricing.calculate(base_recipe, tiers), day, tiers)
	for group in ["ingredients", "topup"]:
		for portion in recipe[group]:
			portion.name = queue[guest_index].get("substitutions", {}).get(portion.name, portion.name)
	var spec: Dictionary = guest.get("order_spec", {})
	if spec.get("recipe", "") == recipe.id:
		guest.no_ice = spec.get("no_ice", false)
		guest.no_garnish = spec.get("no_garnish", false)
		guest.request_text = guest.get("order_note", guest.request_text)
	var race: Dictionary = dialogue_rules.races.get(guest.get("race", ""), {})
	var base_time = float(dialogue_rules.base_patience) * float(race.get("patience_multiplier", 1)) + float(race.get("patience_add", 0))
	if race.has("random_patience") and not queue[guest_index].has("patience"):
		base_time += rng.randf_range(-float(race.random_patience), float(race.random_patience))
	if spec.get("recipe", "") == recipe.id:
		base_time = minf(base_time, float(spec.get("time_limit", base_time)))
	if not queue[guest_index].has("patience"):
		queue[guest_index].patience = base_time * float(companion.time_multiplier) + equipment * float(config.equipment_time_bonus)
	remaining = float(queue[guest_index].patience)
	if guest_index == 0:
		var rival_dialogue: Dictionary = competition.dialogue(day)
		if not rival_dialogue.is_empty():
			guest.merge(rival_dialogue, true)
			guest.answers = guest.choices.map(func(choice): return choice.text)
			guest.good_answer = 0
			guest.competitive_dialogue = true
	# No rival's unselected name or event leaks into the intelligence segment.
	if not competition.rival().is_empty() and (guest_index != 0 or day < int(competition.data.rules.rumor_day)):
		guest.rumor = competition.rival().summary if day >= int(competition.data.rules.rumor_day) else competition.data.summary.quiet
	if competition.narrative() and not appraisal:
		guest.rumor = competition.summary(day)
		competition.street.captain_guest(competition.state.street, guest, day, competition.round_day(day) in [int(competition.street.data.numbers.visit_day), int(competition.street.data.numbers.escalation_day)])
	if stock_only_mode and not appraisal:
		if not competition.narrative():
			guest.rumor = competition.data.summary.quiet
			competition.street.captain_guest(competition.state.street, guest, day, false)
		competition.daily_events.offer(guest.story_id, queue[guest_index], day, rng)
	_sfx("sfx.guest_arrive")
	brew = BrewModel.new(config, recipe, guest)
	if queue[guest_index].get("reservation", false) and not queue[guest_index].get("reservation_checked", false):
		queue[guest_index].reservation_checked = true
		for item in recipe.ingredients + recipe.topup:
			if float(stock.get(item.name, 0)) < float(item.amount):
				competition.state.reputation += int(competition.events["S-06"].unprepared_reputation)
				queue[guest_index].reservation = false
				break
	dialogue_effect = dialogue_rules.default_choice.duplicate(true)
	intel_level = "full"
	dialogue_remaining = float(dialogue_rules.segment_seconds) + float(race.get("segment_bonus", 0))
	dialogue = 3 if appraisal else 0
	rapport = false
	pouring = false
	mixing = false
	selected_cup = ""
	selected_ice = ""
	active_tab = ""
	playing = true
	_save("reception")
	_build_reception()
	_log("guest_start", {"name": guest.name, "recipe": brew.recipe.id})

func _build_reception() -> void:
	screen = "game"
	tutorial_context = "reception"
	_clear(page)
	_header("%d / %d" % [guest_index + 1, queue.size()])
	if tutorial_active:
		tutorial_hint = _label(_panel(page), "", 16, MINT)
	var body = _row(page)
	body.name = "Reception"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	# The scene stays open; only the speech bubble floats over the tavern.
	var scene = Control.new()
	scene.name = "GuestScene"
	scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene.size_flags_stretch_ratio = 1.3
	body.add_child(scene)
	var portrait = TextureRect.new()
	portrait.name = "GuestPortrait"
	portrait.texture = load(character_art.customers.get(str(guest.story_id), character_art.fallback_customer))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.anchor_right = 0.50
	portrait.anchor_top = 0.22
	portrait.modulate = Color.WHITE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(portrait)
	var bubble = PanelContainer.new()
	bubble.name = "SpeechBubble"
	scene.add_child(bubble)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bubble.anchor_left = 0.40
	bubble.anchor_top = 0.16
	bubble.anchor_bottom = 0.70
	bubble.offset_right = -8
	var bubble_style = StyleBoxFlat.new()
	bubble_style.bg_color = Color("172f32")
	bubble_style.border_color = Color("8b8061")
	bubble_style.set_border_width_all(1)
	bubble_style.set_corner_radius_all(16)
	bubble_style.content_margin_left = 22
	bubble_style.content_margin_right = 22
	bubble_style.content_margin_top = 18
	bubble_style.content_margin_bottom = 18
	bubble.add_theme_stylebox_override("panel", bubble_style)
	var conversation = _scroll_column(bubble)
	left = conversation
	var guest_row = _row(conversation)
	var guest_name = _label(guest_row, guest.name, 26, Color(guest.color))
	guest_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	var guest_info = _label(guest_row, guest.role, 15, MUTED)
	guest_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if competition.narrative() and not stock_only_mode and guest_index == 0: _label(conversation, competition.summary(day), 16, MINT)
	_label(conversation, story_catalog.content.common.order.format({"drink": brew.recipe.name}), 19, GOLD)
	dialogue_box = VBoxContainer.new()
	dialogue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_box.add_theme_constant_override("separation", 10)
	conversation.add_child(dialogue_box)
	_draw_dialogue()
	var nameplate = VBoxContainer.new()
	scene.add_child(nameplate)
	nameplate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nameplate.offset_top = -82
	nameplate.offset_left = 24
	time_label = _label(nameplate, "", 16, GOLD)
	timer_bar = ProgressBar.new()
	timer_bar.max_value = remaining
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size.y = 5
	timer_bar.add_theme_stylebox_override("background", _bar_style(Color("243e40")))
	timer_bar.add_theme_stylebox_override("fill", _bar_style(GOLD))
	nameplate.add_child(timer_bar)
	var station = VBoxContainer.new()
	station.name = "BartenderStation"
	station.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	station.size_flags_stretch_ratio = 1.0
	station.add_theme_constant_override("separation", 16)
	body.add_child(station)
	var instructions = _panel(station)
	instructions.get_parent().name = "Instructions"
	instructions.get_parent().custom_minimum_size.y = float(tutorial.layout.instructions_min_height) if tutorial_active else 230
	_label(instructions, brew.recipe.name, 25, GOLD)
	_label(instructions, "本杯挂牌 ¥%d" % int(queue[guest_index].quote.price), 16, MINT)
	var recipe_scroll = _scroll_column(instructions)
	_rich(recipe_scroll, _recipe_description(brew.recipe, true))
	right = VBoxContainer.new()
	right.name = "Workbench"
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	station.add_child(right)
	workbench = Workbench.new()
	workbench.game = self
	right.add_child(workbench)
	if tutorial_active:
		workbench.custom_minimum_size.y = float(tutorial.layout.workbench_min_height)
	var footer = _row(page)
	status_line = _label(footer, "", 15, MUTED)
	status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tutorial_active:
		_button(footer, "退出练习（本杯重做）", show_start)
	_button(footer, "手账", _show_rumors)
	_button(footer, "放弃", _abandon)
	_render_operation()

func _draw_dialogue() -> void:
	_clear(dialogue_box)
	dialogue_clock = _label(dialogue_box, "", 13, MUTED)
	_update_dialogue_clock()
	match dialogue:
		0:
			_label(dialogue_box, guest.request_text, 18)
			_button(dialogue_box, "记下要求", _advance_dialogue.bind(0), false, "dialogue")
		1:
			if brew.stage < 2:
				_label(dialogue_box, story_catalog.content.common.waiting, 16, MUTED)
			elif _market_dialogue():
				_label(dialogue_box, competition.daily_events.message(queue[guest_index], day), 18, MINT)
				for claim in competition.daily_events.state.heard_claims:
					if competition.daily_events.can_verify(claim, guest.story_id) and not queue[guest_index].has("verification_text"):
						_button(dialogue_box, competition.daily_events.pools.claims[claim].button, _verify_market_claim.bind(claim), false, "dialogue")
				_button(dialogue_box, competition.daily_events.prose.acknowledge, _advance_dialogue.bind(0), false, "dialogue")
			else:
				_label(dialogue_box, guest.topic, 18)
				for index in range(guest.answers.size()):
					_button(dialogue_box, guest.answers[index], _advance_dialogue.bind(index), false, "dialogue")
		2:
			if _market_dialogue():
				if brew.stage < 4:
					_label(dialogue_box, "……", 16, MUTED)
				else:
					_label(dialogue_box, guest.rumor, 17, MINT)
					_label(dialogue_box, guest.topic, 18)
					if guest.story_id == rulings.reservation.customer and not queue[guest_index].has("reservation_spec"): _label(dialogue_box, rulings.reservation.text, 16, MINT)
					for index in range(guest.answers.size()):
						_button(dialogue_box, guest.answers[index], _advance_dialogue.bind(index), false, "dialogue")
				return
			if not rapport or not guest.reply.is_empty():
				_label(dialogue_box, guest.reply if rapport else story_catalog.content.common.distant_reply, 17)
			if brew.stage < 4:
				_label(dialogue_box, "……", 16, MUTED)
			else:
				var intel = guest.rumor
				if intel_level == "half":
					intel = intel.left(maxi(1, intel.length() / 2)) + "……"
				elif intel_level == "none":
					intel = story_catalog.content.common.no_intel
				_label(dialogue_box, intel, 17, MINT)
				_button(dialogue_box, "收下这则消息" if intel_level == "full" else "点头，继续调酒", _advance_dialogue.bind(0), false, "dialogue")
		3:
			if _market_dialogue() and not guest.reply.is_empty(): _label(dialogue_box, guest.reply if rapport else story_catalog.content.common.distant_reply, 17)
			_label(dialogue_box, competition.daily_events.prose.appraiser_wait if queue[guest_index].has("event_appraisal") else story_catalog.content.common.thanks, 17, MINT)

func _market_dialogue() -> bool:
	return stock_only_mode and not queue[guest_index].has("event_appraisal")

func _dialogue_unlocked() -> bool:
	return dialogue == 0 or (dialogue == 1 and brew.stage >= 2) or (dialogue == 2 and brew.stage >= 4)

func _update_dialogue_clock() -> void:
	if is_instance_valid(dialogue_clock):
		dialogue_clock.visible = not tutorial_active and dialogue < 3 and _dialogue_unlocked()
		dialogue_clock.text = "回应剩余 %d 秒" % ceili(dialogue_remaining)

func _advance_dialogue(answer: int) -> void:
	if dialogue == (2 if _market_dialogue() else 1):
		if guest.get("longline", false):
			guest.longline_answer = answer
			guest.reply = guest.longline_beat.get("alternate_reply", "他端起杯子，没再往下说。") if answer == 1 else guest.longline_beat.reply
		if guest.has("choices"):
			dialogue_effect = guest.choices[answer].duplicate(true)
			var cost = int(dialogue_effect.get("cost", 0))
			if cost > money:
				status_line.text = "金币不足，无法兑现这项安排。"
				return
			rapport = dialogue_effect.answer == "valid" and not dialogue_effect.get("leak", false)
			intel_level = "full" if rapport else "half"
			var race_rule: Dictionary = dialogue_rules.races.get(guest.get("race", ""), {})
			if not rapport and race_rule.get("tolerance") == 0:
				intel_level = "none"
			if guest.get("competitive_dialogue", false):
				competition.record_answer(dialogue_effect)
			else:
				competition.state.reputation += int(dialogue_effect.get("reputation", 0))
				competition.state.day_valid += 1 if rapport else 0
				competition.state.next_traffic += int(dialogue_effect.get("traffic", 0))
			money -= cost
			remaining = maxf(0, remaining - float(dialogue_effect.get("seconds", 0)))
			stock_ledger.daily.events += cost
		else:
			rapport = answer == int(guest.good_answer)
	if dialogue == 1 and _market_dialogue():
		_sfx("sfx.intel")
		competition.daily_events.hear(queue[guest_index])
		_record_rumor(competition.daily_events.message(queue[guest_index], day), guest.story_id)
	if dialogue == 2 and intel_level == "full":
		_record_rumor(guest.rumor, guest.story_id)
	if dialogue == 2 and guest.get("competitive_dialogue", false):
		competition.hear_intel(day, int(queue[guest_index].customer_index), brew.recipe.id)
	if dialogue == 2 and _market_dialogue() and guest.story_id == rulings.reservation.customer and not queue[guest_index].has("reservation_spec"):
		if not challenge.state.reservations.any(func(reservation): return int(reservation.due) == day + int(rulings.reservation.delay_days)):
			challenge.state.reservations.append({"customer": guest.story_id, "due": day + int(rulings.reservation.delay_days)})
	if stock_only_mode: intel_level = "full"
	dialogue += 1
	dialogue_remaining = float(dialogue_rules.segment_seconds)
	_draw_dialogue()
	_update_tutorial_hint()

func _update_tutorial_hint() -> void:
	if is_instance_valid(tutorial_director):
		tutorial_director.refresh()

func _render_operation() -> void:
	_update_tutorial_hint()
	workbench.render()
	_draw_dialogue()

func _update_measure_readout() -> void:
	if is_instance_valid(workbench):
		workbench.cylinder.update_level()

func _show_bottles(base: bool) -> void:
	workbench.open_drawer("base" if base else "mixer")

func _toggle_pour(liquid: String) -> void:
	if brew.stage >= 2 or float(stock.get(liquid, 0)) <= 0: return
	if workbench.measure_focus.shown:
		if pouring: _stop_pour()
		return
	pouring_liquid = liquid
	_sfx("sfx.bottle_pick")
	workbench.measure_focus.open()
	status_line.text = ""

func _stop_pour() -> void:
	pouring = false
	if is_instance_valid(workbench):
		workbench.measure_focus.close()
	_update_measure_readout()

func _transfer() -> void:
	_stop_pour()
	workbench.measure_focus.dismiss()
	if not brew.transfer():
		status_line.text = "量筒为空"
		return
	_sfx("sfx.transfer")
	_log("measure", brew.quantities.back())
	_render_operation()
	workbench.play_tilt(workbench.cylinder)

func _add_pre_solid(item: String) -> void:
	_sfx("sfx.garnish")
	brew.pre_solids.append(item)
	_render_operation()

func _bar_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	return style

func _finish_straight() -> void:
	if not playing or brew.stage != 2 or brew.recipe.method != "直调": return
	workbench.straight_focus.open()

func _commit_straight() -> void:
	brew.mix_at(float(config.mix_target))
	_render_operation()

func _toggle_mix() -> void:
	if brew.stage != 2 or brew.recipe.method == "直调": return
	if workbench.mix_focus.shown:
		if mixing: workbench.mix_focus.close()
		return
	status_line.text = ""
	workbench.mix_focus.open()

func _complete_mix(position: float) -> void:
	var previous_errors = brew.errors
	brew.mix_at(position)
	_sfx("sfx.mix_good" if brew.errors == previous_errors else "sfx.mix_miss")
	status_line.text = "完美" if brew.mix_perfect else "调制完成"
	_log("mix", {"method": brew.recipe.method, "error": brew.mix_error})
	_render_operation()

func _select_cup(cup: String) -> void:
	_sfx("sfx.cup")
	selected_cup = cup
	_render_operation()

func _select_ice(ice: String) -> void:
	if ice != "无冰": _sfx("sfx.ice")
	selected_ice = ice
	_render_operation()

func _pour_into_glass() -> void:
	brew.choose_vessel(selected_cup, selected_ice)
	_sfx("sfx.glass_pour")
	brew.finish_pour()
	_render_operation()
	workbench.play_tilt(workbench.shaker.get_node("Visual"))

func _topup() -> void:
	var item = brew.recipe.topup[brew.topup_index]
	stock_ledger.consume(item.name, float(item.amount))
	stock[item.name] = float(stock[item.name]) - float(item.amount)
	_sfx("sfx.topup")
	brew.add_topup(item.name)
	_render_operation()

func _special(apply_request: bool) -> void:
	brew.handle_special(apply_request)
	_render_operation()

func _garnish(item: String) -> void:
	_sfx("sfx.garnish")
	brew.add_garnish(item)
	_render_operation()

func _process(delta: float) -> void:
	if is_instance_valid(effects_label) and screen == "game": effects_label.text = _effects_summary()
	if is_instance_valid(scene_transition) and scene_transition.busy: return
	if get_tree().paused or not playing or brew == null:
		return
	if not tutorial_active:
		remaining = maxf(0, remaining - delta)
	if not tutorial_active and dialogue < 3 and _dialogue_unlocked():
		dialogue_remaining = maxf(0, dialogue_remaining - delta)
		if dialogue_remaining <= 0:
			if dialogue == (2 if _market_dialogue() else 1) and guest.has("choices"):
				var cold = -1
				for index in range(guest.choices.size()):
					if guest.choices[index].answer == "cold":
						cold = index
				if cold >= 0:
					_advance_dialogue(cold)
			else:
				intel_level = "half"
				dialogue += 1
				dialogue_remaining = float(dialogue_rules.segment_seconds)
				_draw_dialogue()
	_update_dialogue_clock()
	time_label.text = "%02d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	timer_bar.value = remaining
	if pouring and brew.stage < 2:
		var amount = minf(delta * _pour_rate(), float(stock[pouring_liquid]))
		stock_ledger.consume(pouring_liquid, amount)
		stock[pouring_liquid] = maxf(0, float(stock[pouring_liquid]) - amount)
		brew.add_liquid(pouring_liquid, amount)
		if float(stock[pouring_liquid]) <= 0:
			_stop_pour()
		_update_measure_readout()
	if mixing:
		mix_time += delta
		var duration = float(config.mix_cycle_seconds)
		if brew.recipe.method in ["滚摇", "长摇"]:
			duration *= float(config.long_mix_multiplier)
		mix_position = pingpong(mix_time / duration, 1.0)
		shake_bar.queue_redraw()
	if remaining <= 0:
		_settle(true)

func _pour_rate() -> float:
	# A dash of bitters must be controllable with the same mouse as a full measure.
	return minf(float(config.pour_speed), float(brew.target().amount) / float(config.small_measure_seconds))

func _serve() -> void:
	_sfx("sfx.bell")
	_settle(false)

func _abandon() -> void:
	_settle(true)

func _settle(timed_out: bool) -> void:
	playing = false
	pouring = false
	mixing = false
	var quoted: Dictionary = queue[guest_index].get("quote", competition.quote(brew.recipe, pricing.calculate(_find_recipe(brew.recipe.id), tiers), day, tiers))
	var modifiers = competition.modifiers(quoted, _find_recipe(brew.recipe.id), brew.cup != brew.recipe.cup, brew.ice != brew.expected_ice(), quoted.tiers)
	last_mistake_report = MistakeReport.build(self, modifiers, timed_out)
	var errors = int(last_mistake_report.count)
	var complete = not timed_out and brew.stage == 5
	var success = complete and errors == 0 and dialogue == 3
	_sfx("sfx.result_timeout" if timed_out else ("sfx.result_good" if success else "sfx.result_imperfect"))
	var ratio = maxf(float(config.minimum_payout_ratio), 1.0 - errors * float(config.mistake_penalty)) if complete else 0.0
	var tier_bonus = 0.0
	for item in brew.recipe.ingredients:
		if item.name in config.base_names:
			var family = config.base_families[item.name]
			tier_bonus = maxf(tier_bonus, float(quoted.tiers.get(family, 0)) * float(config.favorite_tier_bonus))
	var preference = 1.0
	if _uses_favorite(brew.recipe, guest.favorite):
		preference += tier_bonus
	var wine = Competition.money(float(quoted.price) * float(modifiers.revenue_multiplier) * preference * ratio * float(companion.success_multiplier if success else companion.failure_multiplier) * float(dialogue_effect.get("revenue", 1)))
	if competition.narrative() or competition.modern_mode:
		var actual_cost = float(stock_ledger.daily.ingredients) - guest_cost_start + float(pricing.catalog.pricing_rules.consumables_per_drink)
		wine -= Competition.money(maxf(0.0, wine - actual_cost) * float(quoted.get("margin_loss", 0)))
	var tip = 0
	if complete:
		var race: Dictionary = dialogue_rules.races.get(guest.get("race", ""), {})
		if rapport and dialogue == 3:
			tip = Competition.money(float(quoted.price) * float(config.rapport_tip_ratio) * float(dialogue_effect.get("tip", 1)) * float(race.get("tip", 1)) * float(modifiers.tip_multiplier))
		day_consumable_budget += float(pricing.catalog.pricing_rules.consumables_per_drink)
	if queue[guest_index].has("event_appraisal"):
		wine = 0
		tip = 0
		competition.daily_events.finish_appraisal(int(queue[guest_index].event_appraisal), success, day)
	var revenue = wine + tip
	stock_ledger.daily.liquor += wine
	stock_ledger.daily.tips += tip
	stock_ledger.daily.consumables = day_consumable_budget
	var required_families = competition.recipe_families(brew.recipe)
	var high_tier = not required_families.is_empty() and required_families.all(func(family): return int(quoted.tiers.get(family, 0)) + 1 >= int(challenge.rules.rivals.viola.minimum_tier))
	var special_correct = brew.special_done and brew.ice == brew.expected_ice() and not _missing_requested_tier() and brew.expected_garnishes().all(func(item): return item in brew.garnishes)
	companion_progress.score(self, queue[guest_index], complete and wine > 0)
	challenge.score(queue[guest_index], guest.story_id, brew.recipe, wine, complete, dialogue == 3, rapport, special_correct, errors, high_tier, day)
	if complete and queue[guest_index].has("reservation_spec") and brew.quantities.all(func(item): return absf(float(item.amount) - float(item.target)) <= float(item.target) * float(config.quantity_tolerance)):
		competition.state.reputation += int(rulings.reservation.reputation)
	competition.record_service(quoted, modifiers, complete, guest.get("id", guest.name), rapport, day, _find_recipe(brew.recipe.id))
	money += revenue
	day_income += revenue
	day_served += 1
	if success:
		day_success += 1
	_log("serve", {"recipe": brew.recipe.id, "errors": errors, "mistakes": last_mistake_report, "dialogue": dialogue, "timeout": timed_out, "revenue": revenue, "wine": wine, "tip": tip, "quote": quoted, "competition": modifiers})
	if competition.narrative() or (stock_only_mode and challenge.state.phase == "free"): competition.street.captain_served(competition.state.street, guest, day)
	_finish_customer_record()
	_save("shop" if guest_index >= queue.size() else "reception")
	scene_transition.next_mode = "zoom_in"
	_clear(page)
	tutorial_context = "settlement"
	_header("一杯酒，一个故事")
	if tutorial_active:
		tutorial_hint = _label(_panel(page), "", 16, MINT)
	var body = _row(page)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column = _panel(body, 330)
	column.get_parent().name = "SettlementDetails"
	var panel = _scroll_column(column)
	_label(panel, interface.result.details, 18, MINT)
	_label(panel, story_catalog.content.common.success if success else (story_catalog.content.common.timeout if timed_out else story_catalog.content.common.imperfect), 32, GOLD)
	_label(panel, "%s · %s  /  本杯收入 ¥%d" % [guest.name, brew.recipe.name, revenue], 24)
	if success and guest.has("closing"):
		_label(panel, guest.closing, 20, MINT)
	_label(panel, "失误 %d 次 · 三轮交谈 %d / 3 · 今日累计 ¥%d" % [errors, dialogue, day_income], 19, MINT)
	_label(panel, interface.result.mistakes.heading, 18, GOLD).name = "MistakeHeading"
	if last_mistake_report.items.is_empty(): _label(panel, interface.result.mistakes.none, 16, MINT).name = "NoMistakes"
	for item in last_mistake_report.items:
		var line = _label(panel, interface.result.mistakes.item.format({"reason": MistakeReport.reason(self, item), "count": item.count}), 16)
		line.name = "MistakeReason_" + str(line.get_index())
	if not last_mistake_report.notes.is_empty():
		_label(panel, interface.result.mistakes.notes_heading, 17, MINT)
		for note in last_mistake_report.notes: _label(panel, interface.result.mistakes[note], 15, MUTED)
	if not brew.quantities.is_empty():
		var details: Array[String] = []
		for item in brew.quantities:
			details.append("%s  %.1f / %s ml" % [item.name, item.amount, item.target])
		_label(panel, "量取记录：" + "；".join(details), 16, MUTED)
	var preview = preload("res://scripts/ui/bar/served_drink.gd").new()
	preview.name = "ServedDrinkPreview"
	preview.game = self
	preview.model = brew
	body.add_child(preview)
	var footer = _row(page)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	tutorial_action = _button(footer, "擦净吧台，迎接下一位  →" if guest_index < queue.size() else "收起招牌，打烊结算  →", _next_guest)

func _missing_requested_tier() -> bool:
	if int(brew.recipe.get("minimum_rum_tier", 1)) > int(tiers.get(rulings.rum.family, 0)) + 1: return true
	var spec: Dictionary = guest.get("order_spec", {})
	if spec.get("recipe", "") != brew.recipe.id or not spec.has("minimum_tier"):
		return false
	for item in brew.recipe.ingredients:
		var family = config.base_families.get(item.name, "")
		if not family.is_empty() and int(tiers[family]) + 1 < int(spec.minimum_tier):
			return true
	return false

func _uses_favorite(recipe: Dictionary, family: String) -> bool:
	if family.is_empty():
		return false
	for item in recipe.ingredients:
		if config.base_families.get(item.name, "") == family:
			return true
	return false

func _next_guest() -> void:
	if scene_transition.busy: return
	if guest_index < queue.size():
		scene_transition.next_mode = "zoom_out"
		_start_guest()
	else:
		if challenge.state.phase == "result": challenge_view.result()
		else: show_shop()

func show_shop() -> void:
	if challenge.state.phase == "result":
		challenge_view.result()
		return
	if stock_only_mode and day == 0 and not competition.state.rival.is_empty() and challenge.state.phase == "off":
		challenge.prepare(competition.state.rival, day + 1)
		_sync_challenge()
		companion_progress.prepare(self)
		challenge.state.retry = _snapshot("preparation")
		_save("preparation")
	sound.enter("shop")
	screen = "game"
	tutorial_context = "shop"
	playing = false
	current_phase = "preparation" if _in_preparation() else "shop"
	competition.prepare_market(day, pricing.catalog, tiers, recipes, stock, rng)
	_clear(page)
	_header("D0 · 开业采购" if _in_preparation() else "打烊 · 月下集市")
	var summary = _row(page)
	var shop_stats = _label(summary, "接待 %d 位 · 完成 %d 杯 · 收入 ¥%d" % [day_served, day_success, day_income], 20, TEXT)
	shop_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_stats.add_theme_stylebox_override("normal", _bar_style(Color("10282bf2")))
	_button(summary, "翻阅酒谱", _show_recipe_book)
	_button(summary, interface.shop.upgrades, _show_upgrades)
	_button(summary, "经营账本", _show_shop_ledger)
	var shop = preload("res://scripts/ui/shop_view.gd").new()
	shop.name = "ShopShelves"
	shop.game = self
	page.add_child(shop)
	challenge_view.progress(shop.sidebar)
	if tutorial_active:
		tutorial_hint = _label(_panel(shop.sidebar), tutorial_story.speaker + "\n" + story_catalog.tutorial_text("shop"), 16, MINT)
	challenge_view.opportunities(shop.sidebar)
	for button in shop.sidebar.find_children("*", "Button", true, false):
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bottom = HFlowContainer.new()
	page.add_child(bottom)
	_rival_actions(bottom)
	if competition.state.scheduled.any(func(event): return event.id == "S-07"):
		var price = int(pricing.catalog.other_prices.design_events.reputation_round.price)
		_button(bottom, "请一轮，平息传闻 ¥%d" % price, _calm_rumor, money < price)
	_button(bottom, "消息手账（%d）" % rumors.size(), _show_rumors)
	_button(bottom, "设置 / 存档（Esc）", func(): pause_menu.open())
	if challenge.state.phase == "rest":
		_button(bottom, challenge.rules.text.next, challenge_view.selection)
	elif _in_preparation():
		_button(bottom, "备货完成，准备第一晚 →", _finish_preparation)
	elif tutorial_active:
		tutorial_action = _button(bottom, interface.shop.finish, _finish_tutorial)
	else:
		_button(bottom, "存档并开始第 %d 日  →" % (day + 1), _next_day)
	if challenge.state.phase in ["free", "off"] and not tutorial_active: _button(bottom, challenge.rules.text.challenge, challenge_view.selection.bind(challenge.state.defeated.size() == challenge.rules.rivals.size()))
	status_line = _label(page, "出品与采购自动保存", 14, MUTED)

func _show_shop_ledger() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	dialog.title = "经营账本"
	dialog.dialog_text = competition.summary(day)
	dialog.dialog_text += "\n经营贡献 ¥%.2f · 用料 ¥%.2f · 损耗 ¥%.2f · 事件 ¥%d" % [stock_ledger.contribution(), stock_ledger.daily.ingredients, stock_ledger.daily.spoilage, stock_ledger.daily.events]
	if stock_ledger.unknown_basis: dialog.dialog_text += "\n旧档历史进价未知，成本基础不完整。"
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _show_upgrades() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	dialog.title = interface.shop.upgrades
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 480)
	dialog.add_child(scroll)
	var upgrade_list = VBoxContainer.new()
	upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(upgrade_list)
	for family in config.base_tiers:
		var tier = int(tiers[family])
		var current = config.base_tiers[family][tier]
		_label(upgrade_list, "%s  Lv.%d · %s" % [family, tier + 1, current.name], 19)
		if tier < config.base_tiers[family].size() - 1:
			var next = config.base_tiers[family][tier + 1]
			var unlock_day = int(rulings.unlock_days[family][tier + 1])
			_button(upgrade_list, "升级 %s → %s  ¥%d" % [family, next.name, _upgrade_price(int(next.unlock_fee))], _purchase_upgrade.bind(dialog, family), money < _upgrade_price(int(next.unlock_fee)) or (stock_only_mode and not _in_preparation() and day < unlock_day))
			if stock_only_mode and not _in_preparation() and day < unlock_day: _label(upgrade_list, "第 %d 个经营日开放；挑战D0可提前准备。" % unlock_day, 14, MUTED)
		else:
			_label(upgrade_list, "已达最高等级", 15, MUTED)
	_button(upgrade_list, "升级器材 Lv.%d  +%s秒 / ¥%s" % [equipment, config.equipment_time_bonus, _upgrade_price(int(config.equipment_price))], _purchase_upgrade.bind(dialog, ""), money < _upgrade_price(int(config.equipment_price)))
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _purchase_upgrade(dialog: AcceptDialog, family: String) -> void:
	dialog.queue_free()
	if family.is_empty(): _buy_equipment()
	else: _buy_tier(family)

func _purchase_bill(liquid: String, packs: int, base: float, date: int, levels: Dictionary, emergency = false, bulk = false, include_daily_events = true) -> Dictionary:
	return companion_progress.discount_bill(competition.purchase_bill(liquid, packs, base, date, levels, emergency, bulk, include_daily_events), str(companion.get("id", "")), pricing.catalog)

func _upgrade_price(raw: int) -> int:
	return companion_progress.upgrade_price(raw, str(companion.get("id", "")))

func _stock_price(liquid: String, emergency = false) -> int:
	var bill = _purchase_bill(liquid, 1, pricing.pack_price(liquid, tiers), day, tiers, emergency)
	return int(bill.total) if not bill.is_empty() else competition.package_price(liquid, pricing.pack_price(liquid, tiers), day, tiers, emergency)

func _in_preparation() -> bool:
	return day == 0 or challenge.state.phase in ["preparation", "rest"]

func _sync_challenge() -> void:
	competition.modern_mode = stock_only_mode
	competition.round_offset = int(challenge.state.start_day) - 1 if challenge.state.phase in ["preparation", "active", "result"] else 0
	competition.street.challenge_mode = challenge.state.phase in ["preparation", "active", "result"]
	competition.ingredient_aliases = {str(rulings.rum.canonical): str(rulings.rum.names[int(tiers.get(rulings.rum.family, 0))])} if stock_only_mode else {}

func _show_opening_visit() -> void:
	playing = false
	sound.enter("rival")
	_clear(page)
	_header(competition.rival().name)
	var panel = _panel(page)
	var portrait = TextureRect.new()
	portrait.texture = load(character_art.rivals[competition.state.rival])
	portrait.custom_minimum_size = Vector2(180, 180)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(portrait)
	_label(panel, challenge.rules.text.opening_wait if promotion.is_empty() else challenge.rules.text.opening.format({"drink": promotion.name}), 24, GOLD)
	for id in competition.street.data.responses:
		_button(panel, competition.street.data.responses[id].label, _answer_opening.bind(id))

func _answer_opening(id: String) -> void:
	if competition.state.receipts.has("opening"): return
	competition.state.receipts.opening = id
	competition.state.street.respect = clampi(int(competition.state.street.respect) + int(competition.street.data.responses[id].respect), -int(competition.street.data.numbers.respect_cap), int(competition.street.data.numbers.respect_cap))
	_save("promotion")
	_open_stock_day()

func _rival_actions(parent: Node) -> void:
	if _in_preparation(): return
	if stock_only_mode:
		for index in competition.daily_events.state.records.size():
			var record: Dictionary = competition.daily_events.state.records[index]
			var cost = competition.daily_events.action_cost(index, day)
			var label = competition.daily_events.prose.get("action_" + str(record.id))
			if record.heard and not record.resolved and competition.daily_events.rules.events[record.id].has("discount_margin_loss"):
				_button(parent, competition.daily_events.prose["discount_" + str(record.id)], _discount_daily_event.bind(index))
			if cost >= 0 and label is String: _button(parent, "%s ¥%d" % [label, cost], _resolve_daily_event.bind(index), money < cost or promotion.is_empty() or not _can_serve(promotion))
		return
	if competition.narrative(): return
	if competition.active(day) and competition.state.rival == "bella" and competition.state.licensed_recipes.is_empty():
		_button(parent, "授权主推联名 ¥%d" % int(pricing.catalog.other_prices.design_events.collaboration.price), _license_recipe)
	if competition.active(day) and competition.state.rival == "olga":
		_button(parent, "锁定明日采购 ¥%d" % int(competition.profile().lock_service_fee_override), _show_lock_service, day in competition.state.lock_days)
	if competition.state.rival == "duren" and "R-07" in competition.state.informed and int(competition.state.credit_limit) == 0:
		_button(parent, "接受专项赊购额度", _accept_credit)
	if not competition.content.regular_customer_ids.is_empty() and competition.state.rival == "marta":
		var reserve = CheckButton.new()
		reserve.text = "为熟客留座"
		reserve.button_pressed = competition.state.reserve_regular
		reserve.toggled.connect(func(value):
			competition.state.reserve_regular = value
			_save(current_phase))
		parent.add_child(reserve)
	if competition.state.rival == "viola" and "R-09" in competition.state.informed and not competition.state.receipts.has("R-09"):
		_button(parent, "自愿歇业赴品鉴会", _attend_tasting)
	if day >= int(competition.rules.timeline.ending_day) and competition.state.ending.is_empty() and competition.state.pending_ending.is_empty():
		for kind in competition.state.ending_ready:
			_button(parent, "确认" + {"counterplay": "应对结局", "alliance": "结盟", "takeover": "接手库存"}[kind], _confirm_rival_ending.bind(kind))

func _license_recipe() -> void:
	var fee = competition.license_recipe(promotion.id, day, money)
	if fee < 0:
		return
	money -= fee
	stock_ledger.daily.events += fee
	_save("preparation" if _in_preparation() else "shop")
	show_shop()

func _accept_credit() -> void:
	if competition.open_credit(day):
		_save("preparation" if _in_preparation() else "shop")
		show_shop()

func _show_lock_service() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	dialog.title = "锁定明日采购清单"
	dialog.min_size = Vector2i(680, 460)
	var column = VBoxContainer.new()
	var shell = Control.new()
	shell.custom_minimum_size = Vector2(640, 380)
	dialog.add_child(shell)
	shell.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label(column, "按当前基准包价锁定所选包数；少买或缺货不退服务费。", 17)
	var scroll = _scroll_column(column)
	scroll.get_parent().custom_minimum_size.y = 300
	var inputs = {}
	var names = stock.keys()
	names.sort()
	for name in names:
		var row = _row(scroll)
		var base = pricing.pack_price(name, tiers)
		var label = _label(row, "%s · 基准 ¥%s / 包" % [name, base], 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amount = SpinBox.new()
		amount.set_meta("ingredient", name)
		amount.min_value = 0
		amount.max_value = maxi(1, floori(money / maxf(1, base)))
		amount.step = 1
		row.add_child(amount)
		inputs[name] = amount
	add_child(dialog)
	dialog.confirmed.connect(func():
		var packs = {}
		var prices = {}
		for name in inputs:
			if int(inputs[name].value) > 0:
				packs[name] = int(inputs[name].value)
				prices[name] = pricing.pack_price(name, tiers)
		var fee = competition.lock_service(day, packs, prices, money)
		if fee >= 0:
			money -= fee
			stock_ledger.daily.events += fee
			_save("preparation" if _in_preparation() else "shop")
			show_shop()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _confirm_rival_ending(kind: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.theme = theme
	dialog.title = "确认本周目竞争结局"
	dialog.dialog_text = "此局只确认一种结局，次日解除竞争压力。已确认的债务和锁价服务仍需履行。"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if competition.confirm_ending(kind, day):
			_save(current_phase)
			show_shop()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _attend_tasting() -> void:
	if competition.state.rival != "viola" or competition.state.receipts.has("R-09"):
		return
	competition.state.receipts["R-09"] = "accepted"
	competition.state.voluntary_skip_days.append(day + 1)
	_save("preparation" if _in_preparation() else "shop")
	show_shop()

func _show_skipped_night() -> void:
	playing = false
	_clear(page)
	_header("赴品鉴会 · 今日自愿歇业")
	_label(page, "今晚没有营业，困难酒合规连胜保持原状。", 24, GOLD)
	_button(page, "回店，准备下一日", _next_day)

func _calm_rumor() -> void:
	var price = int(pricing.catalog.other_prices.design_events.reputation_round.price)
	if money < price or not competition.state.scheduled.any(func(event): return event.id == "S-07"):
		return
	money -= price
	competition.state.scheduled = competition.state.scheduled.filter(func(event): return event.id != "S-07")
	_save("preparation" if _in_preparation() else "shop")
	show_shop()

func _commit_stock_bill(bill: Dictionary) -> void:
	bill = companion_progress.discount_bill(bill, companion.id, pricing.catalog)
	money -= int(bill.total)
	var volume = int(bill.packs) * float(pricing.catalog.ingredients[bill.name].pack_ml)
	stock[bill.name] = float(stock.get(bill.name, 0)) + volume
	stock_ledger.purchase(bill.name, volume, float(bill.unit_cost), int(bill.total), bill.get("merchant_discount", false))
	companion_progress.purchase(bill, volume)
	competition.commit_purchase(bill, day)

func _buy_stock(liquid: String, packs = 1, emergency = false, bulk = false, use_credit = false) -> void:
	var bill = _purchase_bill(liquid, packs, pricing.pack_price(liquid, tiers), day, tiers, emergency, bulk)
	if bill.is_empty():
		return
	if use_credit:
		if emergency or competition.state.rival != "duren" or (int(competition.state.credit_due_day) > 0 and int(competition.state.credit_due_day) <= day) or int(competition.state.credit_used) + int(bill.total) > int(competition.state.credit_limit):
			return
		competition.state.credit_used += int(bill.total)
		competition.state.credit_due_day = day + int(competition.rules.rivals.duren.credit_payment_delay_days)
		money += int(bill.total)
	if money < int(bill.total):
		return
	_commit_stock_bill(bill)
	if use_credit:
		stock_ledger.daily.procurement -= int(bill.total)
	_save("preparation" if _in_preparation() else "shop")
	_sfx("sfx.purchase")
	_refresh_shop_purchase()

func _buy_tier(family: String) -> void:
	var next = int(tiers[family]) + 1
	if next >= config.base_tiers[family].size():
		return
	if stock_only_mode and not _in_preparation() and day < int(rulings.unlock_days[family][next]): return
	var raw_price = int(config.base_tiers[family][next].unlock_fee)
	var price = _upgrade_price(raw_price)
	if money < price:
		return
	money -= price
	tiers[family] = next
	companion_progress.upgrade(family, next, raw_price)
	if challenge.state.phase in ["active", "preparation"]: challenge.state.stats.upgrade_cost += price
	_sync_challenge()
	_save("preparation" if _in_preparation() else "shop")
	_sfx("sfx.upgrade")
	_refresh_shop_purchase()

func _buy_equipment() -> void:
	var price = _upgrade_price(int(config.equipment_price))
	if money < price:
		return
	money -= price
	companion_progress.upgrade("", equipment + 1, int(config.equipment_price))
	if challenge.state.phase in ["active", "preparation"]: challenge.state.stats.upgrade_cost += price
	equipment += 1
	_save("preparation" if _in_preparation() else "shop")
	_sfx("sfx.upgrade")
	_refresh_shop_purchase()

func _next_day() -> void:
	if challenge.state.phase == "result":
		challenge_view.result()
		return
	var closed_challenge = challenge.state.results.any(func(result): return int(result.day) == day)
	if not closed_challenge:
		for liquid in stock:
			if liquid not in config.base_names:
				var remaining_stock = floorf(float(stock[liquid]) * (1.0 - float(config.spoilage_ratio)))
				stock_ledger.consume(liquid, float(stock[liquid]) - remaining_stock, true)
				stock[liquid] = remaining_stock
	stock_ledger.finish_day(day)
	day += 1
	var planned = challenge.planned_promotion(day)
	if not planned.is_empty(): promotion = _find_recipe(planned)
	competition.apply_pending_ending(day)
	if int(competition.state.credit_due_day) > 0 and day >= int(competition.state.credit_due_day):
		var repaid = mini(money, int(competition.state.credit_used))
		money -= repaid
		competition.state.credit_used -= repaid
		if int(competition.state.credit_used) == 0:
			competition.state.credit_due_day = 0
	if day in competition.state.voluntary_skip_days:
		competition.state.receipts["R-09"] = "attended"
		competition.state.reputation += int(competition.rules.rivals.viola.tasting.reputation_gain)
		competition.cooperation(day)
		competition.prepare_market(day, pricing.catalog, tiers, recipes, stock, rng)
		_save("promotion")
		_show_skipped_night()
		return
	_save("promotion")
	show_promotion()

func _show_rumors() -> void:
	pause_menu.open_journal("messages")

func _record_rumor(text: String, speaker = "") -> void:
	text = JournalNotes.clean(text)
	if text.is_empty(): return
	if text not in rumors: rumors.append(text)
	if not journal_speakers.has(text): journal_speakers[text] = []
	if not speaker.is_empty() and speaker not in journal_speakers[text]: journal_speakers[text].append(speaker)

func _journal_speaker_text(note: String) -> String:
	var names: Array[String] = []
	for id in journal_speakers.get(note, []):
		for customer in customers:
			if customer.story_id == id: names.append(customer.name)
	return interface.journal.unknown_speaker if names.is_empty() else interface.journal.speaker.format({"names": interface.journal.speaker_separator.join(names)})

func _persist_journal() -> bool:
	# Manual saves still rewind the current drink; only notebook edits travel
	# into its start checkpoint, never cash, stock, costs or gameplay RNG.
	if playing and not reception_checkpoint.is_empty():
		reception_checkpoint.run.rumors = rumors.duplicate()
		reception_checkpoint.run.journal_favorites = journal_favorites.duplicate()
		reception_checkpoint.run.journal_speakers = journal_speakers.duplicate(true)
	return _save_manual()

func _snapshot(phase: String) -> Dictionary:
	var run = {"phase": phase, "money": money, "day": day, "equipment": equipment, "tiers": tiers.duplicate(true), "stock": stock.duplicate(true), "rumors": rumors.duplicate(true), "companion": companion.id, "promotion_id": promotion.get("id", ""), "queue": queue.duplicate(true), "guest_index": guest_index, "day_income": day_income, "day_served": day_served, "day_success": day_success}
	run.stock_only_mode = stock_only_mode
	run.journal_favorites = journal_favorites.duplicate()
	run.journal_speakers = journal_speakers.duplicate(true)
	run.selection_step = selection_step
	run.daily_events = competition.daily_events.state.duplicate(true)
	run.challenge = challenge.state.duplicate(true)
	run.companion_progress = companion_progress.state.duplicate(true)
	run.competition = competition.state.duplicate(true)
	run.day_consumable_budget = day_consumable_budget
	run.daily_costs = daily_costs
	run.stock_ledger = stock_ledger.snapshot()
	run.rival_id = null if competition.state.rival.is_empty() else competition.state.rival
	run.pricing_catalog_version = pricing.catalog.catalog_version
	run.rival_rules_version = competition.rules.rules_version
	run.rng = {"seed": str(rng.seed), "state": str(rng.state)}
	run.tutorial = tutorial_active
	return {"version": SaveSchema.VERSION, "meta": progress.snapshot(), "run": run}

func _save(phase: String) -> bool:
	current_phase = phase
	var snapshot = _snapshot(phase)
	if phase == "reception": reception_checkpoint = snapshot.duplicate(true)
	if save_slots.managed(): snapshot = save_slots.stamped(snapshot, save_slots.active_slot)
	last_save_ok = save_store.write_snapshot(config.save_path, snapshot, save_schema.decode)
	if not last_save_ok:
		_storage_notice(save_store.last_error)
	elif save_slots.managed(): save_slots.autosave(snapshot)
	return last_save_ok

func _save_manual() -> bool:
	var snapshot = reception_checkpoint if playing and not reception_checkpoint.is_empty() else _snapshot(current_phase)
	if save_slots.managed(): snapshot = save_slots.stamped(snapshot, save_slots.active_slot)
	last_save_ok = save_store.write_snapshot(config.save_path, snapshot, save_schema.decode)
	if not last_save_ok: _storage_notice(save_store.last_error)
	return last_save_ok

func _storage_notice(message: String) -> void:
	_log("save_notice", {"message": message})
	if is_instance_valid(storage_dialog):
		storage_dialog.dialog_text = message
		return
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	storage_dialog = dialog
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "存档提示"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _load_game(path: String = "") -> bool:
	var document = save_store.load_snapshot(config.save_path if path.is_empty() else path, save_schema.decode)
	if document.is_empty():
		_storage_notice(save_store.last_error)
		return false
	var selected_path = config.save_path if path.is_empty() else path
	if selected_path in save_slots.paths(): save_slots.activate(selected_path, document)
	var skip_shared_tutorial = selected_path in save_slots.paths() and document.run.tutorial and save_slots.profile_state().get("tutorial_completed", false)
	_restore_document(document)
	if skip_shared_tutorial:
		progress.advance()
		_reset_run(companion, true)
		if not last_save_ok: _restore_document(document)
	if save_store.loaded_backup:
		_storage_notice("主存档不可用，已恢复上一次有效备份。")
	return true

func _restore_document(document: Dictionary) -> void:
	# No live state is touched until all fields have passed schema validation.
	var snapshot: Dictionary = document.run
	pending_open_plan = {}
	rng.seed = int(snapshot.rng.seed)
	rng.state = int(snapshot.rng.state)
	progress.restore(document.meta)
	tutorial_active = progress.cycle == 1
	tutorial_measure_read = false
	playing = false
	pouring = false
	mixing = false
	brew = null
	guest = {}
	remaining = 0.0
	dialogue = 0
	rapport = false
	selected_cup = ""
	selected_ice = ""
	pouring_liquid = ""
	mix_time = 0.0
	mix_position = 0.0
	money = int(snapshot.money)
	day = int(snapshot.day)
	equipment = int(snapshot.equipment)
	tiers = snapshot.tiers
	stock = snapshot.stock
	rumors = snapshot.rumors
	journal_favorites = snapshot.get("journal_favorites", []).duplicate()
	journal_speakers = snapshot.get("journal_speakers", {}).duplicate(true)
	last_mistake_report = {}
	pause_menu.journal.reset()
	queue = snapshot.queue
	guest_index = int(snapshot.guest_index)
	day_income = int(snapshot.day_income)
	day_served = int(snapshot.day_served)
	day_success = int(snapshot.day_success)
	stock_only_mode = snapshot.stock_only_mode
	selection_step = snapshot.selection_step
	competition.daily_events.state = snapshot.daily_events.duplicate(true)
	competition.state = snapshot.competition.duplicate(true)
	challenge.state = snapshot.challenge.duplicate(true)
	companion_progress.state = snapshot.companion_progress.duplicate(true)
	_sync_challenge()
	stock_ledger.restore(snapshot.stock_ledger)
	if stock_only_mode:
		for name in rulings.rum.names:
			if name == rulings.rum.canonical: continue
			stock[rulings.rum.canonical] += float(stock.get(name, 0))
			stock_ledger.batches[rulings.rum.canonical].append_array(stock_ledger.batches.get(name, []))
			stock[name] = 0.0
			stock_ledger.batches[name] = []
	day_consumable_budget = float(snapshot.day_consumable_budget)
	daily_costs = int(snapshot.daily_costs)
	promotion = {} if snapshot.promotion_id.is_empty() else _find_recipe(snapshot.promotion_id)
	current_phase = snapshot.phase
	for item in config.companions:
		if item.id == snapshot.companion:
			companion = item
	if not companion_progress.state.pending_rival.is_empty():
		challenge_view.choose_companion(companion_progress.state.pending_rival, false)
		return
	match snapshot.phase:
		"selection":
			if selection_step == "companion": _show_companion_selection()
			else: _show_rival_selection()
		"preparation":
			show_shop()
		"reception":
			_start_guest()
		"shop":
			show_shop()
		_:
			if day in competition.state.voluntary_skip_days:
				_show_skipped_night()
			else:
				show_promotion()

func _log(event: String, details: Dictionary) -> void:
	if log_file:
		log_file.seek_end()
		log_file.store_line(JSON.stringify({"time": Time.get_datetime_string_from_system(), "event": event, "data": details}))
		log_file.flush()

func _show_counter_cards() -> void:
	sound.enter("promotion")
	screen = "game"
	current_phase = "promotion"
	playing = false
	_clear(page)
	_header("街灯下的告示")
	var card_panel = _panel(page)
	card_panel.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column = _scroll_column(card_panel)
	var r = competition.rival()
	_label(column, str(r.name) + " · " + str(r.shop), 30, GOLD)
	if competition.state.rival == "karn": _label(column, competition.street.data.text.sales.format({"price": int(competition.rules.rivals.karn.competitor_initial_quote)}), 20)
	_label(column, r.pitch, 20)
	_label(column, competition.street.data.habits[competition.state.rival][0], 20)
	_label(column, "选一张开业对策。第六日可以换一次，当日少接待两位。", 18)
	for id in competition.street.data.cards:
		var card: Dictionary = competition.street.data.cards[id]
		_label(column, card.name + " · " + card.description, 17)
		_button(column, "选「%s」" % card.name, _select_counter_card.bind(id), not card.enabled or id == competition.state.street.card)
	if not competition.state.street.card.is_empty():
		_button(column, "沿用原来的办法", func():
			competition.state.receipts.keep_card = true
			_save("promotion")
			show_promotion())

func _select_counter_card(id: String) -> void:
	if not competition.street.choose(competition.state.street, id, competition.round_day(day)): return
	_save("promotion")
	show_promotion()

func _show_street_visit() -> void:
	sound.enter("rival")
	screen = "game"
	current_phase = "promotion"
	playing = false
	_clear(page)
	_header("门口有人")
	var panel = _panel(page)
	var portrait = TextureRect.new()
	portrait.texture = load(character_art.rivals[competition.state.rival])
	portrait.custom_minimum_size = Vector2(180, 240)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(portrait)
	var yesterday = ""
	if not competition.state.history.is_empty(): yesterday = _find_recipe(competition.state.history[-1].recipe_id).name
	_label(panel, competition.street.data.text.visit.format({"yesterday": yesterday}), 24)
	for id in competition.street.data.responses:
		_button(panel, competition.street.data.responses[id].label, _answer_street_visit.bind(id))

func _answer_street_visit(id: String) -> void:
	if not competition.street.respond(competition.state.street, id, competition.round_day(day)): return
	competition.state.reputation += int(competition.street.data.responses[id].reputation)
	_save("promotion")
	show_promotion()

func _finish_customer_record() -> void:
	guest_index += 1
	if guest_index >= queue.size():
		competition.prepare_market(day, pricing.catalog, tiers, recipes, stock, rng)
		companion_progress.close_day(self)
		competition.close_day(promotion, day)
		if challenge.active() and challenge.day(day) >= int(challenge.rules.days):
			stock_ledger.finish_day(day)
			challenge.update_net(stock_ledger, day)
			challenge.finish(day)
			companion_progress.finish(challenge)
		var tomorrow_stock = stock.duplicate(true)
		for name in tomorrow_stock:
			if name not in config.base_names:
				tomorrow_stock[name] = floorf(float(tomorrow_stock[name]) * (1.0 - float(config.spoilage_ratio)))
		if not stock_only_mode: OrderPlanner.new(competition, pricing, day + 1, tiers).repair_market(recipes, tomorrow_stock, money)

func _rival_drawn(entry: Dictionary) -> void:
	competition.reset(entry.id)
	competition.state.street.enabled = true
	selection_step = "companion"
	_save("selection")
	_show_companion_selection()

func _finish_preparation() -> void:
	if not _in_preparation(): return
	stock_ledger.finish_day(day)
	day = int(challenge.state.start_day) if challenge.state.phase == "preparation" else 1
	if challenge.state.phase == "preparation": challenge.state.phase = "active"
	_sync_challenge()
	_save("promotion")
	show_promotion()

func _open_stock_day() -> void:
	if challenge.active() and challenge.day(day) == 1 and not competition.state.receipts.has("opening"):
		_show_opening_visit()
		return
	if not competition.state.street.card.is_empty() and competition.street.effective(competition.state.street, competition.round_day(day)) == "offset" and promotion.id.begins_with("S-"):
		status_line.text = "错位要避开简单档。"
		return
	competition.daily_events.generate(day, rng)
	competition.begin_day(promotion, day, tiers)
	var count = maxi(1, rng.randi_range(int(config.customers_min), int(config.customers_max)) + competition.traffic_delta(promotion, day, pricing.calculate(promotion, tiers).price))
	count = challenge.count_for_day(count, day, int(config.customers_min))
	var guaranteed = int(config.promotion_guarantee) - int(competition.state.street.hit_loss)
	if challenge.active() and challenge.state.rival == "bella": guaranteed = int(challenge.rules.rivals.bella.promotion_guarantee)
	var reservations_today = challenge.state.reservations.filter(func(reservation): return int(reservation.due) == day)
	if not reservations_today.is_empty() and challenge.active() and challenge.state.rival in ["bella", "olga"]:
		count = maxi(count, guaranteed + reservations_today.size())
	var eligible = range(customers.size()).filter(func(index): return not (competition.state.street.captain.left and customers[index].story_id == competition.street.data.captain.id))
	var opportunity = challenge.due_opportunity(day) if challenge.active() else {}
	var orders: Array = []
	for index in count:
		var client = eligible[(int(challenge.state.stats.opportunities) + index) % eligible.size()] if challenge.active() else (index + day - 1) % customers.size()
		if competition.state.street.captain.left and customers[client].story_id == competition.street.data.captain.id: client = (client + 1) % customers.size()
		var recipe_id: String = promotion.id if index < guaranteed else competition.daily_events.sample_order(recipes, promotion.id, day, rng, challenge.active_trends(day))
		if not opportunity.is_empty() and index < int(challenge.rules.rivals.olga.orders_per_opportunity): recipe_id = opportunity.recipe
		orders.append({"recipe_id": recipe_id, "customer_index": client, "promotion_id": promotion.id})
	for reservation in challenge.state.reservations:
		if int(reservation.due) != day: continue
		var customer_index = customers.map(func(customer): return customer.story_id).find(reservation.customer)
		if customer_index >= 0: orders[-1] = {"recipe_id": rulings.reservation.recipe, "customer_index": customer_index, "promotion_id": promotion.id, "reservation_spec": rulings.reservation.duplicate(true)}
	challenge.register_day(day, orders.size())
	_commit_open_plan({"orders": orders, "bills": {}})

func _can_serve(recipe: Dictionary) -> bool:
	recipe = _normalize_recipe(recipe)
	if int(recipe.get("minimum_rum_tier", 1)) > int(tiers.get(rulings.rum.family, 0)) + 1: return false
	var required = {}
	for item in recipe.ingredients + recipe.topup: required[item.name] = float(required.get(item.name, 0)) + float(item.amount)
	for name in required:
		if float(stock.get(name, 0)) < float(required[name]): return false
	return true

func _show_unavailable_guest(recipe: Dictionary) -> void:
	screen = "game"
	_clear(page)
	_header("今晚这杯做不了")
	var panel = _panel(page)
	_label(panel, guest.name, 30, GOLD)
	_label(panel, "想要一杯%s。" % recipe.name, 22)
	_label(panel, "今晚无法提供这杯酒，客人先离开了。", 20)
	_button(panel, "送客，继续接待 →", _decline_guest.bind(guest_index))

func _decline_guest(expected_index = -1) -> void:
	if guest_index >= queue.size() or (expected_index >= 0 and expected_index != guest_index) or not queue[guest_index].get("unavailable", false): return
	_sfx("sfx.guest_depart")
	day_served += 1
	_finish_customer_record()
	_save("shop" if guest_index >= queue.size() else "reception")
	_next_guest()

func _resolve_daily_event(index: int) -> void:
	if current_phase != "shop" or index < 0 or index >= competition.daily_events.state.records.size(): return
	var cost = competition.daily_events.action_cost(index, day)
	if cost < 0 or money < cost or promotion.is_empty() or not _can_serve(promotion): return
	money -= cost
	stock_ledger.daily.events += cost
	queue.append({"recipe_id": promotion.id, "customer_index": 0, "event_appraisal": index})
	_start_guest()

func _discount_daily_event(index: int) -> void:
	if not competition.daily_events.discount(index, day): return
	_save("shop")
	show_shop()

func _verify_market_claim(claim: String) -> void:
	var text = competition.daily_events.verify(claim, guest.story_id, day)
	if text.is_empty(): return
	_sfx("sfx.intel")
	queue[guest_index].verification_text = text
	_draw_dialogue()

func _show_recipe_book() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = theme
	dialog.title = "酒谱"
	var column = VBoxContainer.new()
	column.custom_minimum_size = Vector2(640, 470)
	dialog.add_child(column)
	var selector = OptionButton.new()
	for recipe in recipes: selector.add_item(recipe.name)
	column.add_child(selector)
	var text = _rich(column, _recipe_description(recipes[0]), 400)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selector.item_selected.connect(func(index): text.text = _recipe_description(recipes[index]))
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _refresh_shop_purchase() -> void:
	var shop = page.get_node_or_null("ShopShelves")
	if shop == null: return
	shop.refresh()
	if is_instance_valid(header_stats): header_stats.text = "第 %d 周目 · 第 %d 日 · ¥%d" % [progress.cycle, day, money]
	if is_instance_valid(effects_label): effects_label.text = _effects_summary()

func _sfx(id: String) -> void:
	if is_instance_valid(sound): sound.play(id)
