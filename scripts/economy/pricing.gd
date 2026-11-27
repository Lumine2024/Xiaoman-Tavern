extends RefCounted
## Runtime equivalent of the delivered Decimal API. Tier indices here are zero-based.
var catalog: Dictionary

func _init(data: Dictionary) -> void:
	catalog = data

func pack_price(name: String, tiers: Dictionary = {}) -> float:
	if not catalog.ingredients.has(name):
		push_error("原料未定价：" + name)
		return NAN
	var item: Dictionary = catalog.ingredients[name]
	var price = float(item.pack_price)
	if item.family != null:
		var template: Array = catalog.base_families[item.family].tiers
		var tier = int(tiers.get(item.family, 0))
		if tier < 0 or tier >= template.size():
			push_error("无效基酒等级：" + str(tier))
			return NAN
		price += float(template[tier].pack_price) - float(template[0].pack_price)
	return price

func calculate(recipe: Dictionary, tiers: Dictionary = {}) -> Dictionary:
	var rule: Dictionary = catalog.pricing_rules
	var difficulty = recipe.id.split("-")[0]
	if not rule.difficulty_base.has(difficulty) or not rule.methods.has(recipe.method):
		push_error("未知配方难度或技法")
		return {}
	var cost0 = float(rule.consumables_per_drink)
	var cost = cost0
	var liquids: Array = recipe.ingredients + recipe.topup
	if liquids.is_empty():
		return {}
	for item in liquids:
		if not catalog.ingredients.has(item.name) or not is_finite(float(item.amount)) or float(item.amount) <= 0:
			push_error("未定价原料或无效用量：" + str(item))
			return {}
		var entry: Dictionary = catalog.ingredients[item.name]
		var price = pack_price(item.name, tiers)
		if not is_finite(price):
			return {}
		cost0 += float(item.amount) * float(entry.pack_price) / float(entry.pack_ml)
		cost += float(item.amount) * price / float(entry.pack_ml)
	var work: Dictionary = rule.work
	var extra = maxi(0, liquids.size() - int(work.included_liquid_portions)) * float(work.per_extra_liquid)
	extra += maxi(0, recipe.garnish.size() - int(work.included_garnishes)) * float(work.per_extra_garnish)
	extra += recipe.pre_solids.size() * float(work.per_pre_solid) + float(rule.methods[recipe.method].extra_value)
	var step = float(rule.round_to)
	var standard = _round_up(maxf(cost0 / float(rule.max_cost_ratio), float(rule.difficulty_base[difficulty]) + float(rule.cost_value_multiplier) * cost0 + extra), step)
	var price = _round_up(maxf(standard + float(rule.cost_value_multiplier) * (cost - cost0), cost / float(rule.max_cost_ratio)), step)
	return {"price": price, "standard_price": standard, "cost": cost, "standard_cost": cost0, "work_value": extra}

func _round_up(value: float, step: float) -> int:
	# Avoid rounding a mathematically exact step up due to binary float noise.
	return int(ceilf(value / step - 0.000000001) * step)
