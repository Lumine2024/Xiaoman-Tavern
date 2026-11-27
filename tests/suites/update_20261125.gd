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

func capture(label: String) -> void:
	await process_frame
	if not output.is_empty() and label.begins_with("-result-"):
		var file = FileAccess.open(output + label + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(game._snapshot("shop")))
		file.close()
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func complete() -> void:
	game.scene_transition.cancel()
	game._advance_dialogue(0)
	while game.brew.stage < 2:
		var target = game.brew.target()
		game.stock_ledger.consume(target.name, float(target.amount))
		game.stock[target.name] -= float(target.amount)
		game.brew.add_liquid(target.name, float(target.amount))
		game.brew.transfer()
	for item in game.brew.recipe.pre_solids: game.brew.pre_solids.append(item.name)
	game._advance_dialogue(0)
	game.brew.mix_at(float(game.config.mix_target))
	game.brew.choose_vessel(game.brew.recipe.cup, game.brew.expected_ice())
	game.brew.finish_pour()
	for item in game.brew.recipe.topup:
		game.stock_ledger.consume(item.name, float(item.amount))
		game.stock[item.name] -= float(item.amount)
		game.brew.add_topup(item.name)
	var answer = int(game.guest.good_answer)
	if game.guest.has("choices"):
		for index in game.guest.choices.size():
			if game.guest.choices[index].answer == "valid" and not game.guest.choices[index].get("leak", false):
				answer = index
				break
	game._advance_dialogue(answer)
	game.brew.handle_special(true)
	for garnish in game.brew.expected_garnishes(): game.brew.add_garnish(garnish)
	game._serve()

func promotion(relative_day: int) -> String:
	var cursor = 0
	for index in fixture.rotation.size():
		cursor += int(fixture.rotation_days[index])
		if relative_day <= cursor: return fixture.rotation[index]
	return fixture.rotation.back()

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/update_20261125_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game.set_process(false)
	for id in fixture.rum_merge:
		var raw: Dictionary = game.recipes.filter(func(recipe): return recipe.id == id)[0]
		var rum: Array = raw.ingredients.filter(func(item): return item.name in game.rulings.rum.names)
		check(rum.size() == 1 and rum[0].name == fixture.rum_merge[id].name and rum[0].amount == fixture.rum_merge[id].amount, "authored merged rum formula: " + id)
	check(game._find_recipe("M-09").pre_solids.is_empty(), "mint is only garnish")
	for filename in fixture.audio_files:
		var path = "res://assets/audio/sfx/" + str(filename) + ".ogg"
		check(ResourceLoader.exists(path) and load(path) is AudioStreamOggVorbis and load(path).get_length() > 0, "delivered Ogg decodes: " + str(filename))
	check(game.theme.get_stylebox("focus", "Button") is StyleBoxTexture and not game.theme.get_stylebox("focus", "Button").draw_center, "focus frame leaves other button state visible")
	game.pause_menu.open()
	game.pause_menu.show_settings()
	await capture("-settings")
	check(game.pause_menu.content.get_parent().get_theme_stylebox("panel") is StyleBoxTexture, "delivered panel is wired")
	game.pause_menu.close()
	game._begin_rival_run(game.config.companions[0], fixture.rivals[0])
	game.rng.seed = int(fixture.seed)
	game.money = int(fixture.money)
	for family in game.tiers: game.tiers[family] = int(fixture.tier)
	for ingredient in game.stock: game.stock[ingredient] = float(fixture.stock_ml) if ingredient in game.selectable_liquids() else 0.0
	game.stock_ledger.reset(game.stock)
	game._sync_challenge()
	check(game.challenge.state.phase == "preparation" and not game.challenge.state.retry.is_empty(), "new challenge has D0 retry snapshot")
	check(game.selectable_liquids().size() == game.stock.size() - game.rulings.rum.names.size() + 1, "three rum names are a single live inventory family")
	game.challenge.state.retry = {}
	game.challenge.state.retry = game._snapshot("preparation")
	check(game._save("preparation"), "controlled D0 fixture validates before the run")
	for index in fixture.rivals.size():
		var id: String = fixture.rivals[index]
		if index > 0:
			var cash_before = game.money
			var stock_before = game.stock.duplicate(true)
			var tiers_before = game.tiers.duplicate(true)
			var captain_before = game.competition.state.street.captain.duplicate(true)
			var events_before = game.competition.daily_events.state.duplicate(true)
			game.challenge_view.start(id)
			check(game.money == cash_before and game.stock == stock_before and game.tiers == tiers_before, "new opponent inherits shop assets: " + id)
			check(game.competition.daily_events.state == events_before and game.competition.state.street.captain == captain_before, "calendar events and customer memory survive next opponent")
			check(game.challenge.state.stats.valid == 0 and game.challenge.day(game.day) == 0, "only round counters restart")
		game.show_shop()
		if id == fixture.rivals[0]:
			for window in fixture.windows:
				root.size = Vector2i(window[0], window[1])
				await capture("-d0-" + str(int(window[0])))
		for opportunity in game.challenge.state.opportunities:
			if game.day >= int(opportunity.notice) and game.day < int(opportunity.due):
				game.challenge.heard(opportunity, game.day)
				check(game.challenge.plan(opportunity, game.day, game._can_serve(game._find_recipe(opportunity.recipe))), "Olga preview can be prepared before first service")
		game._finish_preparation()
		var potential = 0
		var promoted = 0
		for relative in range(1, int(game.challenge.rules.days) + 1):
			game.scene_transition.cancel()
			game.competition.state.receipts.keep_card = true
			if game.competition.state.street.card.is_empty(): game.competition.street.choose(game.competition.state.street, fixture.card, relative)
			game.promotion = game._find_recipe(game.challenge.planned_promotion(game.day) if not game.challenge.planned_promotion(game.day).is_empty() else promotion(relative))
			game._open_stock_day()
			if relative == 1 and not game.playing:
				var before = game.money
				game._answer_opening(fixture.opening_answer)
				check(game.money == before and game.competition.state.street.respect > 0, "D1 appearance changes respect without money")
			check(game.queue.size() > 0 and game.challenge.active(), "no early victory or empty opportunity day")
			potential += game.queue.size()
			promoted += game.queue.filter(func(order): return order.recipe_id == order.promotion_id).size()
			if id == "olga" and not game.challenge.due_opportunity(game.day).is_empty():
				var due = game.challenge.due_opportunity(game.day)
				check(game.queue.filter(func(order): return order.recipe_id == due.recipe).size() >= int(game.challenge.rules.rivals.olga.orders_per_opportunity), "each announced Olga event has three normal opportunities")
			while game.guest_index < game.queue.size():
				if game.playing: complete()
				else: game._decline_guest(game.guest_index)
				game.scene_transition.cancel()
				if game.guest_index < game.queue.size(): game._next_guest()
				await process_frame
			check(game.last_save_ok, "actual service state saves: " + id)
			if relative < int(game.challenge.rules.days):
				game._next_guest()
				for ingredient in game.selectable_liquids():
					if float(game.stock[ingredient]) < float(fixture.restock_at):
						var pack_ml = float(game.pricing.catalog.ingredients[ingredient].pack_ml)
						game._buy_stock(ingredient, ceili((float(fixture.restock_target) - float(game.stock[ingredient])) / pack_ml))
				for opportunity in game.challenge.state.opportunities:
					if game.day >= int(opportunity.notice) and game.day < int(opportunity.due):
						game.challenge.heard(opportunity, game.day)
						game.challenge.plan(opportunity, game.day, game._can_serve(game._find_recipe(opportunity.recipe)))
				game._next_day()
		check(game.challenge.state.phase == "result", "D14 closes at final order: " + id)
		print("CHALLENGE ROUND %s: opportunities=%d valid=%d net=%.2f won=%s" % [id, game.challenge.state.stats.opportunities, game.challenge.state.stats.valid, game.challenge.state.stats.net, str(game.challenge.won())])
		check(game.challenge.won(), "fully prepared fixture can meet both objectives: " + id)
		if id == "karn": check(potential >= int(fixture.min_karn_opportunities), "Karn budget includes all pressure sources")
		if id == "bella": check(promoted >= int(fixture.min_bella_promotions), "Bella keeps forty-two promoted opportunities")
		game._next_guest()
		await capture("-result-" + id)
		var unchanged_stock = game.stock.duplicate(true)
		check(game._load_game() and game.challenge.state.phase == "result" and game.stock == unchanged_stock, "D14 result reloads without extra spoilage or another score")
	check(game.challenge.state.defeated.size() == fixture.rivals.size() and game.challenge.state.finale_seen, "six completed rivals trigger persistent finale")
	var final_assets = game.stock.duplicate(true)
	game.challenge_view.free_trade()
	check(game.challenge.state.phase == "free" and game.competition.state.rival.is_empty() and game.stock == final_assets, "free mode removes pressure without resetting tavern")
	game.challenge_view.start(fixture.rivals[0])
	var initial_snapshot: Dictionary = game.challenge.state.retry.duplicate(true)
	game.money -= int(fixture.money) / 2
	game.tiers[fixture.rum_family] = 0
	game.challenge.state.phase = "active"
	game.day = int(game.challenge.state.start_day) + int(game.challenge.rules.days) - 1
	game.challenge.finish(game.day)
	game.challenge_view.retry()
	check(game.money == int(initial_snapshot.run.money) and game.tiers == initial_snapshot.run.tiers and game.challenge.state.phase == "preparation", "failed retry rolls back cash, grades and D0 without failed-run income")
	for path in protected: check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "user data protected: " + path)
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("UPDATE 20261125: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(1 if failures else 0)
