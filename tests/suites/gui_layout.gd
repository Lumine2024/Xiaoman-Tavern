extends SceneTree
## Exercise real object buttons and drawer choices using production recipe data.
var failures: Array[String] = []
var game
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle_layout() -> void:
	await process_frame
	await process_frame

func capture(suffix: String) -> void:
	await settle_layout()
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.get_basename() + suffix + ".png")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.mix_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.straight_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path = "user://gui_test_save.json"
	game._choose_companion(game.config.companions[0])
	for family in game.tiers:
		game.tiers[family] = game.config.base_tiers[family].size() - 1
	game._open_day()
	game.set_process(false)
	# Choose a real recipe that exercises the timing judgement.
	for recipe in game.recipes:
		if recipe.method != "直调":
			game.queue[0].recipe_id = recipe.id
			break
	game._start_guest()
	game.set_process(false)
	game._process(0)
	await settle_layout()
	var bench = game.workbench
	for group in ["liquids", "cups", "ice", "garnishes"]:
		for path in game.bar_assets[group].values():
			check(load(path) is Texture2D, "load asset " + path)
	check(bench.drawer_buttons.get_child_count() == 2, "two ingredient drawers before mixing")
	check(bench.bell.disabled, "bell disabled before finishing")
	check(bench.drawer_buttons.position.y >= bench.table.position.y + bench.table.size.y, "drawer fronts sit below countertop")
	check(bench.cabinet.get_rect().encloses(bench.drawer_buttons.get_rect()), "drawer fronts fit inside cabinet")
	check(bench.drawer.position.y >= bench.table.position.y + bench.table.size.y, "open drawer stays below countertop")
	await capture("")
	game._advance_dialogue(0)
	var first_pour = true
	while game.brew.stage < 2:
		var item = game.brew.target()
		bench.open_drawer("base" if item.name in game.config.base_names else "mixer")
		await settle_layout()
		await create_timer(0.25).timeout
		var fixed_at = bench.cylinder.global_position
		bench.drawer_scroll.scroll_horizontal = int(bench.drawer_scroll.get_h_scroll_bar().max_value)
		await settle_layout()
		check(bench.cylinder.global_position.is_equal_approx(fixed_at), "drawer scrolling leaves cylinder fixed")
		for card in bench.drawer_items.get_children():
			if card.get_child(0).name == item.name:
				card.get_child(0).pressed.emit()
				break
		game._process(float(item.amount) / game._pour_rate() / 2)
		await create_timer(0.25).timeout
		check(bench.measure_focus.shown, "pouring opens focused measuring close-up")
		check(bench.cylinder.level_y(game.brew.measured) > bench.cylinder.level_y(float(item.amount)), "half dose is below highlighted target")
		if first_pour:
			await capture("-pour")
			first_pour = false
		game._process(float(item.amount) / game._pour_rate() / 2)
		check(is_equal_approx(bench.cylinder.level_y(game.brew.measured), bench.cylinder.level_y(float(item.amount))), "full dose reaches target")
		bench.cylinder.pressed.emit()
		check(not game.pouring, "click cylinder pauses")
		bench.shaker.pressed.emit()
		check(bench.drawer_buttons.get_child_count() == 2, "ingredient drawers remain until mixing completes")
	check(game.brew.stage == 2, "measuring reaches mix")
	for item in game.brew.recipe.pre_solids:
		bench._choose("solids", item.name)
	bench.close_drawer()
	game._advance_dialogue(int(game.guest.good_answer))
	bench.shaker.pressed.emit()
	check(game.mixing, "click shaker starts mix")
	check(bench.gauge.size.y > bench.gauge.size.x * 5, "judgement bar is vertical")
	game.mix_position = float(game.config.mix_target)
	bench.gauge.queue_redraw()
	await capture("-mix")
	bench.shaker.pressed.emit()
	await settle_layout()
	check(game.brew.stage == 3, "second click completes mix")
	check(bench.drawer_buttons.get_child_count() == 3, "three finishing drawers after mix")
	check(not bench.gauge.visible, "judgement hidden after mixing")
	bench.open_drawer("cups")
	await capture("-cups")
	bench._choose("cups", game.brew.recipe.cup)
	bench._choose("ice", game.brew.expected_ice())
	bench.close_drawer()
	await capture("-finish")
	bench.shaker.pressed.emit()
	while game.brew.stage == 3:
		bench._choose("topup", game.brew.recipe.topup[game.brew.topup_index].name)
	check(game.brew.stage == 4, "pour and topup reach special handling")
	game._advance_dialogue(0)
	bench.glass.pressed.emit()
	check(game.brew.stage == 5, "click glass confirms request")
	for item in game.brew.expected_garnishes():
		bench._choose("garnishes", item)
	bench.close_drawer()
	await capture("-serve")
	check(game.brew.final_errors() == 0, "object workflow yields a perfect drink")
	check(not bench.bell.disabled, "bell enabled for serving")
	var served = game.day_served
	bench.bell.pressed.emit()
	check(game.day_served == served + 1 and game.day_success == 1, "bell submits drink")
	# Cover every production recipe through the new object actions, including
	# straight drinks, pre-mix solids, multiple topups and no-ice/no-garnish guests.
	for index in range(game.recipes.size()):
		var recipe = game.recipes[index]
		game._initialize_stock()
		for family in game.tiers:
			game.tiers[family] = game.config.base_tiers[family].size() - 1
		game.guest_index = 0
		game.day_served = 0
		game.day_success = 0
		game.day_income = 0
		game.queue[0] = {"recipe_id": recipe.id, "customer_index": index % game.customers.size()}
		game._start_guest()
		game.set_process(false)
		bench = game.workbench
		await settle_layout()
		check(game.get_global_rect().encloses(bench.get_global_rect()), recipe.id + " workbench fits viewport")
		game._advance_dialogue(0)
		while game.brew.stage < 2:
			var item = game.brew.target()
			bench._choose("base" if item.name in game.config.base_names else "mixer", item.name)
			game._process(float(item.amount) / game._pour_rate())
			bench.cylinder.pressed.emit()
			bench.shaker.pressed.emit()
		for item in recipe.pre_solids:
			bench._choose("solids", item.name)
		game._advance_dialogue(int(game.guest.good_answer))
		bench.shaker.pressed.emit()
		if game.mixing:
			game.mix_position = float(game.config.mix_target)
			bench.shaker.pressed.emit()
		check(bench.finishing and bench.drawer_buttons.get_child_count() == 3, recipe.id + " finishing drawers")
		bench._choose("cups", recipe.cup)
		bench._choose("ice", game.brew.expected_ice())
		bench.shaker.pressed.emit()
		while game.brew.stage == 3:
			check(bench.drawer_kind == "topup", recipe.id + " topup drawer opens")
			bench._choose("topup", recipe.topup[game.brew.topup_index].name)
		game._advance_dialogue(0)
		bench.glass.pressed.emit()
		for item in game.brew.expected_garnishes():
			bench._choose("garnishes", item)
		check(game.brew.stage == 5 and game.brew.final_errors() == 0, recipe.id + " perfect object workflow")
		bench.bell.pressed.emit()
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("GUI OBJECTS: 32 recipes; %d failures; drawers, liquid height, zoom, vertical mixing, solids, topup, serving" % failures.size())
	quit(0 if failures.is_empty() else 1)
