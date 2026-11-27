extends Button
## Liquid level and target share the same scale; zoom never changes the measurement.
var game
var zoomed = false
var tilt_degrees = 0.0:
	set(value):
		tilt_degrees = value
		queue_redraw()
const GLASS = preload("res://assets/bar/cylinder.png")
var well: Rect2

func _ready() -> void:
	var region: Array = game.bar_ui.cylinder.well_rect
	well = Rect2(Vector2(region[0], region[1]) * size, Vector2(region[2], region[3]) * size)
	flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pivot_offset = Vector2(45, 215)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "点击停止倒酒；点调酒壶倒入"
	pressed.connect(func(): game._stop_pour())

func level_y(amount: float) -> float:
	return well.end.y - clampf(amount / float(game.config.jigger_capacity), 0, 1) * well.size.y

func update_level() -> void:
	# The viewport zooms the real glass together with its surroundings.
	zoomed = game.workbench.measure_focus.shown
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	var angle = deg_to_rad(tilt_degrees)
	draw_set_transform(pivot_offset - pivot_offset.rotated(angle), angle)
	var amount = float(game.brew.measured)
	var liquid = game.brew.selected_liquid
	var color = Color("#" + game.drink_colors.liquids[game.ingredient_label(liquid)]) if not liquid.is_empty() else Color.TRANSPARENT
	var y = level_y(amount)
	if amount > 0:
		draw_rect(Rect2(well.position.x, y, well.size.x, well.end.y - y), color)
		draw_line(Vector2(well.position.x, y), Vector2(well.end.x, y), color.lightened(0.3), 2)
	draw_texture_rect(GLASS, Rect2(Vector2.ZERO, size), false)
	var font = get_theme_default_font()
	for i in range(11):
		var mark_y = level_y(float(game.config.jigger_capacity) * i / 10.0)
		draw_line(Vector2(48 if i % 5 == 0 else 56, mark_y), Vector2(65, mark_y), Color("b8cbbc"), 1)
		if i % 5 == 0:
			draw_string(font, Vector2(1, mark_y + 4), "%.0f" % (float(game.config.jigger_capacity) * i / 10.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c6d6c7"))
	if game.brew.stage < 2:
		var target_y = level_y(float(game.brew.target().amount))
		draw_rect(Rect2(22, target_y - 4, 47, 8), Color(0.86, 0.72, 0.47, 0.24))
		draw_line(Vector2(20, target_y), Vector2(73, target_y), Color("f2d485"), 2)
		draw_colored_polygon(PackedVector2Array([Vector2(79, target_y), Vector2(87, target_y - 5), Vector2(87, target_y + 5)]), Color("f2d485"))
	if amount > float(game.config.jigger_capacity):
		draw_string(font, Vector2(19, 7), "溢出", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e99b78"))
