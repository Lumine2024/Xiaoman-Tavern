extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func click(button: Control) -> void:
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await process_frame
	await process_frame

func key(code: int) -> void:
	for down in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame

func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")

func slot_button(index: int) -> Button:
	return game.pause_menu.content.get_child(1).get_child(0).get_child(index + fixture.auto_paths.size())

func finish_opening() -> void:
	while game.screen == "opening":
		await click(game.page.get_child(0).get_child(0).get_child(0).get_child(2))

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/co_work_revision_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	var originals = {}
	for path in game.save_slots.paths() + [game.save_slots.settings.profile_path]:
		for suffix in ["", ".bak"]:
			originals[path + suffix] = FileAccess.get_file_as_string(path + suffix) if FileAccess.file_exists(path + suffix) else null
	for name in ["manual_paths", "auto_paths", "profile_path"]:
		game.interface.slots[name] = fixture[name]
	game.save_slots.settings = game.interface.slots
	game.save_slots.default_path = fixture.legacy_path
	game.config.save_path = fixture.legacy_path
	game.pause_menu.reduced_motion = false
	for path in game.save_slots.paths() + [fixture.profile_path]:
		for suffix in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	game.show_start()
	await process_frame
	await click(game.page.get_child(0).get_node("TitleActions").get_child(0))
	check(paused and game.pause_menu.view == "new", "start button opens new slot selector")
	await capture("-new-slots")
	await click(slot_button(0))
	await finish_opening()
	check(game.tutorial_active and game.progress.cycle == 1 and game.config.save_path == fixture.manual_paths[0], "empty slot starts fresh tutorial")
	var first_slot = FileAccess.get_file_as_string(fixture.manual_paths[0])
	game.show_start()
	await process_frame
	await click(game.page.get_child(0).get_node("TitleActions").get_child(0))
	check(game.pause_menu.view == "new", "start does not resume existing run")
	await click(slot_button(1))
	await finish_opening()
	check(game.tutorial_active and game.day == 1 and game.config.save_path == fixture.manual_paths[1], "second slot owns independent first cycle")
	check(FileAccess.get_file_as_string(fixture.manual_paths[0]) == first_slot, "new game preserves prior slot")
	game.set_process(false)
	game.bar_ui.measure_focus.zoom_in_seconds = 0
	game.bar_ui.measure_focus.zoom_out_seconds = 0
	game._open_day()
	while game.guest_index < game.queue.size():
		game._settle(true)
		game._next_guest()
	game._buy_stock(game._find_recipe(game.tutorial.promotion_id).ingredients[0].name)
	await process_frame
	check(game.tutorial_director.step == "explore_shop" and not game.tutorial_director.veil.visible, "tutorial shop is unlocked after replenishment")
	check(game.tutorial_hint.text.contains(fixture.handoff_phrase), "tutorial explains transition to peer competition")
	await capture("-shop-exploration")
	game._finish_tutorial()
	check(game.save_slots.profile_state().tutorial_completed and FileAccess.file_exists(fixture.profile_path), "tutorial completion shared durably")
	var second_slot = FileAccess.get_file_as_string(fixture.manual_paths[1])
	game.show_start()
	await process_frame
	await click(game.page.get_child(0).get_node("TitleActions").get_child(0))
	await click(slot_button(2))
	check(not game.tutorial_active and game.screen == "selection" and game.progress.cycle == 2, "new slot skips already completed onboarding")
	game._begin_rival_run(game.config.companions[int(fixture.companion_index)], fixture.rival_id)
	game.money = int(fixture.modified_money)
	game._save(game.current_phase)
	check(FileAccess.get_file_as_string(fixture.manual_paths[1]) == second_slot, "new run does not alter other cycle")
	var third = game.save_slots.read(fixture.manual_paths[2])
	check(third.file_info.saved_at > 0 and third.file_info.slot == 2, "save metadata includes timestamp and slot")
	check(game.save_slots.describe(third).contains(str(int(fixture.modified_money))), "slot summary shows actual money")
	check(fixture.auto_paths.all(func(path): return not game.save_slots.read(path).is_empty()), "both rolling autosaves are readable")
	await key(KEY_ESCAPE)
	game.pause_menu.show_slots("load")
	await capture("-load-slots")
	await click(slot_button(1))
	check(game.progress.cycle == 2 and game.money != int(fixture.modified_money), "loading another slot restores its independent money and cycle")
	check(game._load_game(fixture.manual_paths[2]) and game.money == int(fixture.modified_money), "return to third slot preserves its progress")
	game.pause_menu.open()
	game.pause_menu.show_slots("save")
	await click(slot_button(3))
	check(game.config.save_path == fixture.manual_paths[3] and game.save_slots.read(fixture.manual_paths[3]).run.money == int(fixture.modified_money), "save as copies into selected empty slot")
	game.pause_menu.show_slots("new")
	await click(slot_button(2))
	var confirm: ConfirmationDialog
	for child in game.pause_menu.get_children():
		if child is ConfirmationDialog: confirm = child
	check(is_instance_valid(confirm), "occupied slot asks before replacing")
	confirm.get_cancel_button().pressed.emit()
	await process_frame
	check(game.save_slots.read(fixture.manual_paths[2]).run.money == int(fixture.modified_money), "cancel overwrite preserves existing slot")
	game.pause_menu.close()
	# Reopening an unfinished tutorial after global completion advances only that slot.
	check(game._load_game(fixture.manual_paths[0]) and not game.tutorial_active and game.progress.cycle == 2, "shared completion suppresses old unfinished tutorials")
	game._begin_rival_run(game.config.companions[int(fixture.companion_index)], fixture.rival_id, true)
	game._select_counter_card("follow")
	game.promotion = game._find_recipe(fixture.recipe_id)
	game._open_day(true)
	game.queue[0].recipe_id = fixture.recipe_id
	game._start_guest()
	game._advance_dialogue(0)
	await key(KEY_TAB)
	check(paused and game.pause_menu.view == "journal", "Tab opens and pauses handbook")
	check(game.pause_menu._journal_text().contains(game.companion.name) and game.pause_menu._journal_text().contains(game.competition.rival().name), "handbook includes companion and rival")
	await capture("-journal")
	await key(KEY_TAB)
	check(not paused and not game.pause_menu.opened, "Tab closes handbook without gameplay input")
	var bench = game.workbench
	await process_frame
	var board = Rect2(bench.table.position, bench.table.size)
	check(board.encloses(bench.bell.get_rect()), "bell rests inside counter bounds")
	var target = game.brew.target()
	game._toggle_pour(target.name)
	game._process(float(target.amount) / game._pour_rate())
	game._stop_pour()
	game._transfer()
	await create_timer(float(fixture.pause_seconds)).timeout
	check(absf(bench.cylinder.tilt_degrees) > 0, "transfer visibly tilts cylinder")
	await key(KEY_ESCAPE)
	var angle = bench.cylinder.tilt_degrees
	await create_timer(float(fixture.pause_seconds), true).timeout
	check(is_equal_approx(angle, bench.cylinder.tilt_degrees), "pause freezes tilt tween")
	await key(KEY_ESCAPE)
	await create_timer(float(game.bar_ui.animation.tilt_seconds) * 2).timeout
	check(is_zero_approx(bench.cylinder.tilt_degrees), "tilt restores original orientation")
	while game.brew.stage < 2:
		target = game.brew.target()
		game._toggle_pour(target.name)
		game._process(float(target.amount) / game._pour_rate())
		game._stop_pour()
		game._transfer()
	for item in game.brew.recipe.pre_solids: game._add_pre_solid(item.name)
	game._advance_dialogue(int(game.guest.good_answer))
	game._toggle_mix()
	while bench.mix_focus.phase == "zoom_in": await process_frame
	await create_timer(float(fixture.pause_seconds)).timeout
	check(absf(bench.shaker.get_node("Visual").rotation) > 0, "active mixing visibly shakes vessel")
	await capture("-shake")
	bench.mix_focus.close()
	while bench.mix_focus.phase == "zoom_out": await process_frame
	game._select_cup(game.brew.recipe.cup)
	game._select_ice(game.brew.expected_ice())
	game._pour_into_glass()
	check(bench.glass.has_node("DrinkLiquid") and bench.selection_label.text.contains(fixture.filled_label), "finished drink has visible liquid and status")
	await create_timer(float(game.bar_ui.animation.tilt_seconds) * 2).timeout
	await capture("-filled-glass")
	for window in fixture.window_sizes:
		root.size = Vector2i(window[0], window[1])
		await process_frame
		await process_frame
		check(game.get_global_rect().encloses(game.page.get_global_rect()), "effects header and bar fit viewport")
	var malformed = third.duplicate(true)
	malformed.file_info = fixture.invalid_metadata
	check(game.save_schema.decode(malformed).is_empty(), "invalid slot metadata is rejected")
	malformed = third.duplicate(true)
	malformed.file_info.slot = fixture.manual_paths.size()
	check(game.save_schema.decode(malformed).is_empty(), "out-of-range slot metadata is rejected")
	for path in originals:
		check((not FileAccess.file_exists(path)) if originals[path] == null else FileAccess.get_file_as_string(path) == originals[path], "real user data unchanged: " + path)
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	for path in fixture.manual_paths + fixture.auto_paths + [fixture.profile_path, fixture.legacy_path]:
		for suffix in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("CO-WORK REVISION: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
