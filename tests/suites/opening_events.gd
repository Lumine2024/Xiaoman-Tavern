extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func capture(label: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func write(path: String, document: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()

func make_drink() -> void:
	var bench = game.workbench
	while game.brew.stage < 2:
		var item = game.brew.target()
		bench._choose("base" if item.name in game.config.base_names else "mixer", item.name)
		game._process(float(item.amount) / game._pour_rate())
		bench.cylinder.pressed.emit()
		bench.shaker.pressed.emit()
	for item in game.brew.recipe.pre_solids: bench._choose("solids", item.name)
	bench.shaker.pressed.emit()
	if game.mixing:
		game._process(float(game.config.mix_target) * float(game.config.mix_cycle_seconds) * (float(game.config.long_mix_multiplier) if game.brew.recipe.method in ["滚摇", "长摇"] else 1.0))
		bench.shaker.pressed.emit()
	bench._choose("cups", game.brew.recipe.cup)
	bench._choose("ice", game.brew.expected_ice())
	bench.shaker.pressed.emit()
	while game.brew.stage == 3: bench._choose("topup", game.brew.recipe.topup[game.brew.topup_index].name)
	bench.glass.pressed.emit()
	for garnish in game.brew.expected_garnishes(): bench._choose("garnishes", garnish)
	check(game.brew.stage == 5 and game.brew.final_errors() == 0, "appraiser uses real measuring/mixing/cup/ice/garnish workflow")
	bench.bell.pressed.emit()

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/opening_events_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Capture protected files without reading them through the obsolete-save remover.
	var protected = {}
	for path in game.save_slots.paths() + [game.interface.slots.profile_path, game.save_slots.default_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game.set_process(false)
	game.progress.advance()
	game._reset_run(game.config.companions[0], true)
	check(game.page.get_child(0).rival_mode, "rival draw precedes companion selection")
	var selector = game.page.get_child(0)
	var entry: Dictionary
	for candidate in selector.entries:
		if candidate.id == fixture.rival_id: entry = candidate
	selector.confirmed.emit(entry)
	check(not game.page.get_child(0).rival_mode and game.competition.state.rival == fixture.rival_id, "drawn opponent is visible before buff choice")
	check(game._load_game() and not game.page.get_child(0).rival_mode and game.competition.state.rival == fixture.rival_id, "loading companion choice does not reroll opponent")
	game.page.get_child(0).confirmed.emit(game.config.companions[int(fixture.companion_index)])
	check(game.day == 0 and game.current_phase == "preparation", "new run starts in D0 shop")
	for name in game.stock:
		check(game.stock[name] == (float(game.config.opening_stock.base_ml) if name in game.config.base_names and name in game.selectable_liquids() else 0.0), "D0 stock: " + name)
	check(game.money == int(game.config.starting_money), "initial cash retained until purchase")
	check(game.stock.keys().filter(func(name): return game.stock[name] > 0).size() == game.config.base_tiers.size(), "six base families start stocked after the rum ruling")
	for size in fixture.windows:
		root.size = Vector2i(size[0], size[1])
		await capture("-d0-" + str(size[0]))
	var before = game.money
	var cost = game._stock_price(fixture.purchases[0])
	for name in fixture.purchases: game._buy_stock(name)
	check(game.money < before and game.stock[fixture.purchases[0]] == game.pricing.catalog.ingredients[fixture.purchases[0]].pack_ml, "D0 purchase uses real money and pack size")
	check(game._load_game() and game.day == 0 and game.last_save_ok, "D0 purchases roundtrip")
	if not game.last_save_ok: quit(1); return
	var purchase_cash = game.money
	var bought = game.stock.duplicate(true)
	game._finish_preparation()
	check(game.day == 1 and game.stock == bought, "D0 to D1 does not spoil opening supplies")
	game._select_counter_card("follow")
	var baseline_rules = game.competition.daily_events.rules.events
	game.competition.daily_events.rules.events = {}
	for id in fixture.baseline_event_ids: game.competition.daily_events.rules.events[id] = baseline_rules[id]
	game._open_day()
	if not game.competition.state.receipts.has("opening"): game._answer_opening(game.competition.street.data.responses.keys()[0])
	check(game.queue.size() > 0 and game.money == purchase_cash, "opening does not auto-purchase orders")
	var events = game.competition.daily_events
	check(events.state.records.size() == mini(int(events.rules.daily_count), events.rules.events.size()), "daily event target generated without duplicating types")
	var generated = events.state.duplicate(true)
	events.generate(game.day, game.rng)
	check(events.state == generated, "event generation cannot reroll same day")
	var conflicting = load("res://scripts/game/daily_events.gd").new()
	conflicting.rules = events.rules.duplicate(true)
	conflicting.rules.events.lemon_discount = conflicting.rules.events.lemon_shipping.duplicate(true)
	conflicting.rules.events.lemon_discount.multiplier = fixture.event_expectations.conflict_discount_factor
	conflicting.generate(game.day, game.rng)
	var price_group = conflicting.state.records.filter(func(record): return conflicting.rules.events[record.id].conflict_group == "price:柠檬汁")
	check(price_group.size() == 1, "same ingredient cannot rise and fall together")
	conflicting.generate(int(fixture.event_expectations.lemon_expiry_day), game.rng)
	check(conflicting.state.records.filter(func(record): return int(record.day) == int(fixture.event_expectations.lemon_expiry_day) and conflicting.rules.events[record.id].conflict_group == "price:柠檬汁").is_empty(), "price-event cooldown leaves an actual return to normal")
	var captain_index = 0
	for i in game.customers.size():
		if game.customers[i].story_id == fixture.captain_id: captain_index = i
	game.queue[0] = {"recipe_id": fixture.lemon_recipe_id, "customer_index": captain_index}
	game.guest_index = 0
	game.day_served = 0
	game.stock[fixture.lemon_ingredient] = 0.0
	var rng_before = game.rng.state
	game._start_guest()
	check(not game.playing and game.brew == null and not game.queue[0].has("event_rolls"), "missing stock offers no service or information roll")
	check(game.rng.state == rng_before and events.state == generated, "unserviceable guest does not consume RNG/information")
	await capture("-unavailable")
	var cash = game.money
	var stock = game.stock.duplicate(true)
	game._decline_guest(0)
	check(game.money == cash and game.stock == stock and game.guest_index == 1, "refusal has no charge or ingredient consumption")
	# Independently verify the stochastic path with a replayed RNG, not forced p=1.
	var seen_success = false
	var seen_failure = false
	for seed_value in fixture.disclosure_seeds:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		var reference = RandomNumberGenerator.new()
		reference.seed = seed_value
		var expected = reference.randf() < float(events.rules.disclosure_probability)
		var order = {}
		events.offer(fixture.captain_id, order, game.day, rng)
		check((int(order.event_offer) >= 0) == expected, "p=0.5 follows the real sample")
		seen_success = seen_success or expected
		seen_failure = seen_failure or not expected
		var state_before = rng.state
		events.offer(fixture.captain_id, order, game.day, rng)
		check(rng.state == state_before, "restarting a guest never rerolls information")
	check(seen_success and seen_failure, "both outcomes exercised")
	var unrelated = {}
	events.offer(fixture.unrelated_customer_id, unrelated, game.day, game.rng)
	check(unrelated.event_rolls.is_empty(), "unrelated customer cannot reveal event")
	check(unrelated.message_kind == "smalltalk", "idle branch selects only the smalltalk pool")
	var found_claim = false
	var market_before = events.state.duplicate(true)
	for seed_value in fixture.claim_seeds:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		var order = {}
		events.offer(fixture.rumor_customer_id, order, game.day, rng)
		if order.message_claim == "lemon_rise":
			events.hear(order)
			found_claim = true
			check(order.message_kind == "smalltalk" and int(order.event_offer) == -1, "Lumi's misleading claim is smalltalk, never an event")
			break
	check(found_claim and events.can_verify("lemon_rise", fixture.captain_id), "heard alley rumor can be checked with captain")
	check(not events.can_verify("lemon_rise", fixture.rumor_customer_id), "rumor source cannot act as the verifier")
	check(events.verify("lemon_rise", fixture.captain_id, game.day) == events.pools.claims.lemon_rise.upcoming, "captain forecasts tomorrow without claiming a current rise")
	check(events.verify("lemon_rise", fixture.captain_id, int(fixture.event_expectations.lemon_first_day)) == events.pools.claims.lemon_rise.up, "captain confirms a real current rise")
	check(events.verify("lemon_rise", fixture.captain_id, int(fixture.event_expectations.lemon_expiry_day)) == events.pools.claims.lemon_rise.not_up, "captain rejects a rise after the price has expired")
	check(events.state.records.size() == market_before.records.size(), "smalltalk does not create economic events")
	# Keep an unheard event for the later-visit test after the explicit verification.
	for record in events.state.records: record.heard = false
	var historical = {}
	var historical_rng = RandomNumberGenerator.new()
	for seed_value in fixture.claim_seeds:
		historical_rng.seed = seed_value
		historical = {}
		events.offer(fixture.captain_id, historical, int(fixture.event_expectations.lemon_expiry_day), historical_rng)
		if int(historical.event_offer) >= 0: break
	check(historical.message_text in events.pools.history.lemon_shipping[fixture.captain_id], "deferred expired information uses historical phrasing")
	var lemon = game._find_recipe(fixture.lemon_recipe_id)
	check(events.price_factor(fixture.lemon_ingredient, game.day) == 1.0 and events.drink_factor(lemon, game.day) == 1.0, "notice day retains ordinary prices")
	check(is_equal_approx(events.price_factor(fixture.lemon_ingredient, int(fixture.event_expectations.lemon_first_day)), float(fixture.event_expectations.lemon_factor)) and is_equal_approx(events.drink_factor(lemon, int(fixture.event_expectations.lemon_first_day)), float(fixture.event_expectations.lemon_factor)), "ingredient and drinks both rise tomorrow")
	check(events.price_factor(fixture.lemon_ingredient, int(fixture.event_expectations.lemon_expiry_day)) == 1.0, "lemon price expires after three nights")
	var reviews_index = -1
	for i in events.state.records.size():
		if events.state.records[i].id == "paid_reviews": reviews_index = i
	var reviews: Dictionary = events.state.records[reviews_index]
	check(not events.active(reviews, int(fixture.event_expectations.reviews_before_day)) and events.active(reviews, int(fixture.event_expectations.reviews_first_day)) and events.active(reviews, int(fixture.event_expectations.reviews_last_day)) and not events.active(reviews, int(fixture.event_expectations.reviews_expiry_day)), "reviews wait two days then last four days")
	reviews.heard = true
	var unresolved = events.state.duplicate(true)
	check(events.discount(reviews_index, game.day) and is_equal_approx(events.margin_loss(game.day), float(fixture.event_expectations.discount_margin_loss)), "price response gives up fifteen percent margin")
	check(not events.discount(reviews_index, game.day), "discount cannot be purchased twice")
	events.state = unresolved
	# Enter a genuine paid appraisal from the shop; fee is paid once and brewing is recoverable.
	game.money = int(fixture.rich_cash)
	for name in game.stock: game.stock[name] = float(fixture.batch_ml)
	game.stock_ledger.reset(game.stock)
	game.promotion = game._find_recipe(fixture.recipe_id)
	game.queue = [{"recipe_id": fixture.recipe_id, "customer_index": 0}]
	game.guest_index = 1
	game.day_served = 1
	game.show_shop()
	var before_appraisal = game.stock.duplicate(true)
	var fee = events.action_cost(reviews_index, game.day)
	cash = game.money
	game._resolve_daily_event(reviews_index)
	check(game.playing and game.guest.name == "鉴定师" and game.brew.stage == 0 and game.money == cash - fee, "appraiser enters existing brewing after a single fee")
	check(game.stock == before_appraisal, "appraiser does not deduct a fixed bottle")
	check(game._load_game() and game.guest.name == "鉴定师" and game.money == cash - fee, "appraiser reload does not charge again")
	await capture("-appraiser")
	make_drink()
	check(events.state.records[reviews_index].resolved, "correct real drink neutralizes purchased reviews")
	check(game.money == cash - fee, "appraiser pays no sales revenue or tip")
	for item in game.promotion.ingredients + game.promotion.topup:
		check(is_equal_approx(game.stock[item.name], float(before_appraisal[item.name]) - float(item.amount)), "appraiser consumes exact recipe quantity")
	var valid = game._snapshot("shop")
	check(not game.save_schema.decode(valid).is_empty(), "current save validates with appraisal record")
	var invalid = valid.duplicate(true)
	invalid.run.daily_events.records[0].due = -1
	check(game.save_schema.decode(invalid).is_empty(), "malformed event timeline rejected")
	# Exercise the real verification button path against current prices.
	game.queue = [{"recipe_id": fixture.lemon_recipe_id, "customer_index": captain_index}]
	game.guest_index = 0
	game.day_served = 0
	game.day_success = 0
	game._start_guest()
	game.dialogue = 1
	game.brew.stage = 4
	game.rapport = true
	game._draw_dialogue()
	await capture("-captain-verification")
	game._verify_market_claim("lemon_rise")
	check(game.queue[0].verification_text == events.pools.claims.lemon_rise.upcoming, "real captain verification separates today's normal price from tomorrow")
	await capture("-captain-confirmed")
	for version in fixture.old_versions:
		var old = valid.duplicate(true)
		old.version = version
		write(fixture.obsolete_path, old)
		write(fixture.obsolete_path + ".bak", old)
		check(game.save_store.load_snapshot(fixture.obsolete_path, game.save_schema.decode).is_empty(), "old save is never migrated")
		check(not FileAccess.file_exists(fixture.obsolete_path) and not FileAccess.file_exists(fixture.obsolete_path + ".bak"), "old save and old backup deleted")
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "unread user save/profile protected")
	for path in [fixture.save_path, fixture.obsolete_path]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("OPENING EVENTS: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(1 if failures else 0)
