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
func capture(label: String) -> void:
	await frames()
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")
func companion(id: String) -> Dictionary:
	return game.config.companions.filter(func(item): return item.id == id)[0]
func begin(id: String) -> void:
	game.scene_transition.cancel()
	game._begin_rival_run(companion(id), fixture.rivals[0])
	check(game.last_save_ok, "new round saves: " + id)
func active() -> void:
	game.challenge.state.phase = "active"
	game.day = int(game.challenge.state.start_day)
	game._sync_challenge()
func win() -> void:
	var challenge = game.challenge
	challenge.state.stats.opportunities = int(challenge.rules.rivals.karn.minimum_opportunities)
	challenge.state.days = {str(challenge.state.start_day): challenge.state.stats.opportunities}
	challenge.state.stats.valid = int(challenge.rules.rivals.karn.metrics[0].target)
	challenge.state.stats.net = float(challenge.rules.rivals.karn.metrics[1].target)
	game.day = int(challenge.state.start_day) + int(challenge.rules.days) - 1
	challenge.finish(game.day)
	game.companion_progress.finish(challenge)
	check(game._save("promotion"), "frozen companion result saves")
func check_decode() -> void:
	check(not game.save_schema.decode(game._snapshot("promotion")).is_empty(), "current state decodes")
func purchase_for_recipe(recipe: Dictionary) -> void:
	var portions = {}
	for item in recipe.ingredients + recipe.topup: portions[item.name] = float(portions.get(item.name, 0)) + float(item.amount) * int(fixture.orders_per_day)
	for name in portions:
		var missing = float(portions[name]) - float(game.stock[name])
		if missing > 0: game._buy_stock(name, ceili(missing / float(game.pricing.catalog.ingredients[name].pack_ml)))

func serve_real_order() -> void:
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
	game._advance_dialogue(int(game.guest.good_answer))
	game.brew.handle_special(true)
	for garnish in game.brew.expected_garnishes(): game.brew.add_garnish(garnish)
	game._serve()
func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/companions_cases.json"))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	game.set_process(false)
	game.pause_menu.reduced_motion = true
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	check(game.config.companions.map(func(item): return item.id) == fixture.ids, "exactly five authored companions")
	for id in fixture.ids: check(game.character_art.companions.has(id) and load(game.character_art.companions[id]) is Texture2D, "delivered companion portrait: " + id)
	var model = game.companion_progress
	begin("merchant")
	game.money = int(fixture.cash)
	for case in fixture.batch_cases:
		var bill = {"name": fixture.family, "packs": 1, "total": case.raw}
		var priced = model.discount_bill(bill, "merchant", game.pricing.catalog)
		check(priced.total == int(case.expected), "final bill rounds merchant discount once")
		check(model.discount_bill(priced, "merchant", game.pricing.catalog) == priced, "discount is idempotent")
		check(bill.total == case.raw, "pricing does not mutate original bill")
	for emergency in [false, true]:
		for bulk in [false, true]:
			var ordinary = game.competition.purchase_bill(fixture.family, int(fixture.purchase_packs), game.pricing.pack_price(fixture.family, game.tiers), game.day, game.tiers, emergency, bulk)
			var actual = game._purchase_bill(fixture.family, int(fixture.purchase_packs), game.pricing.pack_price(fixture.family, game.tiers), game.day, game.tiers, emergency, bulk)
			check(actual.total == roundi(float(ordinary.total) * float(model.rules.merchant.purchase_multiplier)), "normal/emergency/bulk pricing matches final discount")
	var raw = int(game.config.base_tiers[fixture.family][1].unlock_fee)
	var before = game.money
	game._buy_tier(fixture.family)
	check(before - game.money == roundi(raw * float(model.rules.merchant.upgrade_multiplier)), "base upgrade takes merchant price")
	before = game.money
	game._buy_equipment()
	check(before - game.money == roundi(int(game.config.equipment_price) * float(model.rules.merchant.upgrade_multiplier)), "equipment takes merchant price")
	var quote = game._purchase_bill(fixture.family, 1, game.pricing.pack_price(fixture.family, game.tiers), game.day, game.tiers)
	before = game.money
	game._buy_stock(fixture.family)
	check(before - game.money == quote.total, "real purchase takes displayed discounted price")
	var ledger = game.stock_ledger
	ledger.order_discounted.clear()
	ledger.consume(fixture.family, float(fixture.gifted_ml))
	check(ledger.order_discounted.is_empty(), "FIFO opening gift is never discounted stock")
	ledger.consume(fixture.family, float(fixture.consume_ml))
	check(ledger.order_discounted.has(fixture.family), "FIFO reaches tagged bought batch")
	check(ledger.batches[fixture.family][0].merchant_discount and is_equal_approx(float(ledger.batches[fixture.family][0].unit_cost), float(quote.unit_cost)), "batch retains actual discounted unit cost")
	var saved_ledger = ledger.snapshot()
	ledger.restore(saved_ledger)
	check(ledger.batches[fixture.family][0].merchant_discount, "batch marker survives restore")
	ledger.order_discounted.clear()
	ledger.consume(fixture.family, 1, true)
	check(ledger.order_discounted.is_empty(), "spoilage never contributes order coverage")
	active()
	var failed = {}
	model.score(game, failed, false)
	model.score(game, {"event_appraisal": 0}, true)
	check(model.valid_orders() == 0, "failed and system orders excluded")
	for name in game.stock: game.stock[name] = 0.0
	ledger.reset(game.stock)
	game.challenge.state.phase = "preparation"
	for name in fixture.merchandise: game._buy_stock(name, int(fixture.purchase_packs))
	game.challenge.state.phase = "active"
	for index in int(fixture.merchant_goal_orders):
		var name: String = fixture.merchandise[index % fixture.merchandise.size()]
		ledger.order_discounted.clear()
		ledger.consume(name, 1)
		game.stock[name] -= 1
		var order = {}
		model.score(game, order, true)
		model.score(game, order, true)
	check(model.state.discount_orders == int(fixture.merchant_goal_orders) and model.state.discount_ingredients.size() == fixture.merchandise.size(), "valid tagged orders deduplicate and cover six ingredients")
	win()
	check(model.state.outcome == "success", "merchant success ending")
	check(game._load_game(fixture.save_path) and model.state.outcome == "success", "frozen merchant result reloads")
	check(not is_instance_valid(game.storage_dialog), "merchant workflow has no save warning")
	game.challenge_view.result()
	await capture("-merchant-ending")
	begin("banker")
	var unearned_cash = game.money
	model.close_day(game)
	check(game.money == unearned_cash and model.state.interest_days.is_empty(), "D0 never earns interest")
	active()
	game.challenge.state.phase = "free"
	model.close_day(game)
	check(game.money == unearned_cash and model.state.interest_days.is_empty(), "free trading never earns interest")
	game.challenge.state.phase = "rest"
	model.close_day(game)
	check(model.state.interest_days.is_empty(), "rest never earns interest")
	begin("banker")
	active()
	for index in int(model.rules.banker.days) / 2:
		game.day = index + 1
		game.money = int(model.rules.banker.principal_cap)
		model.state.valid_by_day[str(game.day)] = int(model.rules.banker.daily_valid)
		model.close_day(game)
	check(model.state.interest_total >= int(model.rules.banker.interest) and not model.achieved(game.challenge), "interest amount alone cannot replace eligible business days")
	var failure_money = game.money
	game.day = int(game.challenge.rules.days)
	game.challenge.finish(game.day)
	model.finish(game.challenge)
	check(model.state.outcome == "failure" and game.money == failure_money, "failure ending adds no penalty or money")
	for case in fixture.bank_cases:
		begin("banker")
		active()
		game.money = int(case.cash)
		game.competition.state.credit_used = int(case.debt)
		model.state.valid_by_day[str(game.day)] = int(case.valid)
		model.close_day(game)
		check(game.money == int(case.cash) + int(case.interest), "bank cash minus debt, cap and floor")
		model.close_day(game)
		check(game.money == int(case.cash) + int(case.interest), "daily interest cannot repeat")
	begin("banker")
	active()
	for index in int(fixture.bank_days):
		game.day = index + 1
		game.money = int(fixture.bank_cases[0].cash)
		model.state.valid_by_day[str(game.day)] = int(fixture.bank_cases[0].valid)
		model.close_day(game)
	check(model.state.interest_total == int(fixture.bank_interest) and model.qualified_days() == int(fixture.bank_days), "banker separately accumulates interest and eligible days")
	check(is_zero_approx(game.stock_ledger.contribution()), "interest excluded from operating net")
	win()
	check(model.state.outcome == "success", "banker success ending")
	var cash = game.money
	check(game._load_game(fixture.save_path) and game.money == cash, "banker reload does not repay interest")
	game.challenge_view.result()
	await capture("-banker-ending")
	begin("patron")
	check(game.money == int(fixture.rich_cash) and model.state.investment == int(fixture.investment), "patron first D0 receives investment")
	check(game.challenge.state.retry.run.money == game.money and game.challenge.state.retry.run.companion_progress.claims == model.state.claims, "D0 snapshot contains money and claim together")
	var start_cash = game.money
	game._buy_tier(fixture.family)
	game._buy_tier(fixture.family)
	game._buy_tier(fixture.second_family)
	game._buy_equipment()
	check(model.state.upgrade_base == int(fixture.raw_upgrades) and model.state.upgrade_families.size() == 2, "new permanent levels count raw price and two families")
	var upgrade_total = model.state.upgrade_base
	model.upgrade(fixture.family, int(game.tiers[fixture.family]), int(game.config.base_tiers[fixture.family][int(game.tiers[fixture.family])].unlock_fee))
	check(model.state.upgrade_base == upgrade_total, "same level never counts twice")
	game.challenge_view.retry()
	check(game.money == start_cash and model.state.claims.size() == 1 and model.state.upgrade_base == 0, "retry restores D0 money claims and upgrades without extra investment")
	game._buy_tier(fixture.family)
	game._buy_tier(fixture.family)
	game._buy_tier(fixture.second_family)
	game._buy_equipment()
	active()
	model.state.valid_by_day[str(game.day)] = int(fixture.rich_valid)
	win()
	check(model.state.outcome == "success", "patron raw-upgrade success ending")
	game.challenge_view.result()
	await capture("-patron-ending")
	var claims = model.state.claims.duplicate()
	for id in fixture.rivals:
		before = game.money
		game.challenge.state.phase = "free"
		model.state.locked = false
		game.challenge_view.start(id)
		check(game.money == before + (0 if id in claims else int(fixture.investment)), "each rival investment only once: " + id)
		if id not in claims: claims.append(id)
		check(game.last_save_ok, "continuing rounds serialize previous companion endings")
	check(model.state.claims.size() == fixture.rivals.size(), "six unique rival claims max")
	for family in game.tiers: game.tiers[family] = game.config.base_tiers[family].size() - 1
	game.challenge.state.phase = "free"
	model.state.locked = false
	game.challenge_view.start(fixture.rivals[0])
	check(model.state.branch == "net", "full inherited upgrades select alternative at D0")
	game.tiers[fixture.family] = 0
	model.prepare(game)
	check(model.state.branch == "net", "branch stays locked throughout round")
	active()
	model.state.valid_by_day[str(game.day)] = int(fixture.rich_valid)
	game.challenge.state.stats.net = float(fixture.alt_net)
	check(model.achieved(game.challenge), "alternative uses operating net with required valid orders")
	game.challenge.state.stats.net = float(fixture.alt_net) - 1
	check(not model.achieved(game.challenge), "investment never fills alternative net gap")
	# A fresh round is not blocked by failing an optional companion goal.
	begin("merchant")
	active()
	win()
	check(model.state.outcome == "ordinary" and game.challenge.won(), "missing companion goals do not block rival victory")
	game.challenge_view.choose_companion(fixture.rivals[1])
	check(game.last_save_ok and model.state.pending_rival == fixture.rivals[1], "pending next-round companion selection saves")
	check(game._load_game(fixture.save_path) and game.screen == "selection", "reload resumes pending companion selection")
	var selector = game.page.get_child(0)
	check(selector.seats.size() == fixture.ids.size() and selector.seats.all(func(seat): return not seat.disabled), "five selectable seats without blanks")
	selector.select(fixture.ids.find("banker"))
	selector.action.pressed.emit()
	check(game.companion.id == "banker" and model.state.locked and model.valid_orders() == 0, "new round can switch companion and clears prior stats")
	check(not game.challenge.state.retry.is_empty() and game.last_save_ok, "switched round has valid retry snapshot")
	var locked_id = game.companion.id
	game.challenge_view.choose_companion(fixture.rivals[0])
	game.challenge_view.start(fixture.rivals[0])
	check(game.companion.id == locked_id and model.state.pending_rival.is_empty(), "round cannot change companion or restart through selection while locked")
	var snapshot = game._snapshot("preparation")
	for key in ["locked", "claims", "interest_days", "upgrade_records"]:
		var bad = snapshot.duplicate(true)
		bad.run.companion_progress[key] = null
		check(game.save_schema.decode(bad).is_empty(), "reject malformed companion state: " + key)
	var bad = snapshot.duplicate(true)
	bad.run.companion_progress.id = "merchant"
	check(game.save_schema.decode(bad).is_empty(), "reject mismatched locked identity")
	bad = snapshot.duplicate(true)
	bad.run.stock_ledger.batches[fixture.family] = [{"ml": 1, "unit_cost": 1, "merchant_discount": "yes"}]
	check(game.save_schema.decode(bad).is_empty(), "reject invalid batch provenance type")
	begin("judge")
	var legacy = game._snapshot("preparation")
	legacy.run.erase("companion_progress")
	legacy.run.challenge.retry.run.erase("companion_progress")
	check(not game.save_schema.decode(legacy).is_empty(), "old v8 judge/pope saves remain readable without invented history")
	# 42 production nights: actual FIFO, scoring, last-customer interest, D14 freeze,
	# order-start snapshots and reloads. Generous cash tests logic, not game balance.
	for id in fixture.integration_ids:
		begin(id)
		game.money = int(fixture.cash)
		for name in game.stock: game.stock[name] = 0.0
		game.stock_ledger.reset(game.stock)
		if id == "patron":
			game._buy_tier(fixture.family)
			game._buy_tier(fixture.family)
			game._buy_tier(fixture.second_family)
			game._buy_equipment()
		purchase_for_recipe(game._find_recipe(fixture.rotation[0]))
		game._finish_preparation()
		for relative in range(1, int(game.challenge.rules.days) + 1):
			var recipe: Dictionary = game._find_recipe(fixture.rotation[(relative - 1) % fixture.rotation.size()])
			game.stock_ledger.new_day()
			game.day_income = 0
			game.day_consumable_budget = 0.0
			purchase_for_recipe(recipe)
			game.promotion = recipe
			game.queue = []
			game.guest_index = 0
			game.day_served = 0
			game.day_success = 0
			for index in int(fixture.orders_per_day): game.queue.append({"recipe_id": recipe.id, "customer_index": int(fixture.integration_customer)})
			game.challenge.register_day(game.day, game.queue.size())
			for index in game.queue.size():
				game._start_guest()
				serve_real_order()
				check(game.last_save_ok, "real order checkpoint saves: " + id)
			check(model.valid_orders() == relative * int(fixture.orders_per_day), "production settlement counts each valid order once: " + id)
			check(game._load_game(fixture.save_path), "real last-order checkpoint reloads: " + id)
			if relative < int(game.challenge.rules.days):
				game._next_day()
				game.scene_transition.cancel()
			await process_frame
		print("REAL COMPANION ", id, " valid=", game.challenge.state.stats.valid, " net=", game.challenge.state.stats.net, " outcome=", model.state.outcome)
		check(game.challenge.state.phase == "result" and game.challenge.won(), "real D14 freezes a winning rival result: " + id)
		check(model.state.outcome == "success", "real D14 reaches companion ending: " + id)
		if id == "banker": check(model.state.interest_days.size() == int(game.challenge.rules.days), "D1-D14 interest recorded once on all fourteen nights")
		game.challenge_view.result()
		await capture("-real-ending-" + id)
	begin("judge")
	for size in fixture.windows:
		root.size = Vector2i(size[0], size[1])
		game._show_companion_selection()
		selector = game.page.get_child(0)
		for index in fixture.ids.size():
			selector.select(index)
			await capture("-selection-" + str(size[0]) + "-" + fixture.ids[index])
		game.challenge.state.phase = "free"
		model.state.locked = false
		game.challenge_view.choose_companion(fixture.rivals[0], false)
		await capture("-round-selection-" + str(size[0]))
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real user file protected")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.queue_free()
	await frames()
	print("COMPANIONS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
