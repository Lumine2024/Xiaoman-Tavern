extends "res://scripts/ui/focus/scene_focus.gd"
## Passive transition: replace drawers while zoomed in, then reveal them on return.
var bench
var activity_tween: Tween

func _ready() -> void:
	bench = get_parent()
	super._ready()

func settings_key() -> String:
	return "straight_focus"

func stop_area_name() -> String:
	return "StraightMixArea"

func active_phase() -> String:
	return "straight"

func manual_stop_enabled() -> bool:
	return false

func activity_hint() -> String:
	return str(settings.hint)

func can_start() -> bool:
	return super.can_start() and game.brew.stage == 2 and game.brew.recipe.method == "直调"

func open() -> void:
	var rect = bench.shaker.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.shaker.size)
	_open_view(rect.grow(float(settings.subject_padding)))

func _start_activity() -> void:
	if game.pause_menu.reduced_motion or float(settings.hold_seconds) <= 0:
		close()
		return
	bench.play_straight_shake(float(settings.hold_seconds))
	activity_tween = create_tween()
	activity_tween.tween_interval(float(settings.hold_seconds))
	activity_tween.tween_callback(close)

func _stop_activity() -> void:
	_cancel_activity()
	if can_start(): game._commit_straight()

func _after_close() -> void:
	game._update_tutorial_hint()

func _cancel_activity() -> void:
	if activity_tween != null: activity_tween.kill()
	if is_instance_valid(bench):
		bench.straight_shake_left = 0.0
		if is_instance_valid(bench.shaker): bench.shaker.get_node("Visual").rotation = 0.0
