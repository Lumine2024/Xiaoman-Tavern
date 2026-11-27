extends CanvasLayer
## Fade ordinary pages through black; zoom result/return views across a captured frame.
var game
var settings: Dictionary
var busy = false
var next_mode = "fade"
var last_mode = "fade"
var overlay: Control
var black: ColorRect
var outgoing: TextureRect
var tween: Tween
var base_transform = Transform2D.IDENTITY
var moves_canvas = false
var generation = 0
var source_rect = Rect2()
var zoom_material: ShaderMaterial
var provide_backdrop = true

func _ready() -> void:
	settings = game.bar_ui.transitions
	layer = int(settings.layer)
	if provide_backdrop:
		var backdrop = game.get_node("TavernBackdrop") as TextureRect
		var background_layer = CanvasLayer.new()
		background_layer.layer = -1
		add_child(background_layer)
		var background = TextureRect.new()
		background.texture = backdrop.texture
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background_layer.add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black = ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outgoing = TextureRect.new()
	outgoing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outgoing.stretch_mode = TextureRect.STRETCH_SCALE
	outgoing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outgoing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	zoom_material = ShaderMaterial.new()
	zoom_material.shader = preload("res://assets/materials/transition_zoom.gdshader")
	zoom_material.set_shader_parameter("edge_feather", float(settings.edge_feather))
	overlay.add_child(outgoing)
	overlay.hide()

func begin() -> void:
	var mode = next_mode
	next_mode = "fade"
	cancel()
	last_mode = mode
	var duration = float(settings.zoom_seconds) if mode != "fade" else float(settings.fade_out_seconds) + float(settings.fade_in_seconds)
	if duration <= 0 or game.pause_menu.reduced_motion: return
	var screenshot: Image
	if DisplayServer.get_name() != "headless": screenshot = get_viewport().get_texture().get_image()
	base_transform = get_viewport().canvas_transform
	source_rect = _subject_rect(mode, true)
	outgoing.texture = ImageTexture.create_from_image(screenshot) if screenshot != null and not screenshot.is_empty() else null
	outgoing.position = Vector2.ZERO
	outgoing.size = get_viewport().get_visible_rect().size
	outgoing.scale = Vector2.ONE
	outgoing.modulate = Color.WHITE
	outgoing.material = null
	black.modulate.a = 1.0
	busy = true
	overlay.show()
	if mode == "fade":
		tween = create_tween()
		tween.tween_property(outgoing, "modulate:a", 0.0, float(settings.fade_out_seconds))
		tween.tween_property(black, "modulate:a", 0.0, float(settings.fade_in_seconds))
	else:
		black.modulate.a = 0.0
		_start_zoom.call_deferred(generation, mode)
	if mode == "fade": tween.tween_callback(cancel)

func _subject_rect(mode: String, before: bool) -> Rect2:
	if (mode == "zoom_in") == before and is_instance_valid(game.workbench):
		return game.workbench.glass.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, game.workbench.glass.size)
	var preview = game.page.find_child("ServedDrinkPreview", true, false)
	if preview != null:
		return preview.drink.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, preview.drink.size)
	var view_size = get_viewport().get_visible_rect().size
	return Rect2(view_size * Vector2(settings.anchor[0], settings.anchor[1]), Vector2.ONE)

func _start_zoom(token: int, mode: String) -> void:
	# Containers settle before mapping the old glass onto the new glass rectangle.
	await get_tree().process_frame
	if token != generation or not busy: return
	var target_rect = _subject_rect(mode, false)
	var ratio = clampf(source_rect.size.y / maxf(1.0, target_rect.size.y), float(settings.min_subject_scale), float(settings.max_subject_scale))
	var source = source_rect.get_center()
	var target = target_rect.get_center()
	moves_canvas = true
	outgoing.material = zoom_material
	_apply_zoom(0.0, ratio, source, target)
	tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(weight): _apply_zoom(weight, ratio, source, target), 0.0, 1.0, float(settings.zoom_seconds))
	tween.tween_callback(cancel)

func _apply_zoom(weight: float, incoming_scale: float, source: Vector2, target: Vector2) -> void:
	var center = source.lerp(target, weight)
	var factor = lerpf(incoming_scale, 1.0, weight)
	get_viewport().canvas_transform = Transform2D(0.0, Vector2.ONE * factor, 0.0, center-target*factor) * base_transform
	factor = lerpf(1.0, 1.0/incoming_scale, weight)
	zoom_material.set_shader_parameter("zoom", factor)
	zoom_material.set_shader_parameter("source_point", source/outgoing.size)
	zoom_material.set_shader_parameter("current_point", center/outgoing.size)
	outgoing.modulate.a = 1.0-weight

func cancel() -> void:
	generation += 1
	if tween != null: tween.kill()
	if moves_canvas: get_viewport().canvas_transform = base_transform
	moves_canvas = false
	busy = false
	if is_instance_valid(overlay): overlay.hide()
	if is_instance_valid(outgoing): outgoing.texture = null

func _input(event: InputEvent) -> void:
	if not busy or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		if game.pause_menu.opened: game.pause_menu.close()
		elif game.screen not in ["title", "selection"]: game.pause_menu.open()
	elif event.keycode == KEY_TAB and game.screen == "game":
		game.pause_menu.open_journal()
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	cancel()
