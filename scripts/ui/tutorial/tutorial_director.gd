extends CanvasLayer
## Derive the next lesson from real gameplay; no duplicate brewing state.
var game
var veil: Control
var story_panel: PanelContainer
var story_label: Label
var exit_button: Button
var targets: Array[Control] = []
var lit: Array[Rect2] = []
var step = ""
var settings: Dictionary
var elapsed = 0.0

class Veil extends Control:
	var director
	func _has_point(point: Vector2) -> bool:
		for target in director.targets:
			if is_instance_valid(target) and director.rect_for(target).has_point(point):
				return false
		return true
	func _draw() -> void:
		# Subtract the union of all lit rectangles, without double-darkening overlaps.
		var cuts: Array = [0.0, size.y]
		for hole in director.lit:
			cuts.append(clampf(hole.position.y, 0, size.y))
			cuts.append(clampf(hole.end.y, 0, size.y))
		cuts.sort()
		for index in range(cuts.size() - 1):
			var top = float(cuts[index])
			var bottom = float(cuts[index + 1])
			if bottom <= top: continue
			var spans: Array = []
			for hole in director.lit:
				if hole.position.y <= top and hole.end.y >= bottom:
					spans.append(Vector2(maxf(0, hole.position.x), minf(size.x, hole.end.x)))
			spans.sort_custom(func(a, b): return a.x < b.x)
			var cursor = 0.0
			for span in spans:
				if span.x > cursor:
					draw_rect(Rect2(cursor, top, span.x - cursor, bottom - top), Color(director.settings.shade))
				cursor = maxf(cursor, span.y)
			if cursor < size.x:
				draw_rect(Rect2(cursor, top, size.x - cursor, bottom - top), Color(director.settings.shade))
		var border = Color(director.settings.border)
		border.a *= 0.75 + 0.25 * sin(director.elapsed * TAU / float(director.settings.pulse_seconds))
		for target in director.targets:
			if is_instance_valid(target) and target.name not in ["PourStopArea", "MixStopArea"]:
				draw_rect(director.rect_for(target).grow(float(director.settings.padding)), border, false, float(director.settings.border_width))

func _ready() -> void:
	settings = game.tutorial.spotlight
	layer = int(settings.layer)
	veil = Veil.new()
	veil.director = self
	veil.name = "TutorialSpotlight"
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_panel = PanelContainer.new()
	story_panel.theme = game.theme
	var story_style = game._bar_style(Color(settings.story_color))
	story_style.content_margin_left = float(settings.story_padding)
	story_style.content_margin_right = float(settings.story_padding)
	story_style.content_margin_top = float(settings.story_padding)
	story_style.content_margin_bottom = float(settings.story_padding)
	story_panel.add_theme_stylebox_override("panel", story_style)
	add_child(story_panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(settings.story_separation))
	story_panel.add_child(row)
	story_label = game._label(row, "", int(settings.story_font_size), game.TEXT)
	story_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_button = game._button(row, game.tutorial_story.exit_text, game.show_start)
	refresh()

func rect_for(control: Control) -> Rect2:
	var result = control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	var parent = control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents:
			result = result.intersection(parent.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, parent.size))
		parent = parent.get_parent()
	return result

func _process(delta: float) -> void:
	elapsed += delta
	refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB and game.screen == "game":
		game.pause_menu.open_journal()
		get_viewport().set_input_as_handled()
		return
	if not veil.visible or not event is InputEventKey or not event.pressed: return
	# Tab/keyboard activation must not reach a previously focused, now dark button.
	if event.keycode in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		var focus = get_viewport().gui_get_focus_owner()
		var measuring = game.tutorial_context == "reception" and (game.workbench.measure_focus.shown or game.workbench.mix_focus.shown)
		if event.keycode == KEY_TAB or (focus not in targets and focus != exit_button and not (measuring and event.keycode == KEY_SPACE)):
			get_viewport().set_input_as_handled()

func choose(control: Control, key: String) -> void:
	step = key
	if is_instance_valid(control) and control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
		targets.append(control)

func drawer_item(kind: String, item: String, key: String, values: Dictionary) -> void:
	# Bind narration to the drawer being requested in every brewing stage.
	values.drawer = game.bar_ui.drawer_names[kind]
	var bench = game.workbench
	if not bench.drawer.visible or bench.drawer_kind != kind:
		if bench.drawer.visible:
			choose(bench.drawer.get_child(0).get_child(0).get_child(1), "close_drawer")
		else:
			choose(bench.drawer_buttons.get_node_or_null(kind), "drawer")
		return
	for card in bench.drawer_items.get_children():
		var button = card.get_child(0)
		if button.name == item:
			bench.drawer_scroll.ensure_control_visible(card)
			choose(button, key)
			return

func dialogue_targets(key: String) -> void:
	step = key
	lit.append(rect_for(game.dialogue_box))
	for child in game.dialogue_box.get_children():
		if child is BaseButton: choose(child, key)

func refresh() -> void:
	if not is_instance_valid(veil): return
	var active = game.tutorial_active and not game.tutorial_context.is_empty()
	var guided = game.tutorial.guided_guest_numbers.any(func(number): return int(number) == game.guest_index + 1)
	var independent = active and game.tutorial_context == "reception" and not guided
	if active and game.tutorial_context == "shop" and int(game.stock_ledger.daily.procurement) > 0:
		step = "explore_shop"
		if is_instance_valid(game.tutorial_hint):
			game.tutorial_hint.text = game.tutorial_story.speaker + "\n" + game.tutorial_story.story.finish
		active = false
	if independent:
		step = "independent"
		if is_instance_valid(game.tutorial_hint):
			game.tutorial_hint.text = game.tutorial_story.speaker + "\n“" + str(game.tutorial_story.independent_notes.get(str(game.guest_index + 1), "")) + "”"
		active = false
	veil.visible = active
	story_panel.visible = active
	targets.clear()
	lit.clear()
	if not active: return
	var values = {}
	match game.tutorial_context:
		"promotion": choose(game.tutorial_action, "promotion")
		"settlement":
			for node_name in ["ServedDrinkPreview", "SettlementDetails"]:
				var preview = game.page.find_child(node_name, true, false)
				if preview != null: lit.append(rect_for(preview))
			var key = "settlement_error" if game.brew.final_errors() > 0 else ("settlement_last" if game.guest_index >= game.queue.size() else "settlement")
			key = game.tutorial.settlement_story_keys.get(str(game.guest_index), key)
			choose(game.tutorial_action, key)
		"shop":
			if int(game.stock_ledger.daily.procurement) > 0:
				choose(game.tutorial_action, "finish")
			else:
				choose(game.tutorial_purchase_button, "shop")
				if is_instance_valid(game.tutorial_purchase_button):
					var scroll = game.tutorial_purchase_button.get_parent().get_parent()
					if scroll is ScrollContainer: scroll.ensure_control_visible(game.tutorial_purchase_button)
		"reception":
			var b = game.brew
			var bench = game.workbench
			var focus = bench.measure_focus
			values = {"guest": game.guest.name, "drink": b.recipe.name, "cup": b.recipe.cup, "ice": b.expected_ice(), "method": b.recipe.method}
			if b.stage < 2:
				values.liquid = b.target().name
				values.amount = String.num(float(b.target().amount), 2)
			if focus.shown:
				step = focus.phase
				if focus.phase == "reading": choose(focus.read_button, "pour_read")
				elif focus.phase == "pouring": choose(focus.overlay, "pour")
				lit.append(rect_for(focus.overlay))
			elif bench.mix_focus.shown:
				step = "mix_" + bench.mix_focus.phase
				if bench.mix_focus.phase == "mixing": choose(bench.mix_focus.overlay, "mix_stop")
				lit.append(rect_for(bench.mix_focus.overlay))
			elif bench.straight_focus.shown:
				step = "straight_" + bench.straight_focus.phase
				targets.append(bench.straight_focus.overlay)
				lit.append(rect_for(bench.straight_focus.overlay))
			elif game.dialogue == 0:
				dialogue_targets("request")
			elif b.stage < 2:
				if b.measured > 0: choose(bench.shaker, "transfer")
				else: drawer_item("base" if b.target().name in game.config.base_names else "mixer", b.target().name, "ingredient", values)
			elif b.stage == 2:
				if game.dialogue == 1: dialogue_targets("chat")
				elif not bench._solids_ready():
					for item in b.recipe.pre_solids:
						if item.name not in b.pre_solids:
							values.garnish = item.name
							drawer_item("solids", item.name, "solid", values)
							break
				else:
					choose(bench.shaker, "straight" if b.recipe.method == "直调" else ("mix_stop" if game.mixing else "mix_start"))
					if game.mixing: lit.append(rect_for(bench.gauge))
			elif b.stage == 3:
				if b.poured:
					values.liquid = b.recipe.topup[b.topup_index].name
					drawer_item("topup", values.liquid, "topup", values)
				elif game.selected_cup != b.recipe.cup: drawer_item("cups", b.recipe.cup, "cup", values)
				elif game.selected_ice != b.expected_ice(): drawer_item("ice", b.expected_ice(), "ice", values)
				else: choose(bench.shaker, "glass_pour")
			elif b.stage == 4:
				if game.dialogue == 2: dialogue_targets("intel")
				else: choose(bench.glass, "special")
			else:
				var missing = b.expected_garnishes().filter(func(item): return item not in b.garnishes)
				if missing.is_empty(): choose(bench.bell, "serve")
				else:
					values.garnish = missing[0]
					drawer_item("garnishes", missing[0], "garnish", values)
	var prose = game.tutorial_story.order_notes[game.guest_index] if step == "request" else (game.tutorial_story.story.straight_transition if step.begins_with("straight_") else game.story_catalog.tutorial_text(step, values))
	var text = game.tutorial_story.speaker + "\n“" + prose + "”"
	if is_instance_valid(game.tutorial_hint):
		game.tutorial_hint.text = text
		story_panel.position = rect_for(game.tutorial_hint.get_parent().get_parent()).position
		story_panel.size = rect_for(game.tutorial_hint.get_parent().get_parent()).size
	if game.tutorial_context == "reception" and (game.workbench.measure_focus.shown or game.workbench.mix_focus.shown or game.workbench.straight_focus.shown):
		story_panel.position = Vector2(float(settings.focus_story_margin), float(settings.focus_story_top))
		story_panel.size = Vector2(veil.size.x - float(settings.focus_story_margin) * 2, float(settings.focus_story_height))
	story_label.text = text
	for target in targets: lit.append(rect_for(target).grow(float(settings.padding)))
	var keyboard_focus = get_viewport().gui_get_focus_owner()
	if keyboard_focus != null and keyboard_focus not in targets and keyboard_focus != exit_button: keyboard_focus.release_focus()
	veil.queue_redraw()
