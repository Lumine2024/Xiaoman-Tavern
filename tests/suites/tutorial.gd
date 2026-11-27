extends SceneTree
var failures: Array = []
var checks = 0
var game
var output = ""
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	check(game.get_global_rect().encloses(game.page.get_global_rect()), "tutorial page fits viewport")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tutorial_cases.json"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.mix_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.straight_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	game.config.save_path = fixture.normal_save_path
	game._choose_companion(game.config.companions[0])
	var normal = FileAccess.get_file_as_string(fixture.normal_save_path)
	var previous_seed = game.rng.seed
	game._restart_cycle()
	check(game.rng.seed != previous_seed, "normal run reseeds on restart")
	normal = FileAccess.get_file_as_string(fixture.normal_save_path)
	game._begin_tutorial()
	check(str(game.rng.seed) == game.tutorial.seed, "tutorial fixed seed")
	await capture("-promotion")
	game._open_day()
	var first_queue = game.queue.duplicate(true)
	check(first_queue.size() == fixture.expected_orders.size(), "observed tutorial guest count")
	for index in range(mini(first_queue.size(), fixture.expected_orders.size())):
		check(first_queue[index].customer_index == fixture.expected_orders[index].customer_index and first_queue[index].recipe_id == fixture.expected_orders[index].recipe_id, "observed order " + str(index))
	print("TUTORIAL QUEUE: ", JSON.stringify(first_queue))
	var saved = game._snapshot("reception")
	game._save("reception")
	var draws: Array = []
	for index in range(int(fixture.draw_count)): draws.append(game.rng.randi())
	check(game._load_game(fixture.normal_save_path), "tutorial reload")
	check(game.remaining == saved.run.queue[0].patience, "patience preserved")
	for draw in draws: check(game.rng.randi() == draw, "next RNG result identical after JSON save/load")
	for invalid in fixture.invalid_rng:
		var broken = saved.duplicate(true)
		broken.run.rng.state = invalid
		check(game.save_schema.decode(broken).is_empty(), "reject invalid RNG state " + invalid)
	var legacy = saved.duplicate(true)
	legacy.version = 4
	legacy.run.erase("rng")
	legacy.run.erase("tutorial")
	check(game.save_schema.decode(legacy).is_empty(), "obsolete save is rejected")
	game._begin_tutorial()
	game._open_day()
	check(game.queue == first_queue, "tutorial queue repeats")
	var clock = game.remaining
	game._process(float(fixture.pause_seconds))
	check(game.remaining == clock and game.dialogue == 0, "tutorial clocks paused")
	while game.guest_index < game.queue.size():
		game._save("reception")
		check(game._load_game(fixture.normal_save_path), "each lesson checkpoint loads")
		game.tutorial_director.refresh()
		var independent = fixture.independent_guest_numbers.any(func(number): return int(number) == game.guest_index + 1)
		check(game.tutorial_director.veil.visible != independent, "reload derives correct lesson mode")
		var patience_before = game.remaining
		game._process(float(fixture.pause_seconds))
		check(game.remaining == patience_before and game.dialogue == 0, "independent practice keeps paused clocks")
		print("GUEST: ", game.guest.name, " / ", game.brew.recipe.name, " / ", game.guest.request_text)
		game._advance_dialogue(0)
		var bench = game.workbench
		while game.brew.stage < 2:
			var item = game.brew.target()
			bench._choose("base" if item.name in game.config.base_names else "mixer", item.name)
			if bench.measure_focus.phase == "reading": bench.measure_focus.confirm_reading()
			game._process(float(item.amount) / game._pour_rate())
			bench.cylinder.pressed.emit()
			bench.shaker.pressed.emit()
		game._advance_dialogue(int(game.guest.good_answer))
		for item in game.brew.recipe.pre_solids: bench._choose("solids", item.name)
		bench.shaker.pressed.emit()
		if game.mixing:
			game._process(float(game.config.mix_target) * float(game.config.mix_cycle_seconds) * (float(game.config.long_mix_multiplier) if game.brew.recipe.method in ["滚摇", "长摇"] else 1.0))
			bench.shaker.pressed.emit()
		bench._choose("cups", game.brew.recipe.cup)
		bench._choose("ice", game.brew.expected_ice())
		bench.shaker.pressed.emit()
		while game.brew.stage == 3: bench._choose("topup", game.brew.recipe.topup[game.brew.topup_index].name)
		game._advance_dialogue(0)
		bench.glass.pressed.emit()
		for item in game.brew.expected_garnishes(): bench._choose("garnishes", item)
		check(game.brew.final_errors() == 0, "tutorial drink correct")
		await capture("-guest-" + str(game.guest_index))
		bench.bell.pressed.emit()
		print("SETTLED: ", game.day_income, " / money ", game.money, " / successes ", game.day_success)
		game._next_guest()
	check(game.day_success == game.queue.size(), "whole tutorial day successful")
	check(game.day_income == int(fixture.expected_income) and game.money == int(fixture.expected_money), "observed tutorial settlement")
	await capture("-shop")
	var liquid = game._find_recipe(game.tutorial.promotion_id).ingredients[0].name
	game._buy_stock(liquid)
	check(game._load_game(fixture.normal_save_path) and game.current_phase == "shop", "tutorial shop saved")
	check(JSON.parse_string(FileAccess.get_file_as_string(fixture.normal_save_path)).run.tutorial, "tutorial now uses normal save")
	game._finish_tutorial()
	check(game.progress.cycle == 2 and not game.tutorial_active, "tutorial finishes first cycle")
	check(game._load_game() and game.screen == "selection", "second cycle selection persists")
	game._choose_companion(game.config.companions[0])
	game._open_day()
	game.queue[0].customer_index = int(fixture.random_patience_customer_index)
	game.queue[0].erase("patience")
	game._start_guest()
	var patience = game.remaining
	var rng_before = game.rng.state
	check(game._load_game(), "random patience save loads")
	check(game.remaining == patience and game.rng.state == rng_before, "random patience and RNG unchanged by customer restart")
	print("TUTORIAL: %d checks; %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(0 if failures.is_empty() else 1)
