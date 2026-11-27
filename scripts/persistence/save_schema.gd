extends RefCounted
## Current save contract only. Obsolete documents are deleted by SaveStore when read.
const VERSION = 8
var config: Dictionary
var recipe_ids: Array = []
var customer_count: int
var customer_ids: Array = []
var liquid_names: Array = []
var competition_defaults

func _init(settings: Dictionary, recipes: Array, customers: Array) -> void:
	config = settings
	competition_defaults = preload("res://scripts/competition/competition.gd").new(preload("res://scripts/game/resource_data.gd").read("res://data/competition.json"))
	customer_count = customers.size()
	for customer in customers: customer_ids.append(customer.story_id)
	for recipe in recipes:
		recipe_ids.append(recipe.id)
		for item in recipe.ingredients + recipe.topup:
			if item.name not in liquid_names:
				liquid_names.append(item.name)

func _integer(value, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) < 9007199254740991.0

func decode(source: Dictionary, depth = 0) -> Dictionary:
	if depth > 1: return {}
	var value = source.duplicate(true)
	if not _integer(value.get("version"), 1) or value.get("version") != VERSION or not value.get("meta") is Dictionary or not value.get("run") is Dictionary:
		return {}
	if value.has("file_info"):
		if not value.file_info is Dictionary or not _integer(value.file_info.get("slot"), -1) or not _number(value.file_info.get("saved_at")):
			return {}
		if float(value.file_info.saved_at) >= 9007199254740991.0: return {}
		if int(value.file_info.slot) >= int(config.get("save_slot_count", 0)): return {}
	var meta: Dictionary = value.meta
	if not _integer(meta.get("cycle"), 1) or not _integer(meta.get("highest_cycle"), 1):
		return {}
	if meta.highest_cycle < meta.cycle or not meta.get("ability_grants") is Array:
		return {}
	if meta.ability_grants.size() != int(meta.cycle) - 1:
		return {}
	for index in range(meta.ability_grants.size()):
		var grant = meta.ability_grants[index]
		if not grant is Dictionary or not _integer(grant.get("cycle"), 1) or grant.get("cycle") != index + 2 or not grant.get("effect") is Dictionary:
			return {}
		grant.cycle = int(grant.cycle)
	var run: Dictionary = value.run
	var challenge = preload("res://scripts/competition/challenge.gd").new()
	if not run.has("challenge"): run.challenge = challenge.fresh()
	if not run.challenge is Dictionary or not challenge.validate(run.challenge): return {}
	for key in ["by_promotion", "perfect_recipes"]:
		for id in run.challenge.stats[key]:
			if id not in recipe_ids: return {}
	for id in run.challenge.stats.careful_guests:
		if id not in customer_ids: return {}
	for reservation in run.challenge.reservations:
		if reservation.customer not in customer_ids: return {}
	if not run.challenge.retry.is_empty():
		var retry = decode(run.challenge.retry, depth + 1)
		if retry.is_empty(): return {}
		run.challenge.retry = retry
	if not run.get("stock_only_mode") is bool or run.get("selection_step") not in ["rival", "companion"] or not run.get("daily_events") is Dictionary: return {}
	if not competition_defaults.daily_events.validate(run.daily_events): return {}
	if not run.get("tutorial") is bool or not run.has("rng"):
		return {}
	if not run.rng is Dictionary:
		return {}
	for field in ["seed", "state"]:
		var encoded = run.rng.get(field)
		if not encoded is String or not encoded.is_valid_int() or str(int(encoded)) != encoded:
			return {}

	if run.get("pricing_catalog_version") != competition_defaults.catalog.catalog_version or run.get("rival_rules_version") != competition_defaults.rules.rules_version:
		return {}
	if not run.get("competition") is Dictionary:
		return {}
	if run.get("rival_id") != null and not run.get("rival_id") is String:
		return {}
	if run.get("rival_id") != (null if run.competition.get("rival", "") == "" else run.competition.get("rival")):
		return {}
	if not run.get("stock_ledger") is Dictionary or not _validate_ledger(run.stock_ledger):
		return {}
	if not _validate_competition(run.competition):
		return {}
	for field in ["phase", "companion", "promotion_id"]:
		if not run.get(field) is String:
			return {}
	if run.get("phase") not in ["selection", "preparation", "promotion", "reception", "shop"]:
		return {}
	for field in ["money", "equipment", "guest_index", "day_income", "day_served", "day_success"]:
		if not _integer(run.get(field)):
			return {}
	if not _integer(run.get("day"), 0 if run.stock_only_mode and run.phase in ["selection", "preparation"] else 1):
		return {}
	if run.phase == "preparation" and (not run.stock_only_mode or (int(run.day) != 0 and run.challenge.phase not in ["preparation", "rest"])): return {}
	if not run.get("tiers") is Dictionary or not run.get("stock") is Dictionary or not run.get("rumors") is Array or not run.get("queue") is Array:
		return {}
	var companions = config.companions.map(func(item): return item.id)
	if run.get("companion") not in companions or (run.get("promotion_id") != "" and run.get("promotion_id") not in recipe_ids):
		return {}
	challenge.state = run.challenge
	var companion_model = preload("res://scripts/game/companion_progress.gd").new()
	if not run.has("companion_progress"):
		if run.companion in ["merchant", "banker", "patron"]: return {}
		run.companion_progress = companion_model.fresh(run.companion)
		run.companion_progress.round = int(run.challenge.round)
		run.companion_progress.locked = run.challenge.phase in ["preparation", "active", "result"]
	if not run.companion_progress is Dictionary or run.companion_progress.get("id") != run.companion or not companion_model.validate(run.companion_progress, config, challenge, liquid_names): return {}
	if not run.companion_progress.pending_rival.is_empty() and run.challenge.phase in ["active", "preparation"]: return {}
	for date in run.companion_progress.valid_by_day:
		if int(date) > int(run.day): return {}
	for date in run.companion_progress.interest_days:
		if int(date) > int(run.day): return {}
	if run.companion_progress.locked and run.challenge.phase not in ["preparation", "active", "result"]: return {}
	for result in run.challenge.results:
		if not result.has("companion_result"): continue
		var record = result.companion_result
		if not record is Dictionary or record.size() != 4 or not record.get("progress") is Dictionary or not _integer(record.get("start_day"), 1): return {}
		var previous = preload("res://scripts/competition/challenge.gd").new()
		previous.state.stats = result.stats
		record.start_day = int(record.start_day)
		previous.state.start_day = int(record.start_day)
		previous.state.round = int(record.progress.get("round", -1))
		previous.state.rival = result.rival
		if record.get("id") != record.progress.get("id") or record.get("outcome") != record.progress.get("outcome") or record.outcome not in ["success", "ordinary", "failure"]: return {}
		if not companion_model.validate(record.progress, config, previous, liquid_names): return {}
		if (record.outcome == "failure") == result.won: return {}
	if run.tiers.size() != config.base_tiers.size() or run.stock.size() != liquid_names.size():
		return {}
	for family in config.base_tiers:
		if not _integer(run.tiers.get(family)) or int(run.tiers[family]) >= config.base_tiers[family].size():
			return {}
		run.tiers[family] = int(run.tiers[family])
	for liquid in liquid_names:
		var amount = run.stock.get(liquid)
		if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount) < 0:
			return {}
	for rumor in run.rumors:
		if not rumor is String:
			return {}
	var notes = preload("res://scripts/game/journal_notes.gd")
	if not run.get("journal_favorites", []) is Array: return {}
	for favorite in run.get("journal_favorites", []):
		if not favorite is String: return {}
	run.rumors = notes.normalize(run.rumors)
	run.journal_favorites = notes.normalize(run.get("journal_favorites", []))
	for favorite in run.journal_favorites:
		if favorite not in run.rumors: return {}
	if not run.get("journal_speakers", {}) is Dictionary: return {}
	var speakers = {}
	for text in run.get("journal_speakers", {}):
		if not text is String or not run.journal_speakers[text] is Array: return {}
		var note = notes.clean(text)
		if note not in run.rumors: return {}
		if not speakers.has(note): speakers[note] = []
		for id in run.journal_speakers[text]:
			if id not in customer_ids: return {}
			if id not in speakers[note]: speakers[note].append(id)
	run.journal_speakers = speakers
	for order in run.queue:
		if not order is Dictionary or order.get("recipe_id") not in recipe_ids or not _integer(order.get("customer_index")):
			return {}
		if int(order.customer_index) >= customer_count:
			return {}
		if order.has("patience") and (not _number(order.patience) or float(order.patience) <= 0):
			return {}
		if order.has("event_offer") or order.has("event_rolls"):
			if not _integer(order.get("event_offer"), -1) or int(order.event_offer) >= run.daily_events.records.size() or not order.get("event_rolls") is Array: return {}
			for roll in order.event_rolls:
				if not roll is Dictionary or not _integer(roll.get("index")) or int(roll.index) >= run.daily_events.records.size() or not _number(roll.get("roll")) or float(roll.roll) >= 1: return {}
				roll.index = int(roll.index)
			order.event_offer = int(order.event_offer)
			if order.get("message_kind") not in ["event", "smalltalk"] or not order.get("message_text") is String or not order.get("message_claim") is String: return {}
			if not order.message_claim.is_empty() and order.message_claim not in competition_defaults.daily_events.rules.claims: return {}
			if order.has("verification_text") and not order.verification_text is String: return {}
		if order.has("event_appraisal"):
			if not _integer(order.event_appraisal) or int(order.event_appraisal) >= run.daily_events.records.size(): return {}
			if run.daily_events.records[int(order.event_appraisal)].id != "paid_reviews": return {}
			order.event_appraisal = int(order.event_appraisal)
		if order.has("companion_scored") and not order.companion_scored is bool: return {}
		if order.has("unavailable") and not order.unavailable is bool: return {}
		order.customer_index = int(order.customer_index)
		if order.has("quote"):
			var q = order.quote
			if not q is Dictionary or not _integer(q.get("price")) or not _integer(q.get("standard_price")) or not _integer(q.get("day"), 1) or not q.get("tiers") is Dictionary:
				return {}
			if q.has("margin_loss") and (not _number(q.margin_loss) or float(q.margin_loss) > 1): return {}
			if q.get("policy") not in ["hold", "follow", "premium"] or q.get("band") not in ["S", "M", "H"] or not q.get("active") is bool or not q.get("legal_substitute") is bool:
				return {}
			if q.get("rules_version") != competition_defaults.rules.rules_version or not q.get("negative_sources") is Dictionary or not q.get("viola") is Dictionary:
				return {}
			if not _number(q.get("positive_multiplier")) or not _number(q.get("premium_tip")):
				return {}
			for multiplier in q.negative_sources.values():
				if not _number(multiplier) or float(multiplier) > 1:
					return {}
			if not q.viola.is_empty():
				for field in ["min_base_tier", "wrong_cup_revenue_multiplier", "low_tier_revenue_multiplier", "compliant_tip_multiplier"]:
					if not _number(q.viola.get(field)):
						return {}
				if q.viola.get("premium_band") != "H":
					return {}
			for field in ["price", "standard_price", "day"]:
				q[field] = int(q[field])
			for family in q.tiers:
				if family not in config.base_tiers or not _integer(q.tiers[family]) or int(q.tiers[family]) >= config.base_tiers[family].size():
					return {}
				q.tiers[family] = int(q.tiers[family])
	if int(run.guest_index) > run.queue.size() or run.day_success > run.day_served or run.day_served != run.guest_index:
		return {}
	if run.phase == "reception" and int(run.guest_index) >= run.queue.size():
		return {}
	if run.phase == "shop" and (run.queue.is_empty() or int(run.guest_index) != run.queue.size()):
		return {}
	for field in ["money", "day", "equipment", "guest_index", "day_income", "day_served", "day_success"]:
		run[field] = int(run[field])
	meta.cycle = int(meta.cycle)
	meta.highest_cycle = int(meta.highest_cycle)
	if run.tutorial != (meta.cycle == 1): return {}
	return value

func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0

func _validate_ledger(ledger: Dictionary) -> bool:
	if not ledger.get("batches") is Dictionary or not ledger.get("daily") is Dictionary or not ledger.get("unknown_basis") is bool:
		return false
	for name in ledger.batches:
		if name not in liquid_names or not ledger.batches[name] is Array:
			return false
		for batch in ledger.batches[name]:
			if not batch is Dictionary or not _number(batch.get("ml")) or not _number(batch.get("unit_cost")):
				return false
			if batch.has("merchant_discount") and not batch.merchant_discount is bool: return false
	for key in ["liquor", "tips", "ingredients", "spoilage", "events", "procurement", "consumables"]:
		if not _number(ledger.daily.get(key)):
			return false
	for key in ["liquor", "tips", "events", "procurement"]:
		ledger.daily[key] = int(ledger.daily[key])
	if not ledger.get("history", []) is Array:
		return false
	for record in ledger.get("history", []):
		if not record is Dictionary or not _integer(record.get("day"), 0) or not record.get("account") is Dictionary or not (record.get("contribution") is float or record.get("contribution") is int):
			return false
		if not is_finite(float(record.contribution)):
			return false
		record.day = int(record.day)
		if not _validate_ledger({"batches": {}, "unknown_basis": false, "daily": record.account}):
			return false
	return true

func _validate_competition(value: Dictionary) -> bool:
	if value.size() != competition_defaults.state.size() or value.get("rules_version") != competition_defaults.rules.rules_version:
		return false
	for key in competition_defaults.state:
		var baseline = competition_defaults.state[key]
		var entry = value.get(key)
		if baseline is int:
			if not _integer(entry, -1000000):
				return false
			value[key] = int(entry)
		elif baseline is float:
			if not _number(entry):
				return false
		elif typeof(entry) != typeof(baseline):
			return false
	if not _validate_street(value.street): return false
	if value.rival != "" and value.rival not in competition_defaults.rules.rivals:
		return false
	if value.strategy not in ["hold", "follow", "premium"] or value.ending not in ["", "counterplay", "alliance", "takeover"]:
		return false
	for record in value.history:
		if not record is Dictionary or not _integer(record.get("day"), 1) or record.get("recipe_id") not in recipe_ids:
			return false
		record.day = int(record.day)
	for key in ["cooperation_days", "lock_days", "voluntary_skip_days"]:
		for index in range(value[key].size()):
			if not _integer(value[key][index], 1):
				return false
			value[key][index] = int(value[key][index])
	for key in value.markets:
		var m = value.markets[key]
		if not m is Dictionary or not _integer(m.get("day"), 0) or not (m.get("variation") is float or m.get("variation") is int):
			return false
		if not is_finite(float(m.variation)) or float(m.variation) < float(competition_defaults.rules.market.daily_variation_min) - 0.000001 or float(m.variation) > float(competition_defaults.rules.market.daily_variation_max) + 0.000001:
			return false
		if not m.get("outages") is Dictionary or not m.get("order") is Array or not m.get("substitutes") is Dictionary:
			return false
		m.day = int(m.day)
		if m.outages.size() > int(competition_defaults.rules.limits.max_outages_total):
			return false
		for name in m.outages:
			if name not in liquid_names or not _integer(m.outages[name], 1):
				return false
			m.outages[name] = int(m.outages[name])
	for key in value.locks:
		var lock = value.locks[key]
		if not lock is Dictionary or not lock.get("packs") is Dictionary or not lock.get("base_prices") is Dictionary or not lock.get("used") is Dictionary:
			return false
		for name in lock.packs:
			if name not in liquid_names or not _integer(lock.packs[name], 1) or not _number(lock.base_prices.get(name)) or not _integer(lock.used.get(name, 0)):
				return false
			if int(lock.used.get(name, 0)) > int(lock.packs[name]):
				return false
			lock.packs[name] = int(lock.packs[name])
			if lock.used.has(name):
				lock.used[name] = int(lock.used[name])
	return true

func _validate_street(s: Dictionary) -> bool:
	var baseline: Dictionary = competition_defaults.street.fresh()
	if s.size() != baseline.size(): return false
	for key in baseline:
		if baseline[key] is int:
			if not _integer(s.get(key), -1000000): return false
			s[key] = int(s[key])
		elif typeof(s.get(key)) != typeof(baseline[key]): return false
	if s.card != "" and (s.card not in competition_defaults.street.data.cards or not competition_defaults.street.data.cards[s.card].enabled): return false
	if abs(s.respect) > int(competition_defaults.street.data.numbers.respect_cap): return false
	if s.visit_answer != "" and s.visit_answer not in competition_defaults.street.data.responses: return false
	if s.ending not in ["", "counterplay", "alliance", "coexist"]: return false
	if s.copies.size() > int(competition_defaults.street.data.numbers.max_copies): return false
	for copy in s.copies:
		if not copy is Dictionary or copy.get("kind") not in ["card", "recipe"] or not _integer(copy.get("day"), 1) or not copy.get("half") is bool: return false
		copy.day = int(copy.day)
		if copy.get("target") not in (competition_defaults.street.data.cards.keys() if copy.kind == "card" else recipe_ids): return false
	for notice in s.notices:
		if not notice is String: return false
	var c = s.captain
	if c.size() != baseline.captain.size(): return false
	if not _integer(c.get("visits")) or int(c.visits) > competition_defaults.street.data.captain.beats.size() or not _integer(c.get("last_day")) or not _integer(c.get("answer"), -1) or int(c.answer) > 1 or not c.get("left") is bool or not c.get("last_line") is String: return false
	for key in ["visits", "last_day", "answer"]: c[key] = int(c[key])
	return true

func is_obsolete(source: Dictionary) -> bool:
	return _integer(source.get("version"), 1) and int(source.version) < VERSION and (source.has("run") or (source.has("money") and source.has("day")))
