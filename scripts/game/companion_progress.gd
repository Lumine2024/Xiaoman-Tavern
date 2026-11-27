extends RefCounted
## Round-only companion goals; claims survive round changes, ordinary accounts stay separate.
var rules: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/companions.json")
var state: Dictionary = fresh()

func fresh(id = "") -> Dictionary:
	return {"version": 1, "id": id, "round": 0, "locked": false, "pending_rival": "", "claims": [], "investment": 0, "discount_orders": 0, "discount_ingredients": [], "discount_purchases": {}, "valid_by_day": {}, "interest_days": {}, "interest_total": 0, "upgrade_records": {}, "upgrade_base": 0, "upgrade_families": [], "branch": "", "outcome": ""}

func prepare(game) -> void:
	if state.locked and int(state.round) == int(game.challenge.state.round): return
	var claims: Array = state.claims.duplicate()
	state = fresh(game.companion.id)
	state.claims = claims
	state.round = int(game.challenge.state.round)
	state.locked = true
	if state.id == "patron":
		if game.challenge.state.rival not in state.claims:
			state.claims.append(game.challenge.state.rival)
			state.investment = int(rules.patron.investment)
			game.money += int(state.investment)
		var families = 0
		var remaining = 0
		for family in game.config.base_tiers:
			var levels: Array = game.config.base_tiers[family]
			if int(game.tiers[family]) < levels.size() - 1: families += 1
			for tier in range(int(game.tiers[family]) + 1, levels.size()): remaining += int(levels[tier].unlock_fee)
		# Existing equipment upgrades have no cap. Do not invent a new maximum.
		var enough_value = remaining >= int(rules.patron.upgrade_amount) or int(game.config.equipment_price) > 0
		state.branch = "upgrade" if enough_value and families >= int(rules.patron.families) else "net"

func discount_bill(bill: Dictionary, id: String, catalog: Dictionary) -> Dictionary:
	if bill.is_empty() or id != "merchant" or bill.get("merchant_discount", false): return bill
	var result = bill.duplicate(true)
	result.total = roundi(float(result.total) * float(rules.merchant.purchase_multiplier))
	result.unit_cost = float(result.total) / (int(result.packs) * float(catalog.ingredients[result.name].pack_ml))
	result.merchant_discount = int(result.total) < int(bill.total)
	return result

func upgrade_price(raw: int, id: String) -> int:
	return roundi(raw * float(rules.merchant.upgrade_multiplier)) if id == "merchant" else raw

func purchase(bill: Dictionary, volume: float) -> void:
	if not state.locked or state.id != "merchant" or not bill.get("merchant_discount", false): return
	state.discount_purchases[bill.name] = float(state.discount_purchases.get(bill.name, 0)) + volume

func score(game, order: Dictionary, valid: bool) -> void:
	if not game.challenge.active() or not state.locked or order.has("event_appraisal") or order.get("companion_scored", false): return
	order.companion_scored = true
	if not valid: return
	var key = str(game.day)
	state.valid_by_day[key] = int(state.valid_by_day.get(key, 0)) + 1
	if state.id == "merchant" and not game.stock_ledger.order_discounted.is_empty():
		state.discount_orders += 1
		for name in game.stock_ledger.order_discounted:
			if name not in state.discount_ingredients: state.discount_ingredients.append(name)

func close_day(game) -> void:
	if state.id != "banker" or not state.locked or not game.challenge.active(): return
	var number = game.challenge.day(game.day)
	if number < 1 or number > int(game.challenge.rules.days) or state.interest_days.has(str(game.day)): return
	var valid = int(state.valid_by_day.get(str(game.day), 0))
	var principal = minf(maxf(game.money - int(game.competition.state.credit_used), 0), float(rules.banker.principal_cap))
	var eligible = valid >= int(rules.banker.daily_valid)
	var interest = mini(int(rules.banker.daily_cap), floori(principal * float(rules.banker.rate))) if eligible else 0
	state.interest_days[str(game.day)] = {"valid": valid, "eligible": eligible, "principal": principal, "interest": interest}
	state.interest_total += interest
	game.money += interest

func upgrade(family: String, level: int, raw: int) -> void:
	if not state.locked or state.id != "patron": return
	var key = ("equipment" if family.is_empty() else family) + ":" + str(level)
	if state.upgrade_records.has(key): return
	state.upgrade_records[key] = {"family": family, "level": level, "price": raw}
	state.upgrade_base += raw
	if not family.is_empty() and family not in state.upgrade_families: state.upgrade_families.append(family)

func valid_orders() -> int:
	var total = 0
	for count in state.valid_by_day.values(): total += int(count)
	return total

func qualified_days() -> int:
	return state.interest_days.values().filter(func(record): return record.eligible).size()

func achieved(challenge) -> bool:
	match state.id:
		"merchant": return int(state.discount_orders) >= int(rules.merchant.orders) and state.discount_ingredients.size() >= int(rules.merchant.ingredients)
		"banker": return int(state.interest_total) >= int(rules.banker.interest) and qualified_days() >= int(rules.banker.days)
		"patron":
			var goal = float(challenge.state.stats.net) >= float(rules.patron.net) if state.branch == "net" else int(state.upgrade_base) >= int(rules.patron.upgrade_amount) and state.upgrade_families.size() >= int(rules.patron.families)
			return valid_orders() >= int(rules.patron.orders) and goal
	return false

func finish(challenge) -> void:
	if not state.locked or not state.outcome.is_empty(): return
	state.outcome = ("success" if achieved(challenge) else "ordinary") if challenge.won() else "failure"
	if not challenge.state.results.is_empty():
		challenge.state.results[-1].companion_result = {"id": state.id, "outcome": state.outcome, "start_day": int(challenge.state.start_day), "progress": state.duplicate(true)}

func lines(game) -> Array[String]:
	var prose: Dictionary = game.story_catalog.content.companions
	var result: Array[String] = [prose.progress.format({"name": game.companion.name}), game.companion.description, prose.locked if state.locked else prose.unlocked]
	if int(state.round) == 0:
		return result
	match state.id:
		"merchant":
			result.append(prose.discount_orders.format({"actual": state.discount_orders, "target": int(rules.merchant.orders)}))
			result.append(prose.discount_variety.format({"actual": state.discount_ingredients.size(), "target": int(rules.merchant.ingredients)}))
			var purchases: Array[String] = []
			for name in state.discount_purchases: purchases.append("%s %sml" % [name, state.discount_purchases[name]])
			result.append(prose.discount_purchases.format({"items": "、".join(purchases) if not purchases.is_empty() else prose.no_records}))
			result.append(prose.discount_used.format({"items": "、".join(state.discount_ingredients) if not state.discount_ingredients.is_empty() else prose.no_records}))
		"banker":
			result.append(prose.interest.format({"actual": state.interest_total, "target": int(rules.banker.interest), "days": qualified_days(), "target_days": int(rules.banker.days)}))
			if state.interest_days.has(str(game.day)):
				var record: Dictionary = state.interest_days[str(game.day)].duplicate()
				record.day = game.day
				result.append(prose.today_interest.format(record))
			elif game.challenge.active():
				result.append(prose.interest_pending.format({"day": game.day, "valid": int(state.valid_by_day.get(str(game.day), 0)), "required": int(rules.banker.daily_valid), "principal": minf(maxf(game.money - int(game.competition.state.credit_used), 0), float(rules.banker.principal_cap))}))
		"patron":
			result.append(prose.investment.format({"amount": state.investment, "rivals": "、".join(state.claims.map(func(id): return game.competition.data.rivals[id].name))}))
			result.append(prose.valid.format({"actual": valid_orders(), "target": int(rules.patron.orders)}))
			if state.branch == "net": result.append(prose.net.format({"actual": "%.2f" % float(game.challenge.state.stats.net), "target": int(rules.patron.net)}))
			else:
				result.append(prose.branch_upgrade)
				result.append(prose.upgrades.format({"actual": state.upgrade_base, "target": int(rules.patron.upgrade_amount), "families": state.upgrade_families.size(), "target_families": int(rules.patron.families)}))
		_: result.append(prose.no_goal)
	return result

func validate(value: Dictionary, config: Dictionary, challenge, liquids: Array) -> bool:
	if value.size() != fresh().size() or value.get("version") != 1: return false
	value.version = 1
	if value.get("id") not in config.companions.map(func(item): return item.id): return false
	if not value.get("locked") is bool or value.get("outcome") not in ["", "ordinary", "success", "failure"] or value.get("branch") not in ["", "upgrade", "net"]: return false
	if not value.get("pending_rival") is String or (value.pending_rival != "" and value.pending_rival not in challenge.rules.rivals): return false
	for key in ["round", "investment", "discount_orders", "interest_total", "upgrade_base"]:
		if not challenge._integer(value.get(key)): return false
		value[key] = int(value[key])
	if value.locked and (int(value.round) != int(challenge.state.round) or value.id == "patron" and value.branch.is_empty()): return false
	for key in ["claims", "discount_ingredients", "upgrade_families"]:
		if not value.get(key) is Array: return false
		var seen = []
		for entry in value[key]:
			var allowed = challenge.rules.rivals.keys() if key == "claims" else (liquids if key == "discount_ingredients" else config.base_tiers.keys())
			if entry not in allowed or entry in seen: return false
			seen.append(entry)
	if value.outcome == "success" and value.id not in ["merchant", "banker", "patron"]: return false
	if value.investment not in [0, int(rules.patron.investment)]: return false
	if value.investment > 0 and (value.id != "patron" or challenge.state.rival not in value.claims): return false
	for key in ["discount_purchases", "valid_by_day", "interest_days", "upgrade_records"]:
		if not value.get(key) is Dictionary: return false
	for name in value.discount_purchases:
		if name not in liquids or not _number(value.discount_purchases[name]): return false
	var total = 0
	for date in value.valid_by_day:
		if not _date(date, challenge) or not challenge._integer(value.valid_by_day[date]): return false
		value.valid_by_day[date] = int(value.valid_by_day[date])
		total += int(value.valid_by_day[date])
	if total > int(challenge.state.stats.valid) or int(value.discount_orders) > total: return false
	var interest = 0
	for date in value.interest_days:
		var record = value.interest_days[date]
		if not _date(date, challenge) or not record is Dictionary or record.size() != 4: return false
		if not record.get("eligible") is bool or not challenge._integer(record.get("valid")) or not _number(record.get("principal")) or not challenge._integer(record.get("interest")): return false
		if float(record.principal) > float(rules.banker.principal_cap) or int(record.valid) != int(value.valid_by_day.get(date, 0)) or record.eligible != (int(record.valid) >= int(rules.banker.daily_valid)): return false
		var expected = mini(int(rules.banker.daily_cap), floori(float(record.principal) * float(rules.banker.rate))) if record.eligible else 0
		if int(record.interest) != expected: return false
		record.valid = int(record.valid)
		record.interest = int(record.interest)
		record.principal = float(record.principal)
		interest += int(record.interest)
	if int(value.interest_total) != interest: return false
	var upgrade_total = 0
	var families = []
	for key in value.upgrade_records:
		var record = value.upgrade_records[key]
		if not record is Dictionary or record.size() != 3 or not record.get("family") is String or not challenge._integer(record.get("level"), 1) or not challenge._integer(record.get("price")): return false
		var family: String = record.family
		if key != ("equipment" if family.is_empty() else family) + ":" + str(int(record.level)): return false
		if not family.is_empty():
			if family not in config.base_tiers or int(record.level) >= config.base_tiers[family].size(): return false
			if int(record.price) != int(config.base_tiers[family][int(record.level)].unlock_fee): return false
			if family not in families: families.append(family)
		elif int(record.price) != int(config.equipment_price): return false
		record.level = int(record.level)
		record.price = int(record.price)
		upgrade_total += int(record.price)
	if upgrade_total != int(value.upgrade_base) or families.size() != value.upgrade_families.size() or not families.all(func(f): return f in value.upgrade_families): return false
	if value.id != "banker" and (not value.interest_days.is_empty() or interest != 0): return false
	if value.id != "merchant" and (value.discount_orders != 0 or not value.discount_ingredients.is_empty() or not value.discount_purchases.is_empty()): return false
	if value.id != "patron" and (upgrade_total != 0 or not value.branch.is_empty()): return false
	return true

func _date(date, challenge) -> bool:
	return date is String and date.is_valid_int() and str(int(date)) == date and int(date) >= int(challenge.state.start_day) and int(date) < int(challenge.state.start_day) + int(challenge.rules.days)

func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0
