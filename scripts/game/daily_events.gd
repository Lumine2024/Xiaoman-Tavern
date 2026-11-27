extends RefCounted
## World events persist independently of who happens to hear about them.
var rules: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/daily_events.json")
var prose: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/story.json").daily_events
var pools: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/story.json").chat_pools
var state: Dictionary = {"generated_days": [], "records": [], "heard_claims": []}

func ready_event(id: String) -> bool:
	var event: Dictionary = rules.events[id]
	if event.duration_days == null: return false
	if event.kind == "price": return event.ingredient != null and event.multiplier != null
	if event.kind == "trend": return event.recipe_id != null
	return event.traffic_delta != null

func generate(day: int, rng: RandomNumberGenerator) -> void:
	if day in state.generated_days: return
	state.generated_days.append(day)
	var candidates: Array = rules.events.keys()
	for index in range(candidates.size() - 1, 0, -1):
		var swap = rng.randi_range(0, index)
		var value = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = value
	var count = 0
	var occupied = []
	for record in state.records:
		var definition: Dictionary = rules.events[record.id]
		if day < int(record.due) + int(definition.duration_days) + int(rules.repeat_cooldown_days): occupied.append(definition.conflict_group)
	for id in candidates:
		var definition: Dictionary = rules.events[id]
		if count >= int(rules.daily_count): break
		if not ready_event(id) or definition.conflict_group in occupied: continue
		state.records.append({"id": id, "day": day, "due": day + int(definition.get("delay_days", 0)), "heard": false, "resolved": false, "mitigation": "", "action_day": 0})
		occupied.append(definition.conflict_group)
		count += 1

func offer(customer_id: String, order: Dictionary, day: int, rng: RandomNumberGenerator) -> void:
	if order.has("event_rolls"): return
	order.event_rolls = []
	order.event_offer = -1
	for index in range(state.records.size() - 1, -1, -1):
		var record: Dictionary = state.records[index]
		var definition: Dictionary = rules.events[record.id]
		if record.heard or record.resolved or (customer_id not in definition.customer_ids and "*" not in definition.customer_ids): continue
		var roll = rng.randf()
		order.event_rolls.append({"index": index, "roll": roll})
		if roll < float(rules.disclosure_probability):
			order.event_offer = index
			break
	var selected: Dictionary
	if int(order.event_offer) >= 0:
		var id: String = state.records[int(order.event_offer)].id
		var record: Dictionary = state.records[int(order.event_offer)]
		var expired = day >= int(record.due) + int(rules.events[id].duration_days)
		var source: Dictionary = pools.history[id] if expired else pools.effective[id]
		if not expired and rules.events[id].kind == "price" and day >= int(record.due): source = pools.ongoing[id]
		var lines: Array = source.get(customer_id, source.get("*", []))
		selected = {"text": lines[rng.randi_range(0, lines.size() - 1)]}
		order.message_kind = "event"
	else:
		var lines: Array = pools.smalltalk["*"].duplicate()
		lines.append_array(pools.smalltalk.get(customer_id, []))
		selected = lines[rng.randi_range(0, lines.size() - 1)]
		order.message_kind = "smalltalk"
	order.message_text = selected.text
	order.message_claim = selected.get("claim", "")

func message(order: Dictionary, day: int) -> String:
	return str(order.get("message_text", prose.none)) + ("\n" + str(order.verification_text) if order.has("verification_text") else "")

func hear(order: Dictionary) -> void:
	var index = int(order.get("event_offer", -1))
	if index >= 0 and index < state.records.size(): state.records[index].heard = true
	var claim: String = order.get("message_claim", "")
	if not claim.is_empty() and claim not in state.heard_claims: state.heard_claims.append(claim)

func active(record: Dictionary, day: int) -> bool:
	return not record.resolved and day >= int(record.due) and day < int(record.due) + int(rules.events[record.id].duration_days)

func price_factor(ingredient: String, day: int) -> float:
	var factor = 1.0
	for record in state.records:
		var definition: Dictionary = rules.events[record.id]
		if definition.kind == "price" and definition.ingredient == ingredient and active(record, day): factor *= float(definition.multiplier)
	return factor

func traffic(day: int, recipe: Dictionary = {}) -> int:
	var delta = 0
	for record in state.records:
		var definition: Dictionary = rules.events[record.id]
		if definition.get("traffic_delta") == null or not active(record, day): continue
		if definition.kind == "price" and (recipe.is_empty() or not (recipe.ingredients + recipe.topup).any(func(item): return item.name == definition.ingredient)): continue
		delta += int(definition.traffic_delta)
	return delta

func action_cost(index: int, day: int) -> int:
	if index < 0 or index >= state.records.size(): return -1
	var record: Dictionary = state.records[index]
	var action = rules.events[record.id].action
	if not record.heard or record.resolved or day >= int(record.due) + int(rules.events[record.id].duration_days) or action == null or action.cost == null: return -1
	return int(action.cost)

func finish_appraisal(index: int, success: bool, day: int) -> void:
	if not success or index < 0 or index >= state.records.size(): return
	state.records[index].resolved = true
	state.records[index].mitigation = "appraiser"
	state.records[index].action_day = day

func validate(value: Dictionary) -> bool:
	if value.size() != 3 or not value.get("generated_days") is Array or not value.get("records") is Array or not value.get("heard_claims") is Array: return false
	for claim in value.heard_claims:
		if claim not in rules.claims: return false
	var days = []
	for day in value.generated_days:
		if not number(day, 1) or day in days: return false
		days.append(int(day))
	value.generated_days = days
	for record in value.records:
		if not record is Dictionary or record.size() != 7 or record.get("id") not in rules.events: return false
		if not number(record.get("day"), 1) or not number(record.get("due"), int(record.day)) or not record.get("heard") is bool or not record.get("resolved") is bool: return false
		if record.get("mitigation") not in ["", "discount", "appraiser"] or not number(record.get("action_day"), 0): return false
		if int(record.day) not in days: return false
		record.day = int(record.day)
		record.due = int(record.due)
		record.action_day = int(record.action_day)
	return true

static func number(value, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) < 9007199254740991.0

func drink_factor(recipe: Dictionary, day: int) -> float:
	var factor = 1.0
	for record in state.records:
		var definition: Dictionary = rules.events[record.id]
		if definition.kind == "price" and active(record, day) and (recipe.ingredients + recipe.topup).any(func(item): return item.name == definition.ingredient): factor *= float(definition.multiplier)
	return factor

func discount(index: int, day: int) -> bool:
	if index < 0 or index >= state.records.size(): return false
	var record: Dictionary = state.records[index]
	if record.resolved or not record.heard or not rules.events[record.id].has("discount_margin_loss") or day >= int(record.due) + int(rules.events[record.id].duration_days): return false
	record.resolved = true
	record.mitigation = "discount"
	record.action_day = day
	return true

func margin_loss(day: int) -> float:
	var retained = 1.0
	for record in state.records:
		if record.mitigation == "discount" and day >= int(record.action_day) and day < int(record.due) + int(rules.events[record.id].duration_days): retained *= 1.0 - float(rules.events[record.id].discount_margin_loss)
	return 1.0 - retained

func can_verify(claim: String, customer_id: String) -> bool:
	return claim in state.heard_claims and rules.claims[claim].verify_customer_id == customer_id

func verify(claim: String, customer_id: String, day: int) -> String:
	if not can_verify(claim, customer_id): return ""
	var factor = price_factor(str(rules.claims[claim].ingredient), day)
	if factor > 1:
		for record in state.records:
			if rules.events[record.id].get("ingredient") == rules.claims[claim].ingredient and active(record, day): record.heard = true
	else:
		for record in state.records:
			var definition: Dictionary = rules.events[record.id]
			if definition.kind == "price" and definition.ingredient == rules.claims[claim].ingredient and float(definition.multiplier) > 1 and not record.resolved and int(record.due) == day + 1:
				record.heard = true
				return pools.claims[claim].upcoming
	return pools.claims[claim].up if factor > 1 else pools.claims[claim].not_up

func order_weights(recipes: Array, promotion_id: String, day: int) -> Dictionary:
	var trending = {}
	for record in state.records:
		var definition: Dictionary = rules.events[record.id]
		if definition.kind == "trend" and active(record, day): trending[definition.recipe_id] = true
	var result = {}
	for recipe in recipes:
		result[recipe.id] = float(rules.order_weights.promotion if recipe.id == promotion_id else (rules.order_weights.trend if trending.has(recipe.id) else rules.order_weights.normal))
	return result

func sample_order(recipes: Array, promotion_id: String, day: int, rng: RandomNumberGenerator, extra_trends: Array = []) -> String:
	if recipes.is_empty(): return ""
	var weights = order_weights(recipes, promotion_id, day)
	for id in extra_trends:
		if id in weights and id != promotion_id: weights[id] = maxf(float(weights[id]), float(rules.order_weights.trend))
	var total = 0.0
	for value in weights.values(): total += float(value)
	var point = rng.randf() * total
	for recipe in recipes:
		point -= float(weights[recipe.id])
		if point < 0: return recipe.id
	return recipes.back().id

func configuration_errors() -> Array[String]:
	var errors: Array[String] = []
	var weights = rules.get("order_weights", {})
	for key in ["normal", "trend", "promotion"]:
		var value = weights.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0:
			errors.append("Invalid order weight: " + key)
	if errors.is_empty() and not (float(weights.normal) < float(weights.trend) and float(weights.trend) < float(weights.promotion)):
		errors.append("Required order weights: normal < trend < promotion")
	var recipes: Array = preload("res://scripts/game/resource_data.gd").read("res://data/recipes.json")
	var recipe_ids = recipes.map(func(recipe): return recipe.id)
	var catalog: Dictionary = preload("res://scripts/game/resource_data.gd").read("res://data/prices.json")
	var customers: Array = preload("res://scripts/game/resource_data.gd").read("res://data/customers.json")
	var customer_ids = customers.map(func(customer): return customer.story_id)
	for id in rules.events:
		var event: Dictionary = rules.events[id]
		if event.kind == "price" and event.ingredient not in catalog.ingredients: errors.append("Unknown ingredient: " + id)
		if event.kind == "price" and event.get("delay_days") != 1: errors.append("Price changes must start the next day: " + id)
		if event.kind == "trend" and (event.recipe_id not in recipe_ids or str(event.recipe_id).split("-")[0] not in rules.trend_bands): errors.append("Invalid trend recipe: " + id)
		for voice in event.customer_ids:
			if voice != "*" and voice not in customer_ids: errors.append("Unknown event customer: " + id)
			var sources = [pools.effective, pools.history]
			if event.kind == "price": sources.append(pools.get("ongoing", {}))
			for source in sources:
				var lines = source.get(id, {}).get(voice, [])
				if not lines is Array or lines.is_empty(): errors.append("Missing event messages: " + id + "/" + voice)
	return errors
