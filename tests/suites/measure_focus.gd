extends SceneTree
var checks = 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func wait_view(focus) -> void:
	while focus.phase in ["zoom_in", "zoom_out"]:
		await process_frame
func capture(path: String) -> void:
	await process_frame
	await process_frame
	if not path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func click_stop(focus, fraction: Array) -> void:
	var point = focus.overlay.size * Vector2(fraction[0], fraction[1])
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/measure_focus_cases.json"))
	var args = OS.get_cmdline_user_args()
	var output = "" if args.is_empty() else args[0].get_basename()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path = fixture.save_path
	game._choose_companion(game.config.companions[0])
	game._open_day()
	game.set_process(false)
	var selected: Dictionary = {}
	var smallest = INF
	for recipe in game.recipes:
		for item in recipe.ingredients:
			if float(item.amount) < smallest:
				smallest = float(item.amount)
				selected = recipe
	game.queue[0] = {"recipe_id":selected.id, "customer_index":0}
	game._start_guest()
	game._advance_dialogue(0)
	while not is_equal_approx(float(game.brew.target().amount), smallest):
		var item = game.brew.target()
		game._toggle_pour(item.name)
		await wait_view(game.workbench.measure_focus)
		game._process(float(item.amount) / game._pour_rate())
		game._stop_pour()
		await wait_view(game.workbench.measure_focus)
		game._transfer()
	var bench = game.workbench
	var focus = bench.measure_focus
	await process_frame
	await process_frame
	var original = root.canvas_transform
	var target = game.brew.target()
	var stock_before = float(game.stock[target.name])
	var base_rect = bench.cylinder.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.cylinder.size)
	game._toggle_pour(target.name)
	check(focus.phase == "zoom_in" and not game.pouring, "click starts camera before pouring")
	game._process(float(fixture.pause_seconds))
	check(game.brew.measured == 0 and game.stock[target.name] == stock_before, "no liquid or cost during zoom-in")
	await wait_view(focus)
	check(game.pouring and focus.phase == "pouring", "zoom finishes before liquid starts")
	var enlarged = bench.cylinder.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bench.cylinder.size)
	check(enlarged.size.y > base_rect.size.y * float(fixture.minimum_gain), "real tabletop cylinder is enlarged")
	check(enlarged.position.y >= 0 and enlarged.end.y <= root.get_visible_rect().size.y, "zoomed cylinder fits screen")
	check(not focus.overlay.find_children("*", "Panel", true, false).size(), "no popup panel or duplicate cylinder")
	game._process(smallest * float(fixture.half_fraction) / game._pour_rate())
	await capture(output + "-small.png" if not output.is_empty() else "")
	click_stop(focus, fixture.stop_point)
	check(not game.pouring and focus.phase == "zoom_out", "pointer stops liquid immediately then zooms out")
	var stopped = float(game.brew.measured)
	var stopped_stock = float(game.stock[target.name])
	game._process(float(fixture.pause_seconds))
	check(game.brew.measured == stopped and game.stock[target.name] == stopped_stock, "no continued pouring during zoom-out")
	await wait_view(focus)
	check(not focus.shown and root.canvas_transform.is_equal_approx(original), "camera returns to exact original transform")
	check(game.page.find_child("SpeechBubble", true, false).modulate.a == 1.0, "scene interface returns to original opacity")
	await capture(output + "-returned.png" if not output.is_empty() else "")
	game._toggle_pour(target.name)
	await wait_view(focus)
	game._process((smallest * float(fixture.over_fraction) - stopped) / game._pour_rate())
	check(game.pouring and game.brew.measured > smallest, "no auto-stop or clamping at target")
	await capture(output + "-over.png" if not output.is_empty() else "")
	var space = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space, true)
	check(not game.pouring and focus.phase == "zoom_out", "space also stops and zooms out")
	await wait_view(focus)
	var actual = game.brew.measured
	game._transfer()
	check(is_equal_approx(game.brew.quantities.back().amount, actual), "manual transfer preserves actual dose")
	check(game.brew.errors > 0, "overshoot retains scoring consequence")
	game._start_guest()
	game._advance_dialogue(0)
	focus = game.workbench.measure_focus
	game._toggle_pour(game.brew.target().name)
	await wait_view(focus)
	game.remaining = 0
	game._process(0)
	await process_frame
	check(not game.playing and root.canvas_transform.is_equal_approx(original), "timeout restores camera and removes pouring view")
	game._start_guest()
	game._toggle_pour(game.brew.target().name)
	game.remaining = 0
	game._process(0)
	await process_frame
	check(root.canvas_transform.is_equal_approx(original), "timeout during zoom-in cancels pending pour")
	game._start_guest()
	game._toggle_pour(game.brew.target().name)
	game.show_start()
	await process_frame
	check(root.canvas_transform.is_equal_approx(original), "leaving during zoom cancels tween and restores scene")
	for size in fixture.resize_sizes:
		root.size = Vector2i(size[0], size[1])
		game._choose_companion(game.config.companions[0])
		game._open_day()
		await process_frame
		await process_frame
		focus = game.workbench.measure_focus
		game._toggle_pour(game.brew.target().name)
		await wait_view(focus)
		var rect = game.workbench.cylinder.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, game.workbench.cylinder.size)
		check(root.get_visible_rect().encloses(rect), "cylinder fits resized viewport " + str(size))
		focus.close()
		await wait_view(focus)
		check(root.canvas_transform.is_equal_approx(original), "resized view restores transform")
	game.queue_free()
	await process_frame
	print("MEASURE CAMERA: %d checks; %d failures; real scene zoom, ordered pouring, stop, restore, timeout, resize" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
