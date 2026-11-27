extends SceneTree
## Uses the production recipe catalogue as input; no duplicate recipe fixtures.
var failures: Array[String] = []
var checks = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/settings.json"))
	var recipes = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	var customers = JSON.parse_string(FileAccess.get_file_as_string("res://data/customers.json"))
	var stories = preload("res://scripts/game/story_catalog.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json")))
	if not stories.apply_customers(customers):
		quit(1)
		return
	var model = load("res://scripts/brewing/brew.gd")
	for recipe in recipes:
		check(recipe.cup in settings.cups and recipe.ice in settings.ice, recipe.id + " valid vessel data")
		for item in recipe.ingredients + recipe.topup:
			check(float(item.amount) > 0 and not item.name.is_valid_int(), recipe.id + " valid liquid data")
		for customer in customers:
			var brew = model.new(settings, recipe, customer)
			for item in recipe.ingredients:
				check(brew.target().name == item.name, recipe.id + " target order")
				brew.add_liquid(item.name, float(item.amount))
				check(brew.transfer(), recipe.id + " transfer")
			check(brew.stage == 2, recipe.id + " reaches mix")
			for item in recipe.pre_solids:
				brew.pre_solids.append(item.name)
			brew.mix_at(float(settings.mix_target))
			check(brew.stage == 3, recipe.id + " reaches vessel")
			brew.choose_vessel(recipe.cup, recipe.ice)
			brew.finish_pour()
			for item in recipe.topup:
				check(brew.stage == 3 and brew.poured, recipe.id + " topup stays in pour stage")
				brew.add_topup(item.name)
			check(brew.stage == 4, recipe.id + " reaches special")
			brew.handle_special(true)
			for item in brew.expected_garnishes():
				brew.add_garnish(item)
			check(brew.stage == 5 and brew.final_errors() == 0, recipe.id + " perfect completion / " + customer.name)
		# Wrong ingredient and overflow must survive transfer and penalize the order.
		var wrong = model.new(settings, recipe, customers[0])
		wrong.add_liquid("__invalid_liquid__", float(settings.jigger_capacity) * 2)
		check(wrong.overflow > 0, recipe.id + " overflow")
		wrong.transfer()
		check(wrong.errors > 0 and wrong.quantities[0].overflow > 0, recipe.id + " wrong pour recorded")
		if recipe.method != "直调":
			var missed = model.new(settings, recipe, customers[0])
			for item in recipe.ingredients:
				missed.add_liquid(item.name, float(item.amount))
				missed.transfer()
			missed.mix_at(0.0)
			check(missed.errors > 0, recipe.id + " bad mix penalized")
		var skipped = model.new(settings, recipe, customers[0])
		skipped.stage = 4
		skipped.ice = recipe.ice
		skipped.handle_special(false)
		check(skipped.errors > 0, recipe.id + " skipped special penalized")
		skipped.add_garnish("__invalid_garnish__")
		check(skipped.errors > 1, recipe.id + " wrong garnish penalized")
	var game = load("res://scenes/main.tscn").instantiate()
	# Tests use isolated save/log files so user progress is never overwritten.
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.mix_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.straight_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path = "user://test_save.json"
	game._choose_companion(game.config.companions[0])
	# Happy-path service includes customers who explicitly demand upgraded spirits.
	for family in game.tiers:
		game.tiers[family] = game.config.base_tiers[family].size() - 1
	game._open_day()
	game.set_process(false)
	await process_frame
	await process_frame
	check(game.header_stats.size.x > 150, "header does not wrap into a narrow column")
	check(game.left.get_child(0).get_child(1).size.x > 100, "guest information has readable width")
	# Horizontal drawers must not move the measuring cylinder.
	game._show_bottles(false)
	await process_frame
	await process_frame
	var catalogue_scroll = game.workbench.drawer_scroll
	var meter_position = game.workbench.cylinder.global_position
	catalogue_scroll.scroll_horizontal = int(catalogue_scroll.get_h_scroll_bar().max_value)
	await process_frame
	check(catalogue_scroll.scroll_horizontal > 0, "auxiliary drawer scrolls horizontally")
	check(game.workbench.cylinder.global_position.is_equal_approx(meter_position), "cylinder stays fixed while browsing ingredients")
	check(not catalogue_scroll.is_ancestor_of(game.workbench.cylinder), "cylinder is outside the drawer")
	check(game.right.get_global_rect().encloses(game.workbench.cylinder.get_global_rect()), "cylinder stays inside the work area")
	game.workbench.close_drawer()
	check(game.queue.size() >= int(settings.customers_min) and game.queue.size() <= int(settings.customers_max), "daily guest count")
	var promoted = 0
	for order in game.queue:
		if order.recipe_id == game.promotion.id:
			promoted += 1
	check(promoted >= int(settings.promotion_guarantee), "promotion guarantee")
	var before = game.money
	while game.guest_index < game.queue.size():
		game._advance_dialogue(0)
		while game.brew.stage < 2:
			var item = game.brew.target()
			game._toggle_pour(item.name)
			game._process(float(item.amount) / game._pour_rate())
			game._stop_pour()
			game._transfer()
		game._advance_dialogue(int(game.guest.good_answer))
		for item in game.brew.recipe.pre_solids:
			game.brew.pre_solids.append(item.name)
		game.brew.mix_at(float(settings.mix_target))
		game._render_operation()
		game.selected_cup = game.brew.recipe.cup
		game.selected_ice = game.brew.recipe.ice
		game._pour_into_glass()
		while game.brew.stage == 3:
			game._topup()
		game._advance_dialogue(0)
		game._special(true)
		for item in game.brew.expected_garnishes():
			game._garnish(item)
		check(game.dialogue == 3, "three conversations")
		game._serve()
		game._next_guest()
	check(game.day_success == game.queue.size(), "full successful day")
	check(game.money > before, "earned money")
	var liquid = game.stock.keys()[0]
	var previous_stock = game.stock[liquid]
	game._buy_stock(liquid)
	check(game.stock[liquid] > previous_stock, "purchase restock")
	game._save("shop")
	var saved_money = game.money
	game.money = 0
	game._load_game()
	check(game.money == saved_money, "save/load money")
	var old_day = game.day
	game._next_day()
	check(game.day == old_day + 1, "next day cycle")
	game._load_game()
	check(game.day == old_day + 1, "promotion phase resumes")
	game.companion = settings.companions[1]
	game._open_day(true)
	# The unchanged legacy guest has no race or customer-specific time override.
	game.queue[0].customer_index = 0
	game._start_guest()
	check(game.remaining >= float(game.dialogue_rules.base_patience) * float(game.companion.time_multiplier), "pope grants configured time")
	game.remaining = 0.01
	game._process(1.0)
	check(not game.playing and game.guest_index == 1, "timeout settles once")
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("SMOKE: %d checks; %d failures; %d recipes × %d guests" % [checks, failures.size(), recipes.size(), customers.size()])
	quit(0 if failures.is_empty() else 1)
