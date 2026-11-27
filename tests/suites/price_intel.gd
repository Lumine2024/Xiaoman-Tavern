extends SceneTree
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

func record(model, id: String) -> Dictionary:
	return {"id": id, "day": int(fixture.notice_day), "due": int(fixture.notice_day) + int(model.rules.events[id].get("delay_days", 0)), "heard": false, "resolved": false, "mitigation": "", "action_day": 0}

func offered(model, speaker: String, day: int) -> Dictionary:
	for seed_value in fixture.disclosure_seeds:
		var rng = RandomNumberGenerator.new()
		rng.seed = int(seed_value)
		var order = {}
		model.offer(speaker, order, day, rng)
		if int(order.event_offer) >= 0: return order
	return {}

func capture(label: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/price_intel_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	var model = load("res://scripts/game/daily_events.gd").new()
	check(model.configuration_errors().is_empty(), "next-day rules and three message phases validate")
	var recipes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	var price_count = 0
	for id in model.rules.events:
		var definition: Dictionary = model.rules.events[id]
		if definition.kind != "price": continue
		price_count += 1
		model.state = {"generated_days": [int(fixture.notice_day)], "records": [record(model, id)], "heard_claims": []}
		var due = int(model.state.records[0].due)
		var expiry = due + int(definition.duration_days)
		check(due == int(fixture.notice_day) + 1, "all price changes wait until tomorrow: " + id)
		check(model.price_factor(definition.ingredient, int(fixture.notice_day)) == 1.0, "no economic effect on notice day: " + id)
		check(is_equal_approx(model.price_factor(definition.ingredient, due), float(definition.multiplier)), "change starts on due day: " + id)
		check(is_equal_approx(model.price_factor(definition.ingredient, expiry - 1), float(definition.multiplier)) and model.price_factor(definition.ingredient, expiry) == 1.0, "duration counts from due day: " + id)
		for recipe in recipes:
			if not (recipe.ingredients + recipe.topup).any(func(item): return item.name == definition.ingredient): continue
			check(model.drink_factor(recipe, int(fixture.notice_day)) == 1.0 and is_equal_approx(model.drink_factor(recipe, due), float(definition.multiplier)), "related drink waits until due day: " + id + "/" + recipe.id)
		for speaker in definition.customer_ids:
			var pending = offered(model, speaker, int(fixture.notice_day))
			var current = offered(model, speaker, due)
			var historical = offered(model, speaker, expiry)
			check(not pending.is_empty() and pending.message_text.contains(fixture.advance_word) and pending.message_text.contains(definition.ingredient), "forecast names ingredient and tomorrow: " + id)
			check(not current.is_empty() and current.message_text in model.pools.ongoing[id][speaker] and not current.message_text.contains(fixture.advance_word), "late disclosure never pretends the rise is tomorrow: " + id)
			check(not historical.is_empty() and historical.message_text in model.pools.history[id][speaker] and historical.message_text.contains(fixture.expired_word), "expired disclosure says the window ended: " + id)
			for word in fixture.forbidden_words:
				# Ingredient names may themselves contain a currency character, e.g. 金酒.
				check(not pending.message_text.replace(definition.ingredient, "").contains(word), "prose has no amount or multiplier: " + id)
		var rng = RandomNumberGenerator.new()
		rng.seed = int(fixture.seed)
		var cached = offered(model, definition.customer_ids[0], int(fixture.notice_day))
		var unchanged = cached.duplicate(true)
		var rng_before = rng.state
		model.offer(definition.customer_ids[0], cached, int(fixture.notice_day), rng)
		check(cached == unchanged and rng.state == rng_before, "saved order text and RNG are not rerolled")
	check(price_count == int(fixture.price_event_count), "all catalog price events covered")
	for id in fixture.authored_trends:
		var speaker: String = fixture.authored_trends[id]
		model.state.records = [record(model, id)]
		var text = offered(model, speaker, int(fixture.notice_day))
		var recipe_name: String = recipes.filter(func(recipe): return recipe.id == model.rules.events[id].recipe_id)[0].name
		check(not text.is_empty() and text.message_text in model.pools.effective[id][speaker] and text.message_text.contains(recipe_name), "authored trend voice and explicit drink: " + id)
	var original_delay = model.rules.events[fixture.copy_event].delay_days
	model.rules.events[fixture.copy_event].delay_days = 0
	check(not model.configuration_errors().is_empty(), "same-day price configuration is rejected")
	model.rules.events[fixture.copy_event].delay_days = original_delay
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game._begin_rival_run(game.config.companions[0], fixture.rival)
	game.set_process(false)
	game._finish_preparation()
	game._select_counter_card(fixture.card)
	game.promotion = game._find_recipe(fixture.promotion)
	game.queue = [{"recipe_id": fixture.promotion, "customer_index": 0}]
	game.guest_index = game.queue.size()
	game.day_served = game.queue.size()
	game.money = int(fixture.cash)
	for ingredient in game.stock: game.stock[ingredient] = float(fixture.stock_ml)
	game.stock_ledger.reset(game.stock)
	var events = game.competition.daily_events
	events.state = {"generated_days": [int(fixture.notice_day)], "records": [], "heard_claims": [fixture.claim]}
	for id in fixture.display_events: events.state.records.append(record(events, id))
	game.show_shop()
	var shop = game.page.get_node("ShopShelves")
	shop.names = fixture.display_names.duplicate()
	shop.page_index = 0
	shop._render()
	check(shop.products.values().all(func(view): return not view.price_tag.text.contains("[s]")), "tomorrow's prices have no badge today")
	await capture("-notice-day")
	game.day = int(fixture.notice_day) + 1
	game.competition.state.markets[str(game.day)] = {"day": game.day, "variation": float(fixture.market_variation), "outages": {}, "order": [], "substitutes": {}}
	game.show_shop()
	shop = game.page.get_node("ShopShelves")
	shop.names = fixture.display_names.duplicate()
	shop.page_index = 0
	shop._render()
	var rise = shop.products[fixture.rise_name].price_tag
	var fall = shop.products[fixture.fall_name].price_tag
	check(rise.text.contains("[s]") and rise.text.contains(game.interface.shop.price_highlight.up_arrow) and rise.text.contains(game.interface.shop.price_highlight.up_color), "today rise has crossed price, new price, red up arrow")
	check(fall.text.contains("[s]") and fall.text.contains(game.interface.shop.price_highlight.down_arrow) and fall.text.contains(game.interface.shop.price_highlight.down_color), "today fall has crossed price, new price, green down arrow")
	check(not shop.products[fixture.normal_name].price_tag.text.contains("[s]"), "unaffected product stays plain despite ordinary market variation")
	for size in fixture.windows:
		root.size = Vector2i(size[0], size[1])
		await capture("-active-" + str(size[0]))
		for view in shop.products.values(): check(view.price_tag.get_content_height() <= view.price_tag.size.y, "price label fits product card")
	var button: Button = shop.products[fixture.fall_name].actions[0].button
	var price_before = game._stock_price(fixture.fall_name)
	var cash_before = game.money
	button.grab_focus()
	button.pressed.emit()
	check(game.last_save_ok, "real shop purchase has a valid saved state")
	check(game.money == cash_before - price_before and fall.get_parsed_text().contains(str(price_before)), "displayed discounted price equals actual purchase charge")
	check(shop.products[fixture.fall_name].price_tag == fall and root.gui_get_focus_owner() == button, "price refresh retains controls and focus")
	# A lock removes the event's effect on this actual pack, so it must not display a false discount.
	game.competition.state.locks[str(game.day)] = {"packs": {fixture.fall_name: 1}, "used": {}, "base_prices": {fixture.fall_name: game.pricing.pack_price(fixture.fall_name, game.tiers)}}
	shop.refresh()
	check(not fall.text.contains("[s]"), "locked pack does not claim a nonexistent price change")
	game.competition.state.locks = {}
	game.competition.begin_day(game.promotion, game.day, game.tiers)
	var captain_index = game.customers.map(func(customer): return customer.story_id).find(fixture.captain)
	game.queue = [{"recipe_id": fixture.recipe, "customer_index": captain_index}]
	game.guest_index = 0
	game.day_served = 0
	game._start_guest()
	game.brew.stage = 2
	game._advance_dialogue(0)
	check(game.dialogue == 1 and game._market_dialogue(), "second segment is market information")
	game._verify_market_claim(fixture.claim)
	check(game.queue[0].verification_text == events.pools.claims[fixture.claim].up, "verification reads today's active price in segment two")
	var market_text = events.message(game.queue[0], game.day)
	check(game.dialogue_box.find_children("*", "Label", true, false).any(func(label): return label.text == market_text), "second segment displays actual market message")
	await capture("-segment-two")
	game._advance_dialogue(0)
	check(game.dialogue == 2 and game.rumors.any(func(text): return text.contains(market_text)), "market acknowledgement records it before third segment")
	game.brew.stage = 4
	game._draw_dialogue()
	check(game.guest.get("longline", false) and game.dialogue_box.find_children("*", "Label", true, false).any(func(label): return label.text == game.guest.topic), "captain longline survives in third segment")
	check(not game.dialogue_box.find_children("*", "Label", true, false).any(func(label): return label.text == market_text), "third segment does not repeat market information")
	check(not game.guest.rumor.is_empty() and game.dialogue_box.find_children("*", "Label", true, false).any(func(label): return label.text == game.competition.summary(game.day)), "third segment shows the selected rival's actual notice")
	await capture("-segment-three")
	game._advance_dialogue(0)
	check(game.dialogue == 3 and int(game.guest.longline_answer) == 0, "third-segment answer is preserved for longline completion")
	check(game._save("reception"), "integration snapshot validates before reload")
	var queue_before = game.queue.duplicate(true)
	var records_before = events.state.duplicate(true)
	var rng_before = game.rng.state
	check(game._load_game(), "integration save reloads")
	check(events.state == records_before, "reload preserves event due dates and acknowledgement")
	check(game.queue[0].message_text == queue_before[0].message_text and game.queue[0].event_offer == queue_before[0].event_offer and game.queue[0].verification_text == queue_before[0].verification_text, "reload preserves chosen message, offer and verification")
	check(game.rng.state == rng_before, "reload never resamples business RNG")
	game.day = int(fixture.notice_day)
	check(events.verify(fixture.claim, fixture.captain, game.day) == events.pools.claims[fixture.claim].upcoming, "captain distinguishes tomorrow rise from today's normal price")
	game.day += 1 + int(events.rules.events[fixture.copy_event].duration_days)
	game.show_shop()
	shop = game.page.get_node("ShopShelves")
	shop.names = fixture.display_names.duplicate()
	shop.page_index = 0
	shop._render()
	check(shop.products.values().all(func(view): return not view.price_tag.text.contains("[s]")), "expired prices return to ordinary labels")
	for path in protected: check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real user file protected: " + path)
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("PRICE INTEL: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(1 if failures else 0)
