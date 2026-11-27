extends SceneTree
var checks = 0
var failures: Array = []
var game
var output = ""
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func wait_view(focus) -> void:
	while focus.phase in ["zoom_in", "zoom_out"]: await process_frame
func click(fraction: Array) -> void:
	var point = root.get_visible_rect().size * Vector2(fraction[0], fraction[1])
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
func capture(suffix: String) -> void:
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")
func prepare(recipe: Dictionary) -> void:
	game._initialize_stock()
	game.guest_index = 0
	game.day_served = 0
	game.day_success = 0
	game.queue[0] = {"recipe_id": recipe.id, "customer_index": 0}
	game._start_guest()
	game._advance_dialogue(0)
	while game.brew.stage < 2:
		var item = game.brew.target()
		game._toggle_pour(item.name)
		game._process(float(item.amount) / game._pour_rate())
		game._stop_pour()
		game._transfer()
	for item in recipe.pre_solids: game._add_pre_solid(item.name)
	game._advance_dialogue(int(game.guest.good_answer))
func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mix_focus_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	var user_path = game.config.save_path
	var user_exists = FileAccess.file_exists(user_path)
	var user_before = FileAccess.get_file_as_string(user_path) if user_exists else ""
	game.config.save_path = fixture.save_path
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game._choose_companion(game.config.companions[0])
	game._open_day()
	var original = root.canvas_transform
	for method in fixture.methods:
		var candidates = game.recipes.filter(func(recipe): return recipe.method == method)
		check(not candidates.is_empty(), "authored method exists: " + method)
		if candidates.is_empty(): continue
		prepare(candidates[0])
		await process_frame
		await process_frame
		var bench = game.workbench
		var focus = bench.mix_focus
		var before = bench.shaker.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.shaker.size)
		bench.shaker.pressed.emit()
		check(focus.phase == "zoom_in" and not game.mixing, method + " zoom before judgement")
		var clock = game.mix_time
		game._process(float(game.bar_ui.mix_focus.zoom_in_seconds))
		check(game.mix_time == clock and game.brew.stage == 2, "pointer does not run during zoom")
		click(fixture.click_point)
		check(focus.phase == "zoom_in", "early click cannot score or skip zoom")
		await wait_view(focus)
		check(game.mixing and focus.phase == "mixing" and game.mix_time == 0, method + " starts after camera arrival")
		var esc = InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		root.push_input(esc, true)
		check(paused and game.pause_menu.opened, method + " Esc pauses active judgement")
		var position_before = game.mix_position
		game._process(float(game.config.mix_cycle_seconds))
		check(game.mix_position == position_before and focus.phase == "mixing", "pause does not score or advance pointer")
		root.push_input(esc, true)
		check(not paused and game.mixing, "Esc resumes original judgement")
		var shaker = bench.shaker.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.shaker.size)
		var gauge = bench.gauge.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.gauge.size)
		check(shaker.size.y > before.size.y * float(fixture.minimum_gain), "real shaker magnified")
		check(root.get_visible_rect().encloses(shaker) and root.get_visible_rect().encloses(gauge), "shaker and full gauge both fit")
		var multiplier = float(game.config.long_mix_multiplier) if method in ["滚摇", "长摇"] else 1.0
		game._process(float(game.config.mix_target) * float(game.config.mix_cycle_seconds) * multiplier)
		await capture("-" + method)
		var selected = game.mix_position
		click(fixture.click_point)
		check(not game.mixing and focus.phase == "zoom_out", "click freezes pointer immediately")
		game._process(float(game.bar_ui.mix_focus.zoom_out_seconds))
		check(game.mix_position == selected and game.brew.stage == 2, "frozen judgement during return")
		await wait_view(focus)
		check(game.brew.stage == 3 and game.brew.mix_perfect, method + " scores original target click after return")
		check(root.canvas_transform.is_equal_approx(original), "exact camera restoration")
		await capture("-" + method + "-returned")
	var timed = game.recipes.filter(func(recipe): return recipe.method == fixture.methods[0])[0]
	prepare(timed)
	game._toggle_mix()
	await wait_view(game.workbench.mix_focus)
	game.mix_position = float(fixture.miss_position)
	var key = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key, true)
	await wait_view(game.workbench.mix_focus)
	check(game.brew.errors > 0 and not game.brew.mix_perfect, "missed judgement remains an error; space stops")
	prepare(timed)
	game._toggle_mix()
	game.remaining = 0
	game._process(0)
	await process_frame
	check(root.canvas_transform.is_equal_approx(original) and not game.mixing, "timeout during zoom cancels pending judgement")
	prepare(timed)
	game._toggle_mix()
	await wait_view(game.workbench.mix_focus)
	game.show_start()
	await process_frame
	check(root.canvas_transform.is_equal_approx(original) and not game.mixing, "leaving active judgement restores camera")
	for size in fixture.resize_sizes:
		root.size = Vector2i(size[0], size[1])
		game._choose_companion(game.config.companions[0])
		game._open_day()
		prepare(timed)
		await process_frame
		await process_frame
		game._toggle_mix()
		await wait_view(game.workbench.mix_focus)
		for control in [game.workbench.shaker, game.workbench.gauge]:
			check(root.get_visible_rect().encloses(control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)), "subjects fit resized viewport")
		game.workbench.mix_focus.dismiss()
	var direct = game.recipes.filter(func(recipe): return recipe.method == "直调")[0]
	prepare(direct)
	game.workbench.shaker.pressed.emit()
	check(game.workbench.straight_focus.shown and not game.workbench.mix_focus.shown, "straight drinks use passive camera without judgement")
	while game.workbench.straight_focus.shown: await process_frame
	check(game.brew.stage == 3, "straight camera returns before vessel stage")
	check(FileAccess.file_exists(user_path) == user_exists and (not user_exists or FileAccess.get_file_as_string(user_path) == user_before), "user save unchanged")
	print("MIX CAMERA: %d checks; %d failures; four timing methods, scoring, zoom, cancellation, resize" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
