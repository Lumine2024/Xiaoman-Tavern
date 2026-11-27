extends "res://scripts/ui/focus/scene_focus.gd"
## Measure using the existing tabletop cylinder and shared scene camera.
var read_button: Button
func _ready() -> void:
	super._ready()
	read_button = game._button(overlay, game.interface.opening.read_ready, confirm_reading)
	read_button.name = "ConfirmMeasureReading"
	read_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	read_button.offset_left = -180
	read_button.offset_right = 180
	read_button.offset_top = -115
	read_button.offset_bottom = -65
	read_button.hide()

func confirm_reading() -> void:
	if not shown or phase != "reading" or get_tree().paused: return
	game.tutorial_measure_read = true
	read_button.hide()
	phase = active_phase()
	game.pouring = true
	game.workbench.cylinder.update_level()

func settings_key() -> String:
	return "measure_focus"
func stop_area_name() -> String:
	return "PourStopArea"
func active_phase() -> String:
	return "pouring"
func can_start() -> bool:
	return super.can_start() and game.brew.stage < 2
func open() -> void:
	var cylinder = game.workbench.cylinder
	game.workbench.cancel_tilt(cylinder)
	_open_view(cylinder.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, cylinder.size))
func _start_activity() -> void:
	if game.tutorial_active and not game.tutorial_measure_read:
		phase = "reading"
		read_button.show()
		return
	game.pouring = true
	game.workbench.cylinder.update_level()
func _stop_activity() -> void:
	game.pouring = false
	game.workbench.cylinder.update_level()
func _after_close() -> void:
	game.workbench.cylinder.update_level()
func _cancel_activity() -> void:
	game.pouring = false
	if is_instance_valid(read_button): read_button.hide()
