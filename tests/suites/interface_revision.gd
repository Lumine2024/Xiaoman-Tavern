extends SceneTree
var game
var fixture: Dictionary
var failures = 0
var checks = 0
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func escape() -> void:
	for down in [true, false]:
		var key = InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = down
		root.push_input(key, true)

func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/interface_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	var real_path = game.config.save_path
	var existed = FileAccess.file_exists(real_path)
	var original = FileAccess.get_file_as_string(real_path) if existed else ""
	game.config.save_path = fixture.save_path
	game.pause_menu.settings.settings_path = fixture.settings_path
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.show_start()
	await capture("-title")
	check(game.page.get_child_count() == 1, "title has only name and action layout")
	game._begin_tutorial()
	check(game.progress.cycle == 1 and game.tutorial_active and game._has_save(), "no save starts first cycle tutorial in normal slot")
	game.show_start()
	game._load_game()
	check(game.progress.cycle == 1 and game.tutorial_active, "unfinished tutorial resumes")
	game._open_day()
	game._advance_dialogue(0)
	var liquid = game.brew.target().name
	game._toggle_pour(liquid)
	var focus = game.workbench.measure_focus
	# Esc must pause even during the camera tween, without completing the pour.
	escape()
	check(paused and game.pause_menu.opened, "Esc opens menu during zoom")
	var transform = root.canvas_transform
	await create_timer(float(fixture.pause_seconds), true).timeout
	check(root.canvas_transform.is_equal_approx(transform) and game.brew.measured == 0, "pause freezes zoom and liquid")
	await capture("-menu")
	escape()
	check(not paused and not game.pause_menu.opened, "Esc resumes")
	while focus.phase == "zoom_in": await process_frame
	if focus.phase == "reading": focus.confirm_reading()
	await create_timer(float(fixture.partial_pour_seconds)).timeout
	check(game.brew.measured > 0, "resumed zoom starts real pour")
	var stock_partial = game.stock[liquid]
	var measured = game.brew.measured
	escape()
	await create_timer(float(fixture.pause_seconds), true).timeout
	check(game.brew.measured == measured and game.stock[liquid] == stock_partial, "pause freezes active pour and inventory")
	check(game._save_manual(), "manual save in focus succeeds")
	var saved = game.save_store.load_snapshot(fixture.save_path, game.save_schema.decode)
	check(saved.run.stock[liquid] > stock_partial, "manual save preserves order-start stock")
	game.pause_menu.close()
	check(game._load_game() and game.brew.measured == 0 and game.stock[liquid] == saved.run.stock[liquid], "load restores order start without double consuming")
	# Current schema rejects obsolete documents.
	var legacy = game._snapshot("reception")
	legacy.version = 5
	legacy.run.tutorial = false
	var migrated = game.save_schema.decode(legacy)
	check(migrated.is_empty(), "obsolete document is not migrated")
	var broken = game._snapshot("reception")
	broken.run.tutorial = false
	check(game.save_schema.decode(broken).is_empty(), "v6 rejects cycle and tutorial mismatch")
	# Build the actual shop state through valid settlements; full successful tutorial is covered separately.
	game.set_process(false)
	while game.guest_index < game.queue.size():
		game._settle(true)
		game._next_guest()
	await capture("-shop")
	var shop = game.page.get_node("ShopShelves")
	var collected: Array = []
	for index in int(fixture.shop_page_count):
		shop.page_index = index
		shop._render()
		await process_frame
		for card in shop.catalog.get_child(1).get_child(0).get_children():
			collected.append(card.get_child(0).get_child(1).text)
	check(collected.size() == game.stock.size() and collected.all(func(name): return name in game.stock), "shop pagination covers all ingredients")
	for window_size in fixture.window_sizes:
		root.size = Vector2i(window_size[0], window_size[1])
		await process_frame
		await process_frame
		check(game.get_global_rect().encloses(game.page.get_global_rect()), "shop page fits window")
	var before_finish = game._snapshot("shop")
	game.config.save_path = fixture.blocked_save_path
	game._finish_tutorial()
	check(not game.last_save_ok and game._snapshot("shop") == before_finish, "failed second-cycle save restores tutorial and economy")
	game.config.save_path = fixture.save_path
	if is_instance_valid(game.storage_dialog): game.storage_dialog.queue_free()
	await process_frame
	game._finish_tutorial()
	check(game.progress.cycle == 2 and not game.tutorial_active and game.screen == "selection", "completion starts second cycle selection")
	await capture("-selection")
	game.show_start()
	game._load_game()
	check(game.progress.cycle == 2 and not game.tutorial_active and game.screen == "selection", "reentry does not repeat onboarding")
	game._begin_rival_run(game.config.companions[0], game.competition.data.rivals.keys()[0])
	check(game.progress.cycle == 2 and not game.tutorial_active, "rival confirmation keeps second cycle")
	game.pause_menu.open()
	game.pause_menu.show_settings()
	await capture("-settings")
	game.pause_menu.reduced_motion = true
	game.pause_menu._store_settings()
	var config = ConfigFile.new()
	check(config.load(fixture.settings_path) == OK and config.get_value("display", "reduced_motion") == true, "settings persist separately")
	game.pause_menu.close()
	game._show_rival_selection(game.companion)
	game.page.get_child(0)._activate()
	await process_frame
	await process_frame
	check(game.page.get_child(0).settled, "reduced motion completes spin without travel")
	check(FileAccess.file_exists(real_path) == existed and (not existed or FileAccess.get_file_as_string(real_path) == original), "real user save remains untouched")
	game.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.settings_path))
	print("INTERFACE REVISION: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
