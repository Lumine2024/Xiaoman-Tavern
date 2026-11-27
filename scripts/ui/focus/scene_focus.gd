extends CanvasLayer
## Shared real-scene camera transition and modal input for bar activities.
signal transition_finished
var game
var settings: Dictionary
var overlay: Control
var shown = false
var phase = "idle"
var original_transform = Transform2D.IDENTITY
var zoom_transform = Transform2D.IDENTITY
var tween: Tween
var scene_ui: Array = []

func _ready() -> void:
	settings = game.bar_ui[settings_key()]
	layer = int(settings.layer)
	overlay = Control.new()
	overlay.theme = game.theme
	overlay.name = stop_area_name()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.focus_mode = Control.FOCUS_ALL
	overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if manual_stop_enabled() and phase == active_phase(): close()
			overlay.accept_event())
	var footer = game._row(overlay)
	footer.name = "FocusFooter"
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.anchor_right = 1
	footer.offset_left = 16
	footer.offset_right = -16
	footer.offset_top = -52
	footer.offset_bottom = -8
	var hint = game._label(footer, activity_hint(), 18, game.TEXT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_stylebox_override("normal", game._bar_style(Color("10282be8")))
	game._button(footer, game.interface.menu.journal, func(): game.pause_menu.open_journal())
	game._button(footer, game.interface.menu.hint, func(): game.pause_menu.open())
	overlay.hide()

func settings_key() -> String:
	return ""

func stop_area_name() -> String:
	return ""

func active_phase() -> String:
	return ""

func manual_stop_enabled() -> bool:
	return true

func activity_hint() -> String:
	return "点击画面 / 空格停止"

func can_start() -> bool:
	return game.playing and game.brew != null

func _start_activity() -> void:
	pass

func _stop_activity() -> void:
	pass

func _after_close() -> void:
	pass

func _cancel_activity() -> void:
	pass

func _open_view(rect: Rect2) -> void:
	if shown or not can_start(): return
	original_transform = get_viewport().canvas_transform
	var viewport_size = get_viewport().get_visible_rect().size
	var factor = minf(viewport_size.y * float(settings.subject_height_ratio) / rect.size.y, viewport_size.x * float(settings.subject_width_ratio) / rect.size.x)
	var destination = viewport_size * Vector2(settings.screen_center[0], settings.screen_center[1])
	zoom_transform = Transform2D(0, Vector2.ONE * factor, 0, destination - rect.get_center() * factor) * original_transform
	scene_ui.clear()
	for name in ["SpeechBubble", "Instructions"]:
		var control = game.page.find_child(name, true, false)
		if control != null: scene_ui.append({"control":control, "color":control.modulate})
	for control in [game.workbench.action_label, game.workbench.shaker_label, game.workbench.selection_label]:
		scene_ui.append({"control":control, "color":control.modulate})
	shown = true
	phase = "zoom_in"
	_cancel_activity()
	overlay.show()
	overlay.grab_focus()
	_animate(zoom_transform, float(settings.zoom_in_seconds), func():
		if not can_start():
			dismiss()
			return
		phase = active_phase()
		_start_activity()
		transition_finished.emit())

func _animate(destination: Transform2D, seconds: float, completed: Callable) -> void:
	if tween != null: tween.kill()
	if game.pause_menu.reduced_motion: seconds = 0.0
	if seconds <= 0:
		_apply_transform(destination)
		completed.call()
		return
	var start = get_viewport().canvas_transform
	tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(weight): _apply_transform(start.interpolate_with(destination, weight)), 0.0, 1.0, seconds)
	tween.tween_callback(completed)

func _apply_transform(value: Transform2D) -> void:
	get_viewport().canvas_transform = value
	var zoom_scale = zoom_transform.get_scale().x / original_transform.get_scale().x
	var current_scale = value.get_scale().x / original_transform.get_scale().x
	var fade = clampf((current_scale - 1.0) / maxf(0.001, zoom_scale - 1.0), 0, 1)
	for item in scene_ui:
		if is_instance_valid(item.control):
			item.control.modulate = Color(item.color, item.color.a * (1.0 - fade))

func close() -> void:
	if not shown or phase == "zoom_out": return
	_stop_activity()
	phase = "zoom_out"
	_animate(original_transform, float(settings.zoom_out_seconds), func():
		shown = false
		phase = "idle"
		overlay.hide()
		_after_close()
		transition_finished.emit())

func dismiss() -> void:
	if tween != null: tween.kill()
	if shown:
		_apply_transform(original_transform)
		_cancel_activity()
	scene_ui.clear()
	shown = false
	phase = "idle"
	if is_instance_valid(overlay): overlay.hide()

func _exit_tree() -> void:
	dismiss()

func _input(event: InputEvent) -> void:
	if not shown or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_TAB:
		game.pause_menu.open_journal()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		game.pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		if manual_stop_enabled() and phase == active_phase(): close()
		get_viewport().set_input_as_handled()
