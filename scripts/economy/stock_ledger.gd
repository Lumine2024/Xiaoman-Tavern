extends RefCounted
## FIFO usage cost is independent of procurement cash; old cost basis stays unknown.
var batches: Dictionary = {}
var order_discounted: Dictionary = {}
var unknown_basis = false
var daily: Dictionary = {}
var history: Array = []

func reset(stock: Dictionary) -> void:
	batches = {}
	order_discounted = {}
	unknown_basis = false
	history = []
	for name in stock:
		batches[name] = [ {"ml": float(stock[name]), "unit_cost": 0.0}]
	new_day()

func new_day() -> void:
	daily = {"liquor": 0, "tips": 0, "ingredients": 0.0, "spoilage": 0.0, "events": 0, "procurement": 0, "consumables": 0.0}

func purchase(name: String, ml: float, unit_cost: float, cash: int, merchant_discount = false) -> void:
	if not batches.has(name):
		batches[name] = []
	batches[name].append({"ml": ml, "unit_cost": unit_cost, "merchant_discount": merchant_discount})
	daily.procurement += cash

func consume(name: String, amount: float, spoilage = false) -> void:
	var left = amount
	var cost = 0.0
	var list: Array = batches.get(name, [])
	while left > 0.0000001 and not list.is_empty():
		var batch: Dictionary = list[0]
		var used = minf(left, float(batch.ml))
		cost += used * float(batch.unit_cost)
		if not spoilage and used > 0 and batch.get("merchant_discount", false):
			order_discounted[name] = float(order_discounted.get(name, 0)) + used
		batch.ml = float(batch.ml) - used
		left -= used
		if float(batch.ml) <= 0.0000001:
			list.pop_front()
	if left > 0.0000001:
		unknown_basis = true
	daily["spoilage" if spoilage else "ingredients"] += cost

func contribution() -> float:
	return float(daily.liquor) + float(daily.tips) - float(daily.ingredients) - float(daily.spoilage) - float(daily.events) - float(daily.consumables)

func finish_day(day: int) -> void:
	if not history.any(func(record): return int(record.day) == day):
		history.append({"day": day, "account": daily.duplicate(true), "contribution": contribution()})

func snapshot() -> Dictionary:
	return {"batches": batches.duplicate(true), "unknown_basis": unknown_basis, "daily": daily.duplicate(true), "history": history.duplicate(true)}

func restore(value: Dictionary) -> void:
	batches = value.batches.duplicate(true)
	unknown_basis = value.unknown_basis
	daily = value.daily.duplicate(true)
	history = value.get("history", []).duplicate(true)
