extends RefCounted
## Reserve real quantities, including top-up. Trial plans never mutate live stock/cash.
var competition
var pricing
var day: int
var tiers: Dictionary

func _init(model, price_model, current_day: int, levels: Dictionary) -> void:
	competition = model
	pricing = price_model
	day = current_day
	tiers = levels

func empty_plan(stock: Dictionary, cash: int) -> Dictionary:
	return {"remaining": stock.duplicate(true), "cash": cash, "bills": {}, "orders": [], "cost": 0}

func reserve(plan: Dictionary, recipe: Dictionary, customer_index: int, actual_recipe: Dictionary = {}) -> Dictionary:
	var trial = plan.duplicate(true)
	var replacements = {}
	var required = actual_recipe if not actual_recipe.is_empty() else recipe
	for item in required.ingredients + required.topup:
		var actual: String = item.name
		var amount = float(item.amount)
		if not _supply(trial, actual, amount):
			var found = false
			for alternate in competition.market(day).substitutes.get(item.name, []):
				var alternative_plan = trial.duplicate(true)
				if _supply(alternative_plan, alternate, amount):
					trial = alternative_plan
					actual = alternate
					replacements[item.name] = actual
					found = true
					break
			if not found:
				return {}
		trial.remaining[actual] = float(trial.remaining.get(actual, 0)) - amount
	var quoted = competition.quote(recipe, pricing.calculate(recipe, tiers), day, tiers)
	quoted.legal_substitute = not replacements.is_empty()
	trial.orders.append({"recipe_id": recipe.id, "customer_index": customer_index, "quote": quoted, "substitutions": replacements})
	return trial

func _supply(plan: Dictionary, name: String, amount: float) -> bool:
	var missing = amount - float(plan.remaining.get(name, 0))
	if missing <= 0:
		return true
	var old: Dictionary = plan.bills.get(name, {})
	var packs = ceili(missing / float(pricing.catalog.ingredients[name].pack_ml))
	var emergency = competition.sold_out(name, day) and competition.can_emergency(name, day)
	var bill = competition.purchase_bill(name, packs + int(old.get("packs", 0)), pricing.pack_price(name, tiers), day, tiers, emergency)
	if bill.is_empty():
		return false
	var delta = int(bill.total) - int(old.get("total", 0))
	if delta > int(plan.cash):
		return false
	plan.cash -= delta
	plan.cost += delta
	plan.bills[name] = bill
	plan.remaining[name] = float(plan.remaining.get(name, 0)) + packs * float(pricing.catalog.ingredients[name].pack_ml)
	return true

func three(recipe: Dictionary, stock: Dictionary, cash: int) -> Dictionary:
	var plan = empty_plan(stock, cash)
	for index in range(int(competition.rules.limits.promotion_guaranteed_orders)):
		plan = reserve(plan, recipe, 0)
		if plan.is_empty():
			break
	return plan

func repair_market(recipes: Array, stock: Dictionary, cash: int) -> bool:
	var snapshot: Dictionary = competition.market(day)
	if recipes.any(func(recipe): return not three(recipe, stock, cash).is_empty()):
		return true
	# Release newest outages first; preserve generated order and never roll again.
	var old_names: Array = []
	var new_names: Array = []
	for name in snapshot.outages:
		if competition.market(day - 1).outages.has(name):
			old_names.append(name)
		else:
			new_names.append(name)
	new_names.reverse()
	old_names.reverse()
	for name in new_names + old_names:
		snapshot.outages.erase(name)
		competition.state.markets[str(day)] = snapshot
		if recipes.any(func(recipe): return not three(recipe, stock, cash).is_empty()):
			return true
	return false
