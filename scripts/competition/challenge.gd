extends RefCounted
## A challenge clock is separate from the continuous business calendar.
var rules: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/challenges.json")
var state: Dictionary = fresh()

func fresh() -> Dictionary:
	return {"phase": "off", "rival": "", "start_day": 1, "round": 0, "defeated": [], "results": [], "stats": statistics(), "days": {}, "opportunities": [], "retry": {}, "finale_seen": false, "reservations": []}

func statistics() -> Dictionary:
	return {"opportunities": 0, "valid": 0, "promotion": 0, "by_promotion": {}, "careful": 0, "careful_guests": {}, "perfect": 0, "perfect_recipes": {}, "trend_hits": 0, "hit_events": {}, "net": 0.0, "upgrade_cost": 0}

func active() -> bool:
	return state.phase == "active"

func day(calendar: int) -> int:
	return 0 if state.phase == "preparation" else calendar - int(state.start_day) + 1

func prepare(rival: String, first_day: int) -> void:
	state.phase = "preparation"
	state.rival = rival
	state.start_day = first_day
	state.round += 1
	state.stats = statistics()
	state.days = {}
	state.retry = {}
	state.opportunities = []
	if rival == "olga":
		var config: Dictionary = rules.rivals.olga
		for index in config.due_days.size():
			state.opportunities.append({"id": "%d:%d" % [state.round, index], "recipe": config.recipes[index], "notice": first_day + int(config.notice_days[index]) - 1, "due": first_day + int(config.due_days[index]) - 1, "end": first_day + int(config.due_days[index]) - 1 + int(config.duration_days), "heard": -1, "prepared": -1})

func count_for_day(base: int, calendar: int, normal_minimum: int) -> int:
	if not active(): return base
	var config: Dictionary = rules.rivals[state.rival]
	var result = base
	if config.has("minimum_opportunities"):
		result = maxi(result, ceili(float(config.minimum_opportunities) * day(calendar) / int(rules.days)) - int(state.stats.opportunities))
	if config.get("preserve_base_traffic", false): result = maxi(result, normal_minimum)
	if config.has("promotion_guarantee"): result = maxi(result, int(config.promotion_guarantee))
	if state.rival == "olga": result = maxi(result, int(config.orders_per_opportunity))
	return result

func register_day(calendar: int, count: int) -> void:
	if not active() or state.days.has(str(calendar)): return
	state.days[str(calendar)] = count
	state.stats.opportunities += count

func due_opportunity(calendar: int) -> Dictionary:
	for opportunity in state.opportunities:
		if int(opportunity.due) == calendar: return opportunity
	return {}

func heard(opportunity: Dictionary, calendar: int) -> void:
	if int(opportunity.notice) <= calendar and calendar < int(opportunity.due): opportunity.heard = calendar

func plan(opportunity: Dictionary, calendar: int, stocked: bool) -> bool:
	if not stocked or int(opportunity.heard) < 0 or int(opportunity.heard) >= int(opportunity.due) or calendar >= int(opportunity.due): return false
	opportunity.prepared = calendar
	return true

func planned_promotion(calendar: int) -> String:
	var opportunity = due_opportunity(calendar)
	return str(opportunity.recipe) if not opportunity.is_empty() and int(opportunity.prepared) >= 0 else ""

func active_trends(calendar: int) -> Array:
	var ids = []
	if not active(): return ids
	for opportunity in state.opportunities:
		if int(opportunity.due) <= calendar and calendar < int(opportunity.end) and opportunity.recipe not in ids: ids.append(opportunity.recipe)
	return ids

func score(order: Dictionary, customer: String, recipe: Dictionary, wine: int, complete: bool, conversation: bool, response: bool, special: bool, errors: int, high_tier: bool, calendar: int) -> void:
	if not active() or order.has("event_appraisal") or order.get("challenge_scored", false): return
	order.challenge_scored = true
	if not complete or wine <= 0: return
	var stats: Dictionary = state.stats
	stats.valid += 1
	if order.get("promotion_id", "") == recipe.id:
		stats.promotion += 1
		_increment(stats.by_promotion, recipe.id)
	if conversation and response and special:
		stats.careful += 1
		_increment(stats.careful_guests, customer)
	if recipe.id.split("-")[0] in rules.rivals.viola.bands and high_tier and conversation and special and errors == 0:
		stats.perfect += 1
		_increment(stats.perfect_recipes, recipe.id)
	for opportunity in state.opportunities:
		if opportunity.recipe == recipe.id and int(opportunity.heard) >= 0 and int(opportunity.prepared) >= 0 and int(opportunity.heard) < int(opportunity.due) and int(opportunity.prepared) < int(opportunity.due) and int(opportunity.due) <= calendar and calendar < int(opportunity.end):
			stats.trend_hits += 1
			_increment(stats.hit_events, str(opportunity.id))
			break

func _increment(values: Dictionary, key: String) -> void:
	values[key] = int(values.get(key, 0)) + 1

func update_net(ledger, calendar: int) -> void:
	if not active(): return
	var total = 0.0
	var current_recorded = false
	for record in ledger.history:
		if int(record.day) >= int(state.start_day): total += float(record.contribution)
		if int(record.day) == calendar: current_recorded = true
	if not current_recorded: total += ledger.contribution()
	state.stats.net = total

func value(key: String) -> float:
	var stats: Dictionary = state.stats
	match key:
		"fulfillment": return float(stats.valid) / float(stats.opportunities) if int(stats.opportunities) > 0 else 0.0
		"promotion_variety": return stats.by_promotion.values().filter(func(n): return int(n) >= int(rules.rivals.bella.per_recipe)).size()
		"careful_variety": return stats.careful_guests.values().filter(func(n): return int(n) >= int(rules.rivals.marta.per_customer)).size()
		"perfect_variety": return stats.perfect_recipes.size()
		"hit_variety": return stats.hit_events.size()
	return float(stats.get(key, 0))

func won() -> bool:
	return rules.rivals[state.rival].metrics.all(func(metric): return value(metric.key) >= float(metric.target))

func finish(calendar: int) -> bool:
	if not active() or day(calendar) < int(rules.days): return false
	state.phase = "result"
	var victory = won()
	if victory and state.rival not in state.defeated: state.defeated.append(state.rival)
	state.results.append({"rival": state.rival, "won": victory, "stats": state.stats.duplicate(true), "day": calendar})
	return true

func validate(value: Dictionary) -> bool:
	if value.keys().size() != fresh().size() or value.get("phase") not in ["off", "preparation", "active", "result", "free", "rest"]: return false
	if not value.get("rival") is String or (value.rival != "" and value.rival not in rules.rivals): return false
	if value.phase in ["active", "preparation", "result"] and value.rival.is_empty(): return false
	for key in ["round", "start_day"]:
		if not _integer(value.get(key)): return false
		value[key] = int(value[key])
	if int(value.start_day) < 1: return false
	if not value.get("retry") is Dictionary or not value.get("days") is Dictionary or not value.get("stats") is Dictionary or not value.get("finale_seen") is bool: return false
	if not valid_statistics(value.stats): return false
	for key in ["defeated", "results", "opportunities", "reservations"]:
		if not value.get(key) is Array: return false
	var seen = []
	for rival in value.defeated:
		if rival not in rules.rivals or rival in seen: return false
		seen.append(rival)
	for count in value.days.values():
		if not _integer(count): return false
	for date in value.days: value.days[date] = int(value.days[date])
	var provided = 0
	for count in value.days.values(): provided += int(count)
	if provided != int(value.stats.opportunities): return false
	for opportunity in value.opportunities:
		if not opportunity is Dictionary or opportunity.size() != 7 or not opportunity.get("id") is String or opportunity.get("recipe") not in rules.rivals.olga.recipes: return false
		for key in ["notice", "due", "end", "heard", "prepared"]:
			if not _integer(opportunity.get(key), -1): return false
			opportunity[key] = int(opportunity[key])
		if int(opportunity.notice) >= int(opportunity.due) or int(opportunity.end) <= int(opportunity.due): return false
	for result in value.results:
		if not result is Dictionary or result.get("rival") not in rules.rivals or not result.get("won") is bool or not result.get("stats") is Dictionary or not _integer(result.get("day")): return false
		if not valid_statistics(result.stats): return false
		result.day = int(result.day)
	for reservation in value.reservations:
		if not reservation is Dictionary or reservation.get("customer") == null or not _integer(reservation.get("due")): return false
		reservation.due = int(reservation.due)
	return true

func valid_statistics(stats: Dictionary) -> bool:
	if stats.size() != statistics().size(): return false
	for key in statistics():
		if statistics()[key] is Dictionary:
			if not stats.get(key) is Dictionary: return false
			for entry in stats[key]:
				if not entry is String or entry.is_empty() or not _integer(stats[key][entry]): return false
				stats[key][entry] = int(stats[key][entry])
		elif key == "net":
			if not (stats.get(key) is int or stats.get(key) is float) or not is_finite(float(stats[key])): return false
			stats[key] = float(stats[key])
		else:
			if not _integer(stats.get(key)): return false
			stats[key] = int(stats[key])
	if int(stats.valid) > int(stats.opportunities): return false
	for key in ["promotion", "careful", "perfect", "trend_hits"]:
		if int(stats[key]) > int(stats.valid): return false
	var maps = {"by_promotion": "promotion", "careful_guests": "careful", "perfect_recipes": "perfect", "hit_events": "trend_hits"}
	for key in maps:
		var total = 0
		for count in stats[key].values(): total += int(count)
		if total != int(stats[maps[key]]): return false
	return true

func _integer(value, minimum = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) < 9007199254740991.0
