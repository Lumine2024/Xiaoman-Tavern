class_name Brew
extends RefCounted
## Order rules independent of the presentation, shared with the headless tests.

var settings: Dictionary
var recipe: Dictionary
var customer: Dictionary
var stage = 0
var ingredient_index = 0
var measured = 0.0
var errors = 0
var mistakes: Array = []
var mix_error = 0.0
var mix_perfect = false
var cup = ""
var ice = ""
var poured = false
var topup_index = 0
var special_done = false
var garnishes: Array = []
var pre_solids: Array = []
var quantities: Array = []
var selected_liquid = ""
var overflow = 0.0

func _init(config: Dictionary, drink: Dictionary, guest: Dictionary) -> void:
	settings = config
	recipe = drink
	customer = guest
	_sync_measure_stage()

func target() -> Dictionary:
	if ingredient_index < recipe.ingredients.size():
		return recipe.ingredients[ingredient_index]
	return {}

func _sync_measure_stage() -> void:
	if ingredient_index >= recipe.ingredients.size():
		stage = 2
	else:
		stage = 0 if target().name in settings.base_names else 1

func add_liquid(liquid: String, amount: float) -> void:
	if stage > 1 or amount <= 0:
		return
	if selected_liquid.is_empty():
		selected_liquid = liquid
	elif selected_liquid != liquid:
		_mistake("mixed_liquids", {"target_name": target().name, "previous": selected_liquid, "actual_name": liquid})
		selected_liquid = liquid
	measured += amount
	overflow = maxf(0.0, measured - float(settings.jigger_capacity))

func transfer() -> bool:
	if stage > 1 or measured <= 0:
		return false
	var item = target()
	var deviation = absf(measured - float(item.amount)) / float(item.amount)
	var optional_amount = float(customer.get("reservation_optional", {}).get(item.name, item.amount))
	var optional_deviation = absf(measured - optional_amount) / optional_amount
	if selected_liquid != item.name or minf(deviation, optional_deviation) > float(settings.quantity_tolerance):
		_mistake("transfer", {"target_name": item.name, "target": item.amount, "actual_name": selected_liquid, "amount": measured, "optional": optional_amount, "tolerance": float(settings.quantity_tolerance) * 100})
	quantities.append({"name": selected_liquid, "amount": measured, "target": item.amount, "deviation": deviation, "overflow": overflow})
	measured = 0.0
	overflow = 0.0
	selected_liquid = ""
	ingredient_index += 1
	_sync_measure_stage()
	return true

func mix_at(position: float) -> void:
	if stage != 2:
		return
	if recipe.method != "直调":
		mix_error = absf(position - float(settings.mix_target))
		mix_perfect = mix_error <= float(settings.perfect_tolerance)
		if mix_error > float(settings.mix_tolerance[recipe.method]):
			_mistake("mix", {"method": recipe.method, "deviation": mix_error * 100, "tolerance": float(settings.mix_tolerance[recipe.method]) * 100})
	for item in recipe.pre_solids:
		if item.name not in pre_solids:
			_mistake("pre_solid", {"ingredient": item.name})
	stage = 3

func expected_ice() -> String:
	return "无冰" if customer.request == "no_ice" or customer.get("no_ice", false) else recipe.ice

func choose_vessel(chosen_cup: String, chosen_ice: String) -> bool:
	if stage != 3:
		return false
	cup = chosen_cup
	ice = chosen_ice
	if cup != recipe.cup:
		_mistake("cup", {"actual": cup, "expected": recipe.cup})
	# Ice is scored at special handling so an explicit correction remains possible.
	return true

func finish_pour() -> void:
	if stage != 3 or cup.is_empty():
		return
	poured = true
	if recipe.topup.is_empty():
		stage = 4

func add_topup(liquid: String) -> bool:
	if stage != 3 or not poured or topup_index >= recipe.topup.size():
		return false
	if liquid != recipe.topup[topup_index].name:
		_mistake("topup", {"actual": liquid, "expected": recipe.topup[topup_index].name})
	topup_index += 1
	if topup_index == recipe.topup.size():
		stage = 4
	return true

func handle_special(apply_request: bool) -> void:
	if stage != 4:
		return
	if apply_request and (customer.request == "no_ice" or customer.get("no_ice", false)):
		ice = "无冰"
	special_done = apply_request
	if not apply_request or ice != expected_ice():
		_mistake("special_skipped" if not apply_request else "ice", {"actual": ice, "expected": expected_ice()})
	stage = 5

func expected_garnishes() -> Array:
	return [] if customer.request == "no_garnish" or customer.get("no_garnish", false) else recipe.garnish

func add_garnish(item: String) -> void:
	if stage != 5 or item in garnishes:
		return
	garnishes.append(item)
	if item not in expected_garnishes():
		_mistake("garnish_extra", {"ingredient": item})

func _mistake(code: String, details: Dictionary) -> void:
	errors += 1
	mistakes.append({"code": code, "data": details, "count": 1})

func final_error_details() -> Array:
	var result = mistakes.duplicate(true)
	# Preserve compatibility with external rule fixtures which set errors
	# directly instead of performing an action through the model.
	if result.size() != errors: result = [] if errors == 0 else [{"code": "untracked", "data": {}, "count": errors}]
	for item in expected_garnishes():
		if item not in garnishes: result.append({"code": "garnish_missing", "data": {"ingredient": item}, "count": 1})
	return result

func final_errors() -> int:
	var result = errors
	for item in expected_garnishes():
		if item not in garnishes:
			result += 1
	return result
