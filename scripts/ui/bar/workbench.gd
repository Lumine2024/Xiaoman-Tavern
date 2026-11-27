extends Control
## Object-first bar. Drawer contents never move the countertop or the cylinder.
const Cylinder = preload("res://scripts/ui/bar/cylinder.gd")
const MixFocus = preload("res://scripts/ui/focus/mix_focus.gd")
const StraightFocus = preload("res://scripts/ui/focus/straight_focus.gd")
const MeasureFocus = preload("res://scripts/ui/focus/measure_focus.gd")
const DESIGN_SIZE = Vector2(620, 520)
var game
var canvas: Control
var table: TextureRect
var cabinet: Panel
var visual_layout: Dictionary
var measure_focus: CanvasLayer
var mix_focus: CanvasLayer
var straight_focus: CanvasLayer
var cylinder: Button
var shaker: Button
var bell: Button
var glass: Button
var gauge: Control
var drawer: PanelContainer
var drawer_scroll: ScrollContainer
var drawer_items: HBoxContainer
var drawer_buttons: HBoxContainer
var action_label: Label
var shaker_label: Label
var selection_label: Label
var drawer_kind = ""
var finishing = false
var shake_elapsed = 0.0
var tilts: Dictionary = {}
var straight_shake_left = 0.0

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 460
	canvas = Control.new()
	canvas.name = "Countertop"
	canvas.size = DESIGN_SIZE
	add_child(canvas)
	visual_layout = game.bar_ui.workbench_layout
	# Draw the cabinet behind the board; drawer faces belong below its front lip.
	cabinet = _cabinet_panel("Cabinet", "cabinet_rect", visual_layout.cabinet_color)
	_cabinet_panel("CabinetPlinth", "plinth_rect", visual_layout.plinth_color)
	table = TextureRect.new()
	table.name = "CounterBoard"
	table.texture = _cropped_texture("res://assets/bar/counter.png", visual_layout.counter_crop)
	table.material = ShaderMaterial.new()
	table.material.shader = preload("res://assets/materials/counter_surface.gdshader")
	var edges: Array = visual_layout.counter_edges
	table.material.set_shader_parameter("edges", Vector4(edges[0], edges[1], edges[2], edges[3]))
	table.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_place(table, "counter_rect")
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(table)
	cylinder = Cylinder.new()
	cylinder.name = "Cylinder"
	cylinder.game = game
	cylinder.position = Vector2(69, 49)
	cylinder.size = Vector2(90, 220)
	canvas.add_child(cylinder)
	shaker = _object("Shaker", "res://assets/shaker.png", Rect2(205, 79, 116, 188), _shaker_pressed)
	shaker.tooltip_text = "量好后倒入；备齐后开始调制"
	var bell_rect = visual_layout.bell_rect
	bell = _object("Bell", "res://assets/bar/bell.png", Rect2(bell_rect[0], bell_rect[1], bell_rect[2], bell_rect[3]), game._serve)
	bell.tooltip_text = "按铃出品"
	glass = _object("Glass", "res://assets/bar/cups_00.png", Rect2(359, 110, 105, 158), _glass_pressed)
	gauge = Control.new()
	gauge.name = "MixGauge"
	gauge.position = Vector2(329, 92)
	gauge.size = Vector2(22, 158)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	canvas.add_child(gauge)
	action_label = _caption(Vector2(22, 0), Vector2(576, 30), 21)
	shaker_label = _caption(Vector2(185, 272), Vector2(156, 30), 16)
	selection_label = _caption(Vector2(352, 272), Vector2(150, 38), 14)
	drawer_buttons = HBoxContainer.new()
	_place(drawer_buttons, "drawer_buttons_rect")
	drawer_buttons.add_theme_constant_override("separation", 10)
	canvas.add_child(drawer_buttons)
	drawer = PanelContainer.new()
	drawer.name = "OpenDrawer"
	_place(drawer, "open_drawer_rect")
	drawer.add_theme_stylebox_override("panel", game._bar_style(Color("142c2e")))
	canvas.add_child(drawer)
	var column = VBoxContainer.new()
	drawer.add_child(column)
	var heading = HBoxContainer.new()
	column.add_child(heading)
	var heading_label = game._label(heading, "", 16, game.GOLD)
	heading_label.name = "DrawerTitle"
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game._button(heading, "×", close_drawer)
	drawer_scroll = ScrollContainer.new()
	drawer_scroll.name = "ItemScroll"
	drawer_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(drawer_scroll)
	drawer_items = HBoxContainer.new()
	drawer_items.add_theme_constant_override("separation", 8)
	drawer_scroll.add_child(drawer_items)
	measure_focus = MeasureFocus.new()
	measure_focus.game = game
	add_child(measure_focus)
	mix_focus = MixFocus.new()
	mix_focus.game = game
	add_child(mix_focus)
	straight_focus = StraightFocus.new()
	straight_focus.game = game
	add_child(straight_focus)
	resized.connect(_layout)
	_layout()
	render()

func _place(control: Control, key: String) -> void:
	var rect: Array = visual_layout[key]
	control.position = Vector2(rect[0], rect[1])
	control.size = Vector2(rect[2], rect[3])

func _cropped_texture(path: String, region: Array) -> AtlasTexture:
	var texture = AtlasTexture.new()
	texture.atlas = load(path)
	var dimensions = texture.atlas.get_size()
	texture.region = Rect2(Vector2(region[0], region[1]) * dimensions, Vector2(region[2], region[3]) * dimensions)
	texture.filter_clip = true
	return texture

func _cabinet_panel(node_name: String, rect: String, color: String) -> Panel:
	var panel = Panel.new()
	panel.name = node_name
	_place(panel, rect)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.border_color = Color(visual_layout.cabinet_border)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	return panel

func _layout() -> void:
	if canvas == null:
		return
	var factor = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) / 2

func _object(node_name: String, path: String, rect: Rect2, action: Callable) -> Button:
	var button = Button.new()
	button.set_meta("audio_skip_ui", true)
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.85, 0.75, 0.5, 0.08) if state == "hover" else Color.TRANSPARENT
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	canvas.add_child(button)
	var visual = TextureRect.new()
	visual.name = "Visual"
	visual.texture = load(path)
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(visual)
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual.pivot_offset = rect.size * Vector2(.5, .8)
	return button

func _process(delta: float) -> void:
	var visual = shaker.get_node("Visual")
	straight_shake_left = maxf(0.0, straight_shake_left - delta)
	if (game.mixing or straight_shake_left > 0) and not game.pause_menu.reduced_motion:
		shake_elapsed += delta
		visual.rotation_degrees = sin(shake_elapsed * TAU / float(game.bar_ui.animation.shake_period)) * float(game.bar_ui.animation.shake_degrees)
	elif not tilts.has(visual):
		visual.rotation = 0
		shake_elapsed = 0.0

func play_straight_shake(seconds: float) -> void:
	if game.pause_menu.reduced_motion: return
	straight_shake_left = seconds

func play_tilt(control: Control) -> void:
	if game.pause_menu.reduced_motion: return
	if control == shaker.get_node("Visual"): straight_shake_left = 0.0
	if tilts.has(control): tilts[control].kill()
	control.pivot_offset = control.size * Vector2(.5, .8)
	var tween = create_tween()
	tilts[control] = tween
	var seconds = float(game.bar_ui.animation.tilt_seconds)
	var property = "tilt_degrees" if control == cylinder else "rotation_degrees"
	tween.tween_property(control, property, float(game.bar_ui.animation.tilt_degrees), seconds).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, property, 0.0, seconds).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): tilts.erase(control))

func cancel_tilt(control: Control) -> void:
	if tilts.has(control):
		tilts[control].kill()
		tilts.erase(control)
	if control == cylinder: cylinder.tilt_degrees = 0.0
	else: control.rotation = 0.0

func _caption(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label = game._label(canvas, "", font_size, game.TEXT)
	label.add_theme_stylebox_override("normal", game._bar_style(Color("10282be8")))
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func render() -> void:
	var b = game.brew
	finishing = b.stage >= 3
	game.shake_bar = gauge
	gauge.visible = b.stage == 2 and b.recipe.method != "直调"
	bell.disabled = b.stage != 5
	cylinder.modulate.a = 1.0 if b.stage < 2 else 0.45
	cylinder.disabled = b.stage >= 2
	cylinder.update_level()
	shaker_label.text = "倒入壶中" if b.stage < 2 else (b.recipe.method if b.stage == 2 else "倒入酒杯")
	shaker_label.visible = b.stage < 4 and not b.poured
	shaker.disabled = b.stage > 3 or (b.stage == 3 and (b.poured or game.selected_cup.is_empty() or game.selected_ice.is_empty()))
	glass.visible = finishing and not game.selected_cup.is_empty()
	if glass.visible:
		glass.get_node("Visual").texture = load(game.bar_assets.cups[game.selected_cup])
	glass.tooltip_text = "确认客人要求" if b.stage == 4 else "酒杯"
	selection_label.text = game.selected_ice if finishing else ""
	if b.stage == 4:
		selection_label.text = {"no_ice": "去冰", "no_garnish": "免装饰", "standard": "确认出品"}.get(game.guest.request, "确认出品")
	elif b.stage == 5:
		selection_label.text = "、".join(b.garnishes)
	if b.poured: selection_label.text = "已入杯\n" + selection_label.text
	selection_label.visible = not selection_label.text.is_empty()
	match b.stage:
		0, 1: action_label.text = "%s · %s ml" % [game.ingredient_label(b.target().name), str(float(b.target().amount)).trim_suffix(".0")]
		2: action_label.text = "调制"
		3: action_label.text = "后注" if b.poured else "杯具与冰"
		4: action_label.text = "客人要求"
		5: action_label.text = "装饰 · 出品"
	game._clear(drawer_buttons)
	var kinds = ["ice", "cups", "garnishes"] if finishing else ["base", "mixer"]
	for kind in kinds:
		var button = Button.new()
		button.name = kind
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.set_meta("audio_skip_ui", true)
		button.text = game.bar_ui.drawer_names[kind]
		button.add_theme_font_size_override("font_size", 19)
		var style = StyleBoxTexture.new()
		style.texture = _cropped_texture("res://assets/bar/drawer.png", visual_layout.drawer_crop)
		style.content_margin_top = visual_layout.drawer_text_top
		style.content_margin_bottom = visual_layout.drawer_text_bottom
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, style)
		button.disabled = (kind == "garnishes" and b.stage < 5) or (kind in ["ice", "cups"] and b.stage != 3) or (kind in ["base", "mixer"] and b.stage == 2)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(open_drawer.bind(kind))
		drawer_buttons.add_child(button)
	# Do not carry ingredient drawers into the finishing phase.
	if (finishing and drawer_kind in ["base", "mixer", "solids"]) or (not finishing and drawer_kind in ["ice", "cups", "garnishes"]):
		drawer_kind = ""
	if b.stage == 2 and not b.recipe.pre_solids.is_empty() and not _solids_ready():
		drawer_kind = "solids"
	if b.stage == 3 and b.poured:
		drawer_kind = "topup"
	elif drawer_kind == "topup":
		drawer_kind = ""
	if drawer_kind.is_empty():
		close_drawer()
	else:
		open_drawer(drawer_kind)
	_draw_drink()

func _solids_ready() -> bool:
	for item in game.brew.recipe.pre_solids:
		if item.name not in game.brew.pre_solids:
			return false
	return true

func _shaker_pressed() -> void:
	match game.brew.stage:
		0, 1: game._transfer()
		2:
			if not _solids_ready():
				open_drawer("solids")
			elif game.brew.recipe.method == "直调":
				game._finish_straight()
			else:
				game._toggle_mix()
		3:
			if not game.selected_cup.is_empty() and not game.selected_ice.is_empty() and not game.brew.poured:
				game._pour_into_glass()

func _glass_pressed() -> void:
	if game.brew.stage == 4:
		game._special(true)

func close_drawer() -> void:
	if not drawer_kind.is_empty(): game._sfx("sfx.drawer_close")
	drawer_kind = ""
	drawer.hide()

func open_drawer(kind: String) -> void:
	if drawer_kind != kind: game._sfx("sfx.drawer_open")
	drawer_kind = kind
	drawer.show()
	drawer.get_child(0).get_child(0).get_node("DrawerTitle").text = "  " + game.bar_ui.drawer_names[kind]
	game._clear(drawer_items)
	var items: Array = []
	var group = kind
	match kind:
		"base", "mixer":
			group = "liquids"
			for item in game.selectable_liquids():
				if (item in game.config.base_names) == (kind == "base"):
					items.append(item)
			items.sort()
		"solids":
			group = "garnishes"
			for item in game.brew.recipe.pre_solids:
				items.append(item.name)
		"topup":
			group = "liquids"
			items.append(game.brew.recipe.topup[game.brew.topup_index].name)
		_: items = game.config[kind]
	for item in items:
		var card = VBoxContainer.new()
		card.custom_minimum_size.x = 92
		drawer_items.add_child(card)
		var button = TextureButton.new()
		button.set_meta("audio_skip_ui", true)
		button.name = item
		button.texture_normal = load(game.bar_assets[group][game.ingredient_label(item) if group == "liquids" else item])
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(92, 80)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = "%s · %.0f ml" % [game.ingredient_label(item), float(game.stock[item])] if group == "liquids" else item
		button.disabled = (group == "liquids" and float(game.stock[item]) <= 0) or (kind == "garnishes" and item in game.brew.garnishes) or (kind == "solids" and item in game.brew.pre_solids)
		button.pressed.connect(_choose.bind(kind, item))
		card.add_child(button)
		var label = game._label(card, game.ingredient_label(item) if group == "liquids" else item, 14, game.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if button.disabled:
			label.add_theme_color_override("font_color", game.MUTED)
			button.modulate.a = 0.45
		elif (kind in ["base", "mixer"] and game.brew.stage < 2 and item == game.brew.target().name) or (kind == "cups" and item == game.selected_cup) or (kind == "ice" and item == game.selected_ice):
			label.add_theme_color_override("font_color", game.GOLD)
			button.modulate = Color("e8cc91")

func _choose(kind: String, item: String) -> void:
	match kind:
		"base", "mixer":
			if game.brew.stage < 2:
				game._toggle_pour(item)
		"cups": game._select_cup(item)
		"ice": game._select_ice(item)
		"garnishes": game._garnish(item)
		"solids": game._add_pre_solid(item)
		"topup":
			var amount = float(game.brew.recipe.topup[game.brew.topup_index].amount)
			if float(game.stock[item]) >= amount:
				game._topup()

func _draw_gauge() -> void:
	var b = game.brew
	if b.stage != 2 or b.recipe.method == "直调":
		return
	var height = gauge.size.y
	var target = float(game.config.mix_target)
	var tolerance = float(game.config.mix_tolerance[b.recipe.method])
	var perfect = float(game.config.perfect_tolerance)
	gauge.draw_style_box(game._bar_style(Color("243e40")), Rect2(0, 0, 22, height))
	gauge.draw_rect(Rect2(0, (1 - target - tolerance) * height, 22, tolerance * 2 * height), Color("8f854e"))
	gauge.draw_rect(Rect2(0, (1 - target - perfect) * height, 22, perfect * 2 * height), game.GOLD)
	var y = (1 - game.mix_position) * height
	gauge.draw_line(Vector2(-4, y), Vector2(26, y), game.TEXT, 3)

func _draw_drink() -> void:
	for child in glass.get_children():
		if child.name == "Visual": continue
		glass.remove_child(child)
		child.queue_free()
	if not glass.visible: return
	var artwork = preload("res://scripts/ui/bar/drink_display.gd").new()
	artwork.name = "DrinkLiquid"
	artwork.assets = game.bar_assets
	artwork.colors = game.drink_colors
	artwork.settings = game.bar_ui
	artwork.cup = game.selected_cup
	artwork.ice = game.brew.ice if game.brew.poured else game.selected_ice
	artwork.garnishes = game.brew.garnishes.duplicate()
	artwork.recipe_name = game.brew.recipe.name
	artwork.has_liquid = game.brew.poured
	glass.get_node("Visual").hide()
	glass.add_child(artwork)
	artwork.size = glass.size
