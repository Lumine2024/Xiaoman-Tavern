extends RefCounted
## Describe the same counted events used for payout and challenge quality.
static func build(game, modifiers: Dictionary, timed_out: bool) -> Dictionary:
	var items: Array = game.brew.final_error_details()
	var notes: Array = []
	var requested_tier = game._missing_requested_tier()
	var excluded_tier = modifiers.low_tier and int(game.guest.get("order_spec", {}).get("minimum_tier", 0)) <= int(game.competition.rules.rivals.viola.min_base_tier)
	if requested_tier and not excluded_tier:
		items.append({"code": "tier", "data": {"details": _tier_details(game)}, "count": 1})
	elif requested_tier:
		notes.append("tier_excluded")
	if modifiers.exclude_cup:
		# The existing rule removes one counted mistake for the cup. Keep the
		# exact one-point exclusion, even when earlier cup choices were wrong.
		var at = -1
		for index in range(items.size() - 1, -1, -1):
			if items[index].code == "cup":
				at = index
				break
		if at < 0:
			for index in range(items.size() - 1, -1, -1):
				if int(items[index].count) > 0:
					at = index
					break
		if at >= 0:
			items[at].count -= 1
			if int(items[at].count) == 0: items.remove_at(at)
		notes.append("cup_excluded")
	for segment in range(game.dialogue + 1, 4):
		items.append({"code": "dialogue", "data": {"segment": segment}, "count": 1})
	if timed_out: notes.append("timeout" if game.remaining <= 0 else "abandoned")
	elif game.brew.stage != 5: notes.append("incomplete")
	var count = 0
	for item in items: count += int(item.count)
	return {"count": count, "items": items, "notes": notes}

static func _tier_details(game) -> String:
	var required = {}
	var spec: Dictionary = game.guest.get("order_spec", {})
	if spec.get("recipe", "") == game.brew.recipe.id and spec.has("minimum_tier"):
		for item in game.brew.recipe.ingredients:
			var family: String = game.config.base_families.get(item.name, "")
			if not family.is_empty(): required[family] = int(spec.minimum_tier)
	var rum = str(game.rulings.rum.family)
	if game.brew.recipe.has("minimum_rum_tier"): required[rum] = maxi(int(required.get(rum, 1)), int(game.brew.recipe.minimum_rum_tier))
	var details: Array[String] = []
	for family in required:
		var actual = int(game.tiers[family]) + 1
		if actual < int(required[family]): details.append(game.interface.result.mistakes.tier_item.format({"family": family, "actual": actual, "expected": required[family]}))
	return "；".join(details)

static func reason(game, item: Dictionary) -> String:
	var details: Dictionary = item.data.duplicate()
	for key in details:
		if details[key] is float: details[key] = "%.1f" % details[key]
	for key in ["target_name", "previous", "actual_name"]:
		if details.has(key): details[key] = game.ingredient_label(str(details[key]))
	var code: String = item.code
	if code == "transfer" and float(item.data.optional) != float(item.data.target): code = "transfer_optional"
	return game.interface.result.mistakes[code].format(details)
