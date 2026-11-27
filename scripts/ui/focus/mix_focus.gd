extends "res://scripts/ui/focus/scene_focus.gd"
## Start timing after camera arrival; score the click before zooming back.
var stopped_position = 0.0
func settings_key() -> String:
	return "mix_focus"
func stop_area_name() -> String:
	return "MixStopArea"
func active_phase() -> String:
	return "mixing"
func can_start() -> bool:
	return super.can_start() and game.brew.stage == 2 and game.brew.recipe.method != "直调"
func open() -> void:
	var bench = game.workbench
	var shaker_rect = bench.shaker.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.shaker.size)
	var gauge_rect = bench.gauge.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.gauge.size)
	_open_view(shaker_rect.merge(gauge_rect).grow(float(settings.subject_padding)))
func _start_activity() -> void:
	game.mix_time = 0.0
	game.mix_position = 0.0
	game.mixing = true
	game.workbench.gauge.queue_redraw()
func _stop_activity() -> void:
	stopped_position = game.mix_position
	game.mixing = false
func _after_close() -> void:
	if can_start(): game._complete_mix(stopped_position)
func _cancel_activity() -> void:
	game.mixing = false
