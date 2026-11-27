extends SceneTree
var failures = 0
var checks = 0
var game
var output = ""
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(button: Button) -> void:
	button.grab_focus()
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await process_frame
func capture(suffix: String) -> void:
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")
func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/character_selection_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	var user_path = game.config.save_path
	var original_exists = FileAccess.file_exists(user_path)
	var original = FileAccess.get_file_as_string(user_path) if original_exists else ""
	game.config.save_path = fixture.save_path
	game._choose_companion(game.config.companions[0])
	game._show_companion_selection()
	await process_frame
	var selector = game.page.get_child(0)
	check(selector.entries.size() == int(fixture.companion_count), "only authored companions")
	check(selector.seats.size() == int(fixture.companion_slots), "five companion seats")
	for i in range(int(fixture.companion_count), int(fixture.companion_slots)):
		check(selector.seats[i].disabled, "empty seat disabled")
	await click(selector.seats[int(fixture.chosen_companion)])
	check(selector.selected == int(fixture.chosen_companion), "mouse selects companion")
	await create_timer(float(selector.settings.select_seconds) + .1).timeout
	await capture("-companion")
	for window_size in fixture.window_sizes:
		root.size = Vector2i(window_size[0], window_size[1])
		await process_frame
		await process_frame
		check(selector.action.get_global_rect().end.y <= root.get_visible_rect().end.y, "confirm fits window")
		check(selector.effect.get_rect().end.x <= selector.size.x, "description fits window")
	root.size = Vector2i(fixture.window_sizes[0][0], fixture.window_sizes[0][1])
	game._show_rival_selection(game.config.companions[int(fixture.chosen_companion)])
	await process_frame
	selector = game.page.get_child(0)
	check(selector.entries.size() == int(fixture.slot_count), "six rivals")
	for seat in selector.seats: check(seat.disabled, "rivals cannot be selected")
	selector.random.seed = int(fixture.random_seed)
	var reference = RandomNumberGenerator.new()
	reference.seed = int(fixture.random_seed)
	var expected = reference.randi_range(0, selector.entries.size()-1)
	await click(selector.action)
	check(selector.rolling and selector.action.disabled, "roll locks confirm")
	check(selector.selected == expected, "uniform draw uses a single random sample")
	selector._activate()
	check(selector.selected == expected, "repeated roll ignored")
	var before = selector.reel_position
	await create_timer(.3).timeout
	check(selector.reel_position > before, "reel advances during animation")
	await capture("-rolling")
	while selector.rolling: await process_frame
	check(selector.settled and not selector.action.disabled, "settled enables confirmation")
	check(is_equal_approx(selector.reel_position, float(expected)), "reel aligned to sampled rival")
	check(selector.name_label.text == selector.entries[expected].name, "description matches reel")
	await capture("-settled")
	var expected_id = selector.entries[expected].id
	await click(selector.action)
	check(game.competition.state.rival == expected_id, "confirmed rival reaches game state")
	check(not game.page.get_child(0).rival_mode and game.current_phase == "selection", "rival confirmation opens companion choice")
	selector = game.page.get_child(0)
	selector.select(int(fixture.chosen_companion))
	await create_timer(float(selector.settings.select_seconds) + .1).timeout
	await click(selector.action)
	check(game.companion.id == game.config.companions[int(fixture.chosen_companion)].id and game.current_phase == "preparation", "companion confirmation opens D0 purchasing")
	check(FileAccess.file_exists(user_path) == original_exists, "user save existence unchanged")
	check(not original_exists or FileAccess.get_file_as_string(user_path) == original, "user save content unchanged")
	print("CHARACTER SELECTION: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
