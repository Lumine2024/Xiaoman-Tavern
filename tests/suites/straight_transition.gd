extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""
var direct: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func key(code: int) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame

func capture(suffix: String) -> void:
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+suffix+".png")

func prepare() -> void:
	game._choose_companion(game.config.companions[0])
	game._open_day()
	game.queue[0] = {"recipe_id": direct.id, "customer_index": int(fixture.customer_index)}
	game._start_guest()
	game._advance_dialogue(0)
	while game.brew.stage < 2:
		var item = game.brew.target()
		game._toggle_pour(item.name)
		game._process(float(item.amount)/game._pour_rate())
		game._stop_pour()
		game._transfer()
	game._advance_dialogue(int(game.guest.good_answer))

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/straight_transition_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	var user_path = game.config.save_path
	var original = FileAccess.get_file_as_string(user_path) if FileAccess.file_exists(user_path) else null
	game.config.save_path = fixture.save_path
	game.pause_menu.reduced_motion = false
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	game.bar_ui.measure_focus.merge(fast,true)
	game.set_process(false)
	direct = game.recipes.filter(func(recipe): return recipe.method == "直调")[0]
	prepare()
	await process_frame
	await process_frame
	var original_transform = root.canvas_transform
	var bench = game.workbench
	var focus = bench.straight_focus
	game._finish_straight()
	check(focus.phase == "zoom_in" and bench.straight_shake_left == 0, "straight zooms before shaking")
	check(game.brew.stage == 2 and bench.drawer_buttons.get_child_count() == 2, "two drawers retained during approach")
	var tween_before = focus.tween
	game._finish_straight()
	check(focus.tween == tween_before, "repeated input cannot restart transition")
	while focus.phase == "zoom_in": await process_frame
	check(focus.phase == "straight" and bench.straight_shake_left > 0, "shake begins after camera arrives")
	check(not bench.gauge.visible and not game.mixing, "no judgement bar or timing challenge")
	check(root.canvas_transform.get_scale().x > original_transform.get_scale().x, "original scene is magnified")
	await create_timer(float(fixture.sample_seconds)).timeout
	check(absf(bench.shaker.get_node("Visual").rotation) > 0, "shaker moves in closeup")
	await capture("-straight-closeup")
	await key(KEY_ESCAPE)
	var left = bench.straight_shake_left
	var transform = root.canvas_transform
	await create_timer(float(fixture.sample_seconds),true).timeout
	check(paused and left == bench.straight_shake_left and transform.is_equal_approx(root.canvas_transform), "Esc freezes shake and camera")
	await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	check(game.brew.stage == 2, "space does not skip passive shake")
	while focus.phase == "straight": await process_frame
	check(focus.phase == "zoom_out" and game.brew.stage == 3 and bench.drawer_buttons.get_child_count() == 3, "drawers switch while zoomed so return reveals the new set")
	while focus.shown: await process_frame
	check(game.brew.stage == 3 and bench.drawer_buttons.get_child_count() == 3, "return reveals three vessel drawers")
	check(root.canvas_transform.is_equal_approx(original_transform), "straight restores original camera exactly")
	await capture("-three-drawers")
	prepare()
	game._finish_straight()
	while game.workbench.straight_focus.phase == "zoom_in": await process_frame
	game.show_start()
	await create_timer(float(game.bar_ui.straight_focus.hold_seconds)).timeout
	check(game.screen == "title" and game.brew.stage == 2 and root.canvas_transform.is_equal_approx(original_transform), "leaving cancels delayed completion and restores camera")
	prepare()
	game._finish_straight()
	game.remaining = 0
	game._process(0)
	check(not game.workbench.straight_focus.shown and root.canvas_transform.is_equal_approx(original_transform), "timeout cancels straight approach")
	prepare()
	game.pause_menu.reduced_motion = true
	game._finish_straight()
	check(game.brew.stage == 3 and not game.workbench.straight_focus.shown, "reduced motion skips automatic visual transition")
	game._select_cup(game.brew.recipe.cup)
	game._select_ice(game.brew.expected_ice())
	game._pour_into_glass()
	while game.brew.stage == 3: game._topup()
	game._advance_dialogue(0)
	game._special(true)
	for item in game.brew.expected_garnishes(): game._garnish(item)
	game.pause_menu.reduced_motion = false
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/bar_ui.json")).transitions,true)
	await process_frame
	game._serve()
	check(game.scene_transition.busy and game.scene_transition.last_mode == "zoom_in", "serving opens result with a scene zoom")
	await process_frame
	await process_frame
	check(not root.canvas_transform.is_equal_approx(original_transform), "result canvas starts scaled")
	await key(KEY_ESCAPE)
	var result_transform = root.canvas_transform
	await create_timer(float(fixture.sample_seconds),true).timeout
	check(paused and root.canvas_transform.is_equal_approx(result_transform), "pause freezes result zoom")
	await key(KEY_ESCAPE)
	check(game.scene_transition.last_mode == "zoom_in", "resume preserves the interrupted zoom")
	await create_timer(float(fixture.sample_seconds)).timeout
	await capture("-result-zoom")
	while game.scene_transition.busy: await process_frame
	check(root.canvas_transform.is_equal_approx(original_transform), "result zoom restores transform after settling")
	await capture("-result")
	game._next_guest()
	var patience = game.remaining
	check(game.scene_transition.last_mode == "zoom_out" and game.scene_transition.busy, "next guest returns with zoom-out")
	game._process(float(fixture.sample_seconds))
	check(game.remaining == patience, "arrival transition does not consume customer time")
	await capture("-next-guest-zoom")
	while game.scene_transition.busy: await process_frame
	check(root.canvas_transform.is_equal_approx(original_transform), "next guest returns to exact scene scale")
	game.show_start()
	check(game.scene_transition.last_mode == "fade" and game.scene_transition.busy, "other full pages fade through black")
	await key(KEY_ESCAPE)
	check(not game.pause_menu.opened, "title fade cannot open an unsaveable in-game menu")
	await create_timer(float(game.bar_ui.transitions.fade_out_seconds)*.5).timeout
	check(game.scene_transition.outgoing.modulate.a < 1 and game.scene_transition.black.modulate.a == 1, "outgoing frame gradually darkens")
	await capture("-fade")
	while game.scene_transition.busy: await process_frame
	game.pause_menu.open(true)
	game.pause_menu.show_slots("load")
	check(game.pause_menu.page_transition.busy, "menu subpages also use black fade")
	while game.pause_menu.page_transition.busy: await process_frame
	check(paused, "menu fade continues while gameplay remains paused")
	game.pause_menu.close()
	check((not FileAccess.file_exists(user_path)) if original == null else FileAccess.get_file_as_string(user_path) == original, "real player save unchanged")
	game.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path+suffix))
	print("STRAIGHT AND SCENE TRANSITIONS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
