extends RefCounted
## v0.4 narrative pilot for new runs; v1.1 economics retained for migrated saves.
var rules: Dictionary
var data: Dictionary
var content: Dictionary
var state: Dictionary
var events: Dictionary
var catalog: Dictionary
var daily_events = preload("res://scripts/game/daily_events.gd").new()
var street = preload("res://scripts/competition/street_rival.gd").new()
var round_offset = 0
var ingredient_aliases: Dictionary = {}
var modern_mode = false

func event_recipe(recipe: Dictionary) -> Dictionary:
	var result = recipe.duplicate(true)
	for item in result.ingredients + result.topup: item.name = ingredient_aliases.get(item.name, item.name)
	return result

func round_day(day: int) -> int:
	return day - round_offset

func _init(presentation: Dictionary) -> void:
	rules = preload("res://scripts/game/resource_data.gd").read("res://data/rival_rules.json")
	content = preload("res://scripts/game/resource_data.gd").read("res://data/rival_content.json")
	catalog = preload("res://scripts/game/resource_data.gd").read("res://data".path_join(rules.pricing_dependency.path).simplify_path())
	data = presentation.duplicate(true)
	data.rules = {"rumor_day": rules.timeline.rumor_day, "pressure_day": rules.timeline.pressure_day, "shift_day": rules.timeline.escalation_day, "ending_day": rules.timeline.ending_day, "max_auxiliary_shortages": rules.limits.max_outages_total}
	events = preload("res://scripts/game/resource_data.gd").read("res://data/special_events.json")
	reset("")

func reset(id: String) -> void:
	round_offset = 0
	street.challenge_mode = false
	ingredient_aliases = {}
	modern_mode = false
	state = {"rules_version": rules.rules_version, "rival": id, "strategy": "hold", "last_policy": "hold", "follow_news_day": 0, "reputation": 0, "last_open_day": 0, "closed_day": 0, "last_promotion": "", "promotion_streak": 0, "history": [], "day_valid": 0, "regular_correct": true, "today_traffic": 0, "next_traffic": 0, "traffic_sources": {}, "market_day": 0, "markets": {}, "shortages": {}, "next_shortages": {}, "fluctuation": 1.0, "today_event": {}, "seen_events": [], "informed": [], "scheduled": [], "today_effects": [], "forecast": "", "forecasts": {}, "hold_days": 0, "correct_days": 0, "compliant_days": 0, "premium_served": 0, "premium_all_compliant": true, "regular_visits": {}, "reserve_regular": false, "favorable_choices": 0, "cooperation_days": [], "licensed_recipes": [], "ending": "", "pending_ending": {}, "ending_ready": [], "reward_granted": false, "permanent_traffic": 0, "rare_unlock_slots": 0, "locks": {}, "lock_days": [], "credit_limit": 0, "credit_used": 0, "credit_due_day": 0, "last_event_effect_day": 0, "last_reputation_check": 0, "today_rewards": [], "receipts": {}, "blocked_promotion": "", "voluntary_skip_days": []}

	state.street = street.fresh()
	daily_events.state = {"generated_days": [], "records": [], "heard_claims": []}

func narrative() -> bool:
	return state.get("street", {}).get("enabled", false)

func rival() -> Dictionary:
	return data.rivals.get(state.rival, {})

func profile() -> Dictionary:
	return rules.rivals.get(state.rival, {})

func active(day: int) -> bool:
	return (state.street.ending.is_empty() and state.rival == "karn" and round_day(day) >= int(street.data.numbers.pressure_day)) if narrative() else (not profile().is_empty() and state.ending.is_empty() and day >= int(rules.timeline.pressure_day))

func dependency_ok() -> bool:
	var event_errors = daily_events.configuration_errors()
	if not event_errors.is_empty():
		push_error("; ".join(event_errors))
		return false
	if catalog.get("catalog_version") != rules.pricing_dependency.catalog_version or rules.pricing_dependency.price_source != "pricing.calculate_price":
		return false
	var value = catalog
	for key in str(rules.rivals.bella.counterplay.collaboration_price_ref).split("."):
		if not value is Dictionary or not value.has(key):
			return false
		value = value[key]
	return (value is float or value is int) and float(value) >= 0

static func money(value: float) -> int:
	return int(floorf(value + 0.5))

func market(day: int) -> Dictionary:
	return state.markets.get(str(day), {"day": day, "variation": 0.0, "outages": {}, "order": [], "substitutes": {}})

func sold_out(name: String, day: int) -> bool:
	return int(market(day).outages.get(name, 0)) > day

func procurement_factor(name: String, day: int, tiers: Dictionary, emergency = false) -> float:
	if narrative(): return 1.0
	if not active(day):
		return 1.0
	var family = catalog.ingredients[name].family
	if state.rival == "duren" and family == null:
		return float(profile().emergency_procurement_multiplier if emergency else profile().procurement_multiplier)
	if state.rival == "viola" and family != null and int(tiers.get(family, 0)) + 1 >= int(profile().procurement_min_base_tier):
		return float(profile().procurement_multiplier)
	return 1.0

func package_price(name: String, base: float, day: int, tiers: Dictionary, emergency = false, include_daily_events = true) -> int:
	var amount = base * (1.0 + float(market(day).variation)) * procurement_factor(name, day, tiers, emergency)
	if include_daily_events: amount *= daily_events.price_factor(str(ingredient_aliases.get(name, name)), day)
	return maxi(1, money(amount)) if base > 0 else 0

func can_emergency(name: String, day: int) -> bool:
	return active(day) and state.rival == "duren" and catalog.ingredients[name].family == null

func available_policies(recipe: Dictionary, day: int) -> Array:
	if narrative(): return ["hold"]
	if state.rival.is_empty():
		return ["hold"]
	if active(day) and state.rival == "karn" and recipe.id.begins_with(profile().price_scope + "-"):
		return ["hold", "follow"]
	return ["hold", "premium"]

func quote(recipe: Dictionary, base: Dictionary, day: int, tiers: Dictionary, promoted_band = "") -> Dictionary:
	if narrative() or modern_mode:
		var card = street.effective(state.street, round_day(day))
		var price = int(base.price)
		if card == "follow" and state.rival == "karn" and recipe.id in street.data.price_recipe_ids:
			price = mini(price, int(rules.rivals.karn.competitor_initial_quote))
		price = money(price * daily_events.drink_factor(event_recipe(recipe), day))
		return {"price": price, "standard_price": int(base.price), "policy": "hold", "band": recipe.id.split("-")[0], "day": day, "rival_id": state.rival, "rules_version": rules.rules_version, "active": active(day), "tiers": tiers.duplicate(true), "negative_sources": {}, "positive_multiplier": 1.0, "premium_tip": 1.0, "viola": {}, "legal_substitute": false, "margin_loss": 1.0 - (1.0 - float(street.data.cards.get(card, {}).get("margin_loss", 0))) * (1.0 - daily_events.margin_loss(day))}
	var band: String = recipe.id.split("-")[0]
	var affected = band == (state.last_promotion.split("-")[0] if promoted_band.is_empty() else promoted_band)
	var policy: String = state.strategy if affected else "hold"
	var p = int(base.price)
	if policy == "follow" and active(day) and state.rival == "karn" and band == profile().price_scope:
		p = mini(p, int(profile().competitor_initial_quote))
	elif policy == "premium":
		p = money(p * float(rules.menu.premium_price_multiplier))
	var negatives: Dictionary = {}
	var positive = 1.0
	var enabled = active(day)
	if enabled and state.rival == "bella":
		if recipe.id in rules.menu.classic_recipe_ids:
			negatives.classic = float(profile().classic_revenue_multiplier)
		if recipe.id == state.last_promotion and int(state.promotion_streak) >= int(profile().copy_offer_start_streak_day):
			negatives.copy = float(profile().copied_promotion_revenue_multiplier)
	if enabled and state.rival == "viola" and recipe.id in rules.menu.classic_recipe_ids:
		positive = float(profile().classic_revenue_multiplier)
	return {"price": p, "standard_price": int(base.price), "policy": policy, "band": band, "day": day, "rival_id": state.rival, "rules_version": rules.rules_version, "active": enabled, "tiers": tiers.duplicate(true), "negative_sources": negatives, "positive_multiplier": positive, "premium_tip": float(rules.menu.premium_tip_multiplier) if policy == "premium" else 1.0, "viola": profile().duplicate(true) if enabled and state.rival == "viola" else {}, "legal_substitute": false}

func recipe_families(recipe: Dictionary) -> Array:
	var families: Array = []
	for item in recipe.ingredients + recipe.topup:
		var family = catalog.ingredients[item.name].family
		if family != null and family not in families:
			families.append(family)
	return families

func modifiers(quoted: Dictionary, recipe: Dictionary, wrong_cup: bool, wrong_ice: bool, tiers: Dictionary) -> Dictionary:
	var negatives: Dictionary = quoted.negative_sources.duplicate(true)
	var tip = float(quoted.premium_tip)
	var excluded_cup = false
	var low_tier = false
	var v: Dictionary = quoted.viola
	if not v.is_empty() and quoted.band == v.premium_band:
		for family in recipe_families(recipe):
			if int(tiers.get(family, 0)) + 1 < int(v.min_base_tier):
				low_tier = true
		if wrong_cup:
			negatives.cup = float(v.wrong_cup_revenue_multiplier)
			excluded_cup = true
		if low_tier:
			negatives.tier = float(v.low_tier_revenue_multiplier)
		if not wrong_cup and not low_tier:
			tip *= float(v.compliant_tip_multiplier)
	if quoted.get("legal_substitute", false) and not (quoted.rival_id == "duren" and quoted.band == rules.rivals.duren.exempt_shortage_revenue_band):
		negatives.substitute = float(rules.market.substitute_revenue_multiplier)
	var negative = 1.0
	for multiplier in negatives.values():
		negative = minf(negative, float(multiplier))
	negative = maxf(1.0 - float(rules.limits.max_rival_discount_ratio), negative)
	return {"revenue_multiplier": negative * float(quoted.positive_multiplier), "tip_multiplier": tip, "exclude_cup": excluded_cup, "low_tier": low_tier, "compliant": not wrong_cup and not wrong_ice and not low_tier, "negative_sources": negatives}

func traffic_delta(recipe: Dictionary, day: int, standard_price: float = -1) -> int:
	if modern_mode and not narrative(): return clampi(int(state.today_traffic) + daily_events.traffic(day, event_recipe(recipe)), -int(street.data.numbers.traffic_cap), int(street.data.numbers.traffic_cap))
	if narrative(): return clampi(street.traffic(state.street, state, recipe, round_day(day)) + int(state.today_traffic) + daily_events.traffic(day, event_recipe(recipe)), -int(street.data.numbers.traffic_cap), int(street.data.numbers.traffic_cap))
	var sources: Dictionary = state.traffic_sources.duplicate(true)
	sources.dialogue = int(state.today_traffic)
	sources.ending = int(state.permanent_traffic)
	if state.strategy == "premium":
		sources.policy = int(rules.menu.premium_traffic_delta)
	if active(day):
		if state.rival == "karn" and recipe.id.begins_with(profile().price_scope + "-") and state.strategy != "follow" and standard_price > float(profile().competitor_initial_quote):
			sources.rival = int(profile().over_cap_traffic_delta)
		if state.rival == "marta":
			var missed = false
			for id in content.regular_customer_ids:
				var absent = state.history.filter(func(record): return int(record.day) > int(state.regular_visits.get(id, day)) and int(record.day) < day).size()
				if absent >= int(profile().missed_regular_days):
					missed = true
			if recipe.ice == profile().cold_recipe_ice or missed:
				sources.rival = int(profile().cold_promotion_traffic_delta)
	var total = 0
	for value in sources.values():
		total += int(value)
	return clampi(total, -int(rules.limits.traffic_loss_per_day), int(rules.limits.traffic_gain_per_day))

func promotion_factor(_recipe: Dictionary, _day: int) -> float:
	return 1.0

func apply_pending_ending(day: int) -> void:
	if not state.pending_ending.is_empty() and int(state.pending_ending.day) <= day and state.ending.is_empty():
		state.ending = state.pending_ending.kind
		state.pending_ending = {}
		state.scheduled.clear()
		state.today_effects.clear()
		for key in state.markets:
			if int(key) >= day:
				state.markets[key].outages.clear()
				state.markets[key].variation = 0.0
		if not state.reward_granted:
			state.reward_granted = true
			state.permanent_traffic = int(profile().counterplay.get("permanent_traffic_delta", 0))
			state.rare_unlock_slots = int(profile().counterplay.get("rare_base_unlock_count", 0))

func begin_day(recipe: Dictionary, day: int, tiers: Dictionary = {}) -> void:
	if int(state.last_open_day) == day:
		return
	apply_pending_ending(day)
	state.last_open_day = day
	state.today_traffic = int(state.next_traffic)
	state.traffic_sources = {}
	state.next_traffic = 0
	state.day_valid = 0
	state.regular_correct = true
	if active(day) and state.rival == "olga" and state.strategy != state.last_policy:
		state.follow_news_day = day + int(profile().follow_delay_days)
	state.last_policy = state.strategy
	state.premium_served = 0
	state.premium_all_compliant = true
	state.today_rewards = []
	state.promotion_streak = int(state.promotion_streak) + 1 if state.last_promotion == recipe.id else 1
	state.last_promotion = recipe.id
	state.history.append({"day": day, "recipe_id": recipe.id})
	state.shortages = market(day).outages.duplicate(true)
	state.today_event = {}
	if narrative():
		street.begin(state.street, state, recipe, round_day(day), recipe_families(recipe).any(func(family): return int(tiers.get(family, 0)) + 1 >= int(street.data.numbers.immune_tier)))
		if street.effective(state.street, round_day(day)) == "attract": state.reputation += int(street.data.cards.attract.reputation)
		return
	if active(day) and state.rival == "viola" and day == int(profile().reputation_check_day) and int(state.last_reputation_check) != day:
		state.last_reputation_check = day
		if int(state.reputation) < int(profile().reputation_threshold):
			state.reputation += int(profile().low_reputation_delta)
	if active(day):
		var window = (day - int(rules.dialogue.first_special_day)) % int(rules.dialogue.special_window_days)
		var candidates: Array = profile().exclusive_events if window == 0 else profile().shared_events
		for id in candidates:
			if id not in state.seen_events:
				var text = events.get(id, {}).get("text", rival().summary)
				for event in rival().events:
					if event.id == id:
						text = event.text
				state.today_event = {"id": id, "text": text.format({"ingredient": recipe.ingredients[0].name})}
				state.seen_events.append(id)
				break

func shift_queue(queue: Array, customers: Array, day: int) -> void:
	if narrative(): return
	if not active(day) or day < int(profile().get("crowd_start_day", rules.timeline.escalation_day)):
		return
	for tag in profile().get("crowd_segment_priority", []):
		var matching: Array = []
		for index in range(customers.size()):
			var guest: Dictionary = customers[index]
			if guest.get("race", "") == tag or guest.role == tag or tag in content.customer_tags.get(guest.get("id", guest.name), []):
				matching.append(index)
		if not matching.is_empty():
			for index in range(queue.size() - 1, -1, -1):
				if int(queue[index].customer_index) not in matching:
					queue[index].customer_index = matching[day % matching.size()]
					return
			return

func outage_probability(name: String, day: int, tiers: Dictionary) -> float:
	if not active(day):
		return 0.0
	var family = catalog.ingredients[name].family
	var rate = float(rules.market.base_aux_outage_probability if family == null else rules.market.base_spirit_outage_probability)
	var delta = 0.0
	match state.rival:
		"bella": delta = float(profile().outage_delta_pp) if name in rules.menu.seasonal_fruits else 0.0
		"marta": delta = float(profile().outage_delta_pp) if family == null else 0.0
		"duren": delta = float(profile().outage_delta_pp) if family == null and day >= int(profile().outage_pressure_day) else 0.0
		"viola": delta = float(profile().outage_delta_pp) if family != null and int(tiers.get(family, 0)) + 1 >= int(profile().outage_min_base_tier) else 0.0
	return clampf(rate + delta / 100.0, 0, 1)

func prepare_market(day: int, _catalog: Dictionary, tiers: Dictionary, recipes: Array, stock: Dictionary, rng: RandomNumberGenerator) -> void:
	if narrative() or modern_mode:
		for market_day in [day, day + 1]:
			if not state.markets.has(str(market_day)): state.markets[str(market_day)] = {"day": market_day, "variation": 0.0, "outages": {}, "order": [], "substitutes": {}}
		return
	var next_day = day + 1
	if not state.markets.has(str(day)):
		state.markets[str(day)] = {"day": day, "variation": 0.0, "outages": {}, "order": [], "substitutes": {}}
	if not state.markets.has(str(next_day)):
		var outages = {}
		for name in market(day).outages:
			if int(market(day).outages[name]) > next_day:
				outages[name] = int(market(day).outages[name])
		var order = stock.keys()
		for index in range(order.size() - 1, 0, -1):
			var swap = rng.randi_range(0, index)
			var value = order[index]
			order[index] = order[swap]
			order[swap] = value
		if active(next_day) and state.rival == "duren" and next_day >= int(profile().outage_pressure_day):
			var priority: Array = []
			for recipe in recipes:
				if recipe.id == state.last_promotion:
					for item in recipe.ingredients + recipe.topup:
						if catalog.ingredients[item.name].family == null and item.name not in priority:
							priority.append(item.name)
			order = order.filter(func(name): return name in priority) + order.filter(func(name): return name not in priority)
		var variation = rng.randf_range(float(rules.market.daily_variation_min), float(rules.market.daily_variation_max)) if active(next_day) else 0.0
		for name in order:
			if outages.size() >= int(rules.limits.max_outages_total):
				break
			if outages.has(name) or rng.randf() >= outage_probability(name, next_day, tiers):
				continue
			var duration = int(profile().outage_days) if state.rival == "duren" and next_day >= int(profile().outage_pressure_day) else int(rules.market.base_outage_days)
			outages[name] = next_day + duration
		var substitutes = {}
		for name in outages:
			for group in content.substitution_groups:
				if name in group and rng.randf() < float(profile().substitute_probability):
					substitutes[name] = group.filter(func(other): return other != name and not outages.has(other))
		state.markets[str(next_day)] = {"day": next_day, "variation": variation, "outages": outages, "order": order, "substitutes": substitutes}
	state.market_day = maxi(int(state.market_day), day)
	state.fluctuation = 1.0 + float(market(day).variation)
	state.next_shortages = market(next_day).outages.duplicate(true)
	if (active(day) or not state.ending.is_empty()) and state.rival == "olga" and not state.forecasts.has(str(next_day)):
		var forecast_rng = RandomNumberGenerator.new()
		forecast_rng.seed = int(rng.randi())
		var prediction = {"rising": float(market(next_day).variation) > 0, "shortage": not market(next_day).outages.is_empty(), "day": next_day}
		var reliability = float(profile().allied_forecast_reliability if not state.ending.is_empty() else profile().forecast_reliability)
		if forecast_rng.randf() >= reliability:
			var key = "rising" if forecast_rng.randi_range(0, 1) == 0 else "shortage"
			prediction[key] = not prediction[key]
		state.forecasts[str(next_day)] = prediction
	if state.forecasts.has(str(next_day)):
		var f: Dictionary = state.forecasts[str(next_day)]
		state.forecast = ("明日货价听来走高，" if f.rising else "明日货价听来回落，") + ("货源恐怕紧张。" if f.shortage else "货源听来平稳。")

func cooperation(day: int) -> void:
	if day not in state.cooperation_days:
		state.cooperation_days.append(day)
		state.favorable_choices += 1

func lock_service(day: int, packs: Dictionary, base_prices: Dictionary, cash: int) -> int:
	if state.rival != "olga" or not active(day) or day in state.lock_days or packs.is_empty():
		return -1
	var fee = int(profile().lock_service_fee_override)
	if cash < fee:
		return -1
	for name in packs:
		if not packs[name] is int or int(packs[name]) <= 0 or not base_prices.has(name):
			return -1
	state.lock_days.append(day)
	state.locks[str(day + int(profile().lock_days))] = {"packs": packs.duplicate(true), "base_prices": base_prices.duplicate(true), "used": {}}
	cooperation(day)
	_check_ready(day)
	return fee

func purchase_bill(name: String, packs: int, base: float, day: int, tiers: Dictionary, emergency = false, bulk = false, include_daily_events = true) -> Dictionary:
	if packs <= 0 or (sold_out(name, day) and not (emergency and can_emergency(name, day))):
		return {}
	var q = package_price(name, base, day, tiers, emergency, include_daily_events)
	var lock: Dictionary = state.locks.get(str(day), {})
	var locked = 0
	if not emergency and not lock.is_empty():
		locked = mini(packs, maxi(0, int(lock.packs.get(name, 0)) - int(lock.used.get(name, 0))))
	var locked_price = float(lock.get("base_prices", {}).get(name, base))
	var regular = (packs - locked) * q
	if bulk:
		regular = money(regular * float(rules.market.bulk_multiplier))
	var total = money(locked * locked_price + regular)
	return {"name": name, "packs": packs, "total": total, "locked": locked, "emergency": emergency, "unit_cost": float(total) / (packs * float(catalog.ingredients[name].pack_ml))}

func commit_purchase(bill: Dictionary, day: int) -> void:
	if int(bill.locked) > 0:
		var lock: Dictionary = state.locks[str(day)]
		lock.used[bill.name] = int(lock.used.get(bill.name, 0)) + int(bill.locked)
	if state.rival == "duren" and active(day):
		cooperation(day)

func license_recipe(recipe_id: String, day: int, cash: int) -> int:
	if state.rival != "bella" or not active(day) or not state.licensed_recipes.is_empty() or int(state.last_event_effect_day) == day or not catalog.recipes.has(recipe_id):
		return -1
	var reference = catalog
	for field in str(profile().counterplay.collaboration_price_ref).split("."):
		reference = reference[field]
	var fee = int(reference)
	if cash < fee:
		return -1
	state.licensed_recipes.append(recipe_id)
	state.reputation += int(profile().counterplay.collaboration_reputation_gain)
	state.last_event_effect_day = day
	cooperation(day)
	_check_ready(day)
	return fee

func open_credit(day: int) -> bool:
	if state.rival != "duren" or "R-07" not in state.informed or int(state.credit_limit) > 0 or int(state.last_event_effect_day) == day:
		return false
	state.credit_limit = int(profile().credit_advance)
	state.last_event_effect_day = day
	return true

func record_answer(choice: Dictionary) -> void:
	state.reputation += int(choice.get("reputation", 0))
	state.day_valid += 1 if choice.get("answer") == "valid" else 0
	state.next_traffic = maxi(int(state.next_traffic), int(choice.get("traffic", 0)))

func dialogue(day: int) -> Dictionary:
	if narrative(): return {}
	if rival().is_empty() or day < int(rules.timeline.rumor_day):
		return {}
	var lines: Array = rival().fingerprints
	var intel: String = state.today_event.get("text", rival().summary)
	if active(day) and state.rival == "olga" and day >= int(profile().leak_start_day) and (day - int(profile().leak_start_day))%int(profile().leak_repeat_days) == 0:
		intel = "奥尔加又把你的价目表卖给了别人。"
	if active(day) and state.rival == "olga" and day == int(state.follow_news_day):
		intel += "你调过的价已经传出去，对面隔了一日跟进了。"
	var answers: Array = []
	var names = ["empathy", "pragmatic", "side_with_rival"]
	for index in range(names.size()):
		var response: Dictionary = rules.dialogue.responses[names[index]]
		answers.append({"text": data.answers[index].text, "answer": "valid" if float(response.intel_fraction) == 1 else "cold", "reputation": response.reputation, "tip": response.tip_multiplier, "traffic": response.next_day_traffic, "intel_fraction": response.intel_fraction})
	return {"topic": lines[(day - int(rules.timeline.rumor_day))%lines.size()], "rumor": intel, "choices": answers}

func hear_intel(_day: int, _customer: int, _recipe: String) -> void:
	if not state.today_event.is_empty() and state.today_event.id not in state.informed:
		state.informed.append(state.today_event.id)

func record_service(quoted: Dictionary, compliance: Dictionary, complete: bool, regular_id: String, correct_dialogue: bool, day: int, recipe: Dictionary) -> void:
	if narrative(): return
	if regular_id in content.regular_customer_ids:
		state.regular_visits[regular_id] = day
		if not correct_dialogue:
			state.regular_correct = false
	if quoted.band == rules.rivals.viola.premium_band:
		state.premium_served += 1 if complete else 0
		state.premium_all_compliant = state.premium_all_compliant and complete and bool(compliance.compliant)
	if complete and quoted.policy == "premium" and "premium" not in state.today_rewards:
		state.today_rewards.append("premium")
		state.reputation += int(rules.menu.premium_reputation_gain)
	if complete and quoted.policy == "hold" and "defend" not in state.today_rewards:
		var upgraded = recipe_families(recipe).any(func(family): return int(quoted.tiers.get(family, 0)) > 0)
		if upgraded:
			state.today_rewards.append("defend")
			state.reputation += int(rules.menu.defend_reputation_gain)

func close_day(recipe: Dictionary, day: int) -> void:
	if int(state.closed_day) == day:
		return
	state.closed_day = day
	if narrative():
		street.close(state.street, state, recipe, round_day(day))
		return
	if active(day):
		if state.rival == "karn":
			state.hold_days = int(state.hold_days) + 1 if recipe.id.begins_with("H-") and state.strategy != "follow" else 0
		elif state.rival == "viola" and day not in state.voluntary_skip_days:
			state.compliant_days = int(state.compliant_days) + 1 if int(state.premium_served) >= int(profile().counterplay.min_premium_serves_per_day) and state.premium_all_compliant else 0
		elif state.rival == "marta" and not content.regular_customer_ids.is_empty():
			var visited = content.regular_customer_ids.any(func(id): return int(state.regular_visits.get(id, 0)) == day)
			state.correct_days = int(state.correct_days) + 1 if visited and state.reserve_regular and state.regular_correct else 0
	_check_ready(day)

func _check_ready(day: int) -> void:
	if narrative(): return
	if not state.ending.is_empty() or profile().is_empty():
		return
	var ready = false
	match state.rival:
		"karn": ready = int(state.hold_days) >= int(profile().counterplay.hard_promotion_without_match_streak_days)
		"bella":
			var unique = {}
			for record in state.history:
				if int(record.day) > day - int(profile().counterplay.seasonal_window_days):
					var recipe: Dictionary = catalog.recipes[record.recipe_id]
					if (recipe.ingredients + recipe.topup).any(func(item): return item.name in rules.menu.seasonal_fruits):
						unique[record.recipe_id] = true
			ready = not state.licensed_recipes.is_empty() or unique.size() >= int(profile().counterplay.seasonal_distinct_promotions)
		"marta": ready = int(state.correct_days) >= int(profile().counterplay.regular_reservation_and_correct_dialogue_streak_days)
		"duren": ready = state.receipts.get("S-08", "") == profile().counterplay.required_outcome
		"viola": ready = int(state.compliant_days) >= int(profile().counterplay.fully_compliant_streak_days)
		"olga": ready = state.lock_days.size() >= int(profile().counterplay.paid_intel_purchases)
	if ready and "counterplay" not in state.ending_ready:
		state.ending_ready.append("counterplay")
	if int(state.favorable_choices) >= int(rules.endings.alliance_choices) and "alliance" not in state.ending_ready:
		state.ending_ready.append("alliance")
	if state.rival in rules.endings.takeover_rival_ids and state.receipts.get("takeover", false) and not content.takeover_supply.is_empty() and "takeover" not in state.ending_ready:
		state.ending_ready.append("takeover")

func confirm_ending(kind: String, day: int) -> bool:
	if day < int(rules.timeline.ending_day) or not state.ending.is_empty() or not state.pending_ending.is_empty() or kind not in state.ending_ready:
		return false
	state.pending_ending = {"kind": kind, "day": day + int(rules.endings.resolution_effective_delay_days)}
	return true

func summary(day: int) -> String:
	if narrative(): return "\n".join(state.street.notices)
	if rival().is_empty():
		return data.summary.quiet
	return "\n".join([data.summary.traffic, data.summary.ended if not state.ending.is_empty() else (rival().summary if day >= int(rules.timeline.rumor_day) else data.summary.quiet), state.forecast if not state.forecast.is_empty() else data.summary.tomorrow])
