extends SceneTree
var checks = 0
var failures = 0
var fixture: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func record(id: String) -> Dictionary:
	return {"id": id, "day": int(fixture.start_day), "due": int(fixture.start_day), "heard": false, "resolved": false, "mitigation": "", "action_day": 0}

func frequencies(model, recipes: Array) -> Dictionary:
	var counts = {}
	var rng = RandomNumberGenerator.new()
	rng.seed = int(fixture.sample_seed)
	for index in int(fixture.sample_count):
		var id: String = model.sample_order(recipes, fixture.promotion_recipe, int(fixture.start_day), rng)
		counts[id] = int(counts.get(id, 0)) + 1
	return counts

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/market_trend_cases.json"))
	var recipes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	var customers: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/customers.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prices.json"))
	var model = load("res://scripts/game/daily_events.gd").new()
	check(model.configuration_errors().is_empty(), "all runtime event references and pools validate")
	check(model.rules.trend_bands == fixture.trend_bands, "medium and hard are both required")
	for ingredient in catalog.ingredients:
		var rises = []
		var falls = []
		for id in model.rules.events:
			var event: Dictionary = model.rules.events[id]
			if event.kind != "price" or event.ingredient != ingredient: continue
			(rises if float(event.multiplier) > 1 else falls).append(id)
			check(event.conflict_group == "price:" + ingredient, "opposite prices share ingredient conflict group")
		check(not rises.is_empty() and not falls.is_empty(), "up and down exist: " + ingredient)
		for id in rises + falls:
			model.state.records = [record(id)]
			check(is_equal_approx(model.price_factor(ingredient, int(fixture.start_day)), float(model.rules.events[id].multiplier)), "each authored price event actually changes its ingredient")
	var trends = []
	for recipe in recipes:
		var found = []
		for id in model.rules.events:
			var event: Dictionary = model.rules.events[id]
			if event.kind == "trend" and event.recipe_id == recipe.id: found.append(id)
		if recipe.id.split("-")[0] not in fixture.trend_bands:
			check(found.is_empty(), "simple recipe has no unrequested trend")
			continue
		check(not found.is_empty(), "trend exists for " + recipe.name)
		trends.append_array(found)
		for id in found:
			check(model.rules.events[id].customer_ids == ["*"], "trend is open to every customer")
			model.state.records = [record(id)]
			var weights = model.order_weights(recipes, fixture.promotion_recipe, int(fixture.start_day))
			check(float(weights[recipe.id]) > float(weights[fixture.normal_recipe]) and float(weights[recipe.id]) < float(weights[fixture.promotion_recipe]), "each trend remains between normal and promotion")
			var expired_day = int(fixture.start_day) + int(model.rules.events[id].duration_days)
			check(model.order_weights(recipes, fixture.promotion_recipe, expired_day)[recipe.id] == model.rules.order_weights.normal, "each trend expires back to normal")
	# Even simultaneous trends and a changed/also-trending promotion preserve the strict ordering.
	model.state.records = trends.map(func(id): return record(id))
	for promotion_id in [fixture.promotion_recipe, fixture.second_promotion]:
		var weights = model.order_weights(recipes, promotion_id, int(fixture.start_day))
		for recipe in recipes:
			if recipe.id != promotion_id: check(float(weights[recipe.id]) < float(weights[promotion_id]), "promotion remains highest with all trends active")
	model.state.records = [record(fixture.trend_event)]
	for customer in customers:
		var hit = false
		for seed_value in fixture.disclosure_seeds:
			var rng = RandomNumberGenerator.new()
			rng.seed = int(seed_value)
			var order = {}
			model.offer(customer.story_id, order, int(fixture.start_day), rng)
			if int(order.event_offer) < 0: continue
			hit = true
			check(order.message_text in model.pools.effective[fixture.trend_event].get(customer.story_id, model.pools.effective[fixture.trend_event]["*"]), "any customer speaks a matching trend message")
			var rng_after = rng.state
			model.offer(customer.story_id, order, int(fixture.start_day), rng)
			check(rng.state == rng_after, "wildcard message is cached on repeat visits to order")
			break
		check(hit, "trend disclosure reachable for " + customer.story_id)
	var boosted = frequencies(model, recipes)
	model.state.records = []
	var ordinary = frequencies(model, recipes)
	check(int(boosted.get(fixture.trend_recipe, 0)) > int(ordinary.get(fixture.trend_recipe, 0)), "real weighted samples show increased trend demand")
	check(int(boosted.get(fixture.trend_recipe, 0)) < int(boosted.get(fixture.promotion_recipe, 0)), "real weighted samples still favor promotion")
	print("TREND SAMPLES: normal=%d; trending=%d; promotion=%d; draws=%d" % [ordinary.get(fixture.trend_recipe, 0), boosted.get(fixture.trend_recipe, 0), boosted.get(fixture.promotion_recipe, 0), fixture.sample_count])
	for invalid in fixture.invalid_weights:
		var original = model.rules.order_weights
		model.rules.order_weights = invalid
		check(not model.configuration_errors().is_empty(), "invalid popularity ordering is rejected")
		model.rules.order_weights = original
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game._begin_rival_run(game.config.companions[0], "karn")
	game.set_process(false)
	game._finish_preparation()
	game._select_counter_card("follow")
	game.competition.daily_events.state = {"generated_days": [int(fixture.start_day)], "records": [record(fixture.trend_event)], "heard_claims": []}
	game.config.customers_min = int(fixture.configured_customers)
	game.config.customers_max = int(fixture.configured_customers)
	game._open_day()
	if not game.competition.state.receipts.has("opening"): game._answer_opening(game.competition.street.data.responses.keys()[0])
	check(game.queue.size() > 0 and game.queue.filter(func(order): return order.recipe_id == game.promotion.id).size() >= int(game.config.promotion_guarantee), "real opening preserves promotion guaranteed orders")
	var saved_queue = game.queue.duplicate(true)
	var rng_after = game.rng.state
	check(game._load_game() and game.queue == saved_queue and game.rng.state == rng_after, "actual trend orders and RNG survive reload without resampling")
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real user data protected")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("MARKET TRENDS: %d checks; %d failures; %d price events; %d trends" % [checks, failures, catalog.ingredients.size() * 2, trends.size()])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
