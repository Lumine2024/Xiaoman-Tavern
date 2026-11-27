extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func frames() -> void:
	await process_frame
	await process_frame
	await process_frame
func click(button: Control) -> void:
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		button.get_viewport().push_input(event, true)
	await frames()
func capture(label: String) -> void:
	await frames()
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")
func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/opening_delete_cases.json"))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	for key in ["manual_paths", "auto_paths", "profile_path"]: game.interface.slots[key] = fixture[key]
	game.save_slots.settings = game.interface.slots
	game.save_slots.default_path = fixture.legacy_path
	game.config.save_path = fixture.legacy_path
	for path in game.save_slots.paths() + [fixture.profile_path]:
		for suffix in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game.set_process(false)
	for size in fixture.window_sizes:
		root.size = Vector2i(size[0], size[1])
		game.show_start()
		await capture("-title-" + str(size[0]))
		game._begin_new_slot(0)
		check(game.screen == "opening" and not game.playing, "new tutorial starts with reading")
		for index in game.story_catalog.content.opening.pages.size():
			await capture("-opening-" + str(size[0]) + "-" + str(index))
			var box = game.page.get_child(0).get_child(0).get_child(0)
			check(box.get_child(1).text == game.story_catalog.content.opening.pages[index], "opening order matches source")
			await click(box.get_child(2))
		check(game.tutorial_active and game.current_phase == "promotion", "key handoff enters tutorial")
		await capture("-handoff-" + str(size[0]))
		game._open_day()
		game._advance_dialogue(0)
		await frames()
		var target = game.brew.target()
		var stock = game.stock.duplicate(true)
		var ledger = game.stock_ledger.snapshot()
		var rng_state = game.rng.state
		game._toggle_pour(target.name)
		var focus = game.workbench.measure_focus
		await frames()
		check(focus.phase == "reading" and not game.pouring, "first measure waits after camera")
		game._process(float(fixture.wait_seconds))
		check(game.brew.measured == 0 and game.stock == stock and game.stock_ledger.snapshot() == ledger and game.rng.state == rng_state, "reading changes no liquid, costs or RNG")
		await capture("-reading-" + str(size[0]))
		game.pause_menu.open()
		focus.confirm_reading()
		check(not game.pouring, "pause cannot confirm reading")
		game.pause_menu.close()
		await frames()
		await click(focus.read_button)
		check(game.pouring and focus.phase == "pouring", "explicit real click begins pouring")
		game._process(float(target.amount) / game._pour_rate())
		game._stop_pour()
		game._toggle_pour(target.name)
		check(game.pouring, "subsequent measure starts normally")
		game.show_start()
	await frames()
	game.save_slots.complete_tutorial()
	var profile = FileAccess.get_file_as_bytes(fixture.profile_path)
	var path = fixture.manual_paths[0]
	for suffix in ["", ".bak", ".tmp"]:
		var file = FileAccess.open(path + suffix, FileAccess.WRITE)
		file.store_string("invalid save")
		file.close()
	game.pause_menu.open(true)
	game.pause_menu.show_slots("load")
	await capture("-delete-slots")
	var grid = game.pause_menu.content.get_child(1).get_child(0)
	await click(grid.get_child(fixture.auto_paths.size()).get_node("DeleteSlot"))
	var confirm = game.pause_menu.get_node("DeleteSlotConfirm")
	await capture("-delete-confirm")
	confirm.canceled.emit()
	await frames()
	check(game.save_slots.exists(path), "cancel preserves invalid save and backup")
	game.pause_menu._confirm_delete(path, game.interface.slots.slot % 1, "load")
	await frames()
	confirm = game.pause_menu.get_node("DeleteSlotConfirm")
	confirm.confirmed.emit()
	await frames()
	check(not game.save_slots.exists(path) and not FileAccess.file_exists(path + ".tmp"), "confirmation deletes primary backup and temp")
	check(game.save_slots.read(path).is_empty(), "deleted backup cannot resurrect progress")
	check(FileAccess.get_file_as_bytes(fixture.profile_path) == profile, "shared tutorial preserved")
	check(not game.save_slots.delete_slot(fixture.profile_path), "profile path cannot be deleted by slot API")
	game.pause_menu.close()
	game.screen = "game"
	check(not game.save_slots.delete_slot(game.config.save_path), "active run protected outside title")
	for path_key in protected:
		check((not FileAccess.file_exists(path_key)) if protected[path_key] == null else FileAccess.get_file_as_bytes(path_key) == protected[path_key], "user file protected: " + path_key)
	print("OPENING DELETE: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await frames()
	quit(0 if failures == 0 else 1)
