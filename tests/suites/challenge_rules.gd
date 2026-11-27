extends SceneTree
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/update_20261125_cases.json"))
	var model = load("res://scripts/competition/challenge.gd").new()
	var recipes = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	var recipe: Dictionary = recipes.filter(func(item): return item.id == fixture.rotation[0])[0]
	model.prepare(fixture.rivals[0], 1)
	model.state.phase = "active"
	for day in range(1, int(model.rules.days) + 1):
		var count = model.count_for_day(int(model.rules.rivals.bella.promotion_guarantee), day, 5)
		model.register_day(day, count)
	check(model.state.stats.opportunities >= int(fixture.min_karn_opportunities), "maximum negative traffic still provides Karn's budget")
	check(not model.finish(int(model.rules.days) - 1) and model.active(), "no early settlement even when a threshold could be met")
	var order = {"promotion_id": recipe.id}
	model.score(order, fixture.special_customer, recipe, 1, true, true, true, true, 2, false, 1)
	check(model.state.stats.valid == 1 and model.state.stats.careful == 1 and model.state.stats.perfect == 0, "minor production errors can count for service but not perfection")
	model.score(order, fixture.special_customer, recipe, 1, true, true, true, true, 0, true, 1)
	check(model.state.stats.valid == 1, "one order cannot be scored twice")
	model.score({"event_appraisal": 0}, fixture.special_customer, recipe, 1, true, true, true, true, 0, true, 1)
	check(model.state.stats.valid == 1, "system task is excluded")
	model.score({}, fixture.special_customer, recipe, 0, false, true, true, true, 0, true, 1)
	check(model.state.stats.valid == 1, "no revenue or abandoned order never counts")
	model.score({}, fixture.special_customer, recipe, 1, true, true, false, true, 0, true, 1)
	check(model.state.stats.careful == 1, "no valid response means no careful service")
	model.score({}, fixture.special_customer, recipe, 1, true, true, true, true, 0, false, 1)
	check(model.state.stats.perfect == 1, "only order with sufficiently high actual grades counts as high-tier perfect")
	model.prepare("duren", int(model.rules.days) + 1)
	model.state.phase = "active"
	model.state.stats.opportunities = 1000
	model.state.stats.valid = int(float(fixture.trial_ratio) * 1000)
	model.state.stats.net = float(model.rules.rivals.duren.metrics[1].target)
	check(not model.won(), "84.6 percent does not round up to 85 percent")
	model.prepare("olga", 1)
	model.state.phase = "active"
	check(model.state.opportunities.size() == model.rules.rivals.olga.due_days.size(), "all dedicated previews exist before play")
	var slots = 0
	for opportunity in model.state.opportunities:
		check(int(opportunity.notice) < int(opportunity.due) and int(opportunity.due) <= int(model.rules.days), "every preview precedes this round's opportunity")
		slots += int(model.rules.rivals.olga.orders_per_opportunity)
	check(slots >= int(fixture.min_olga_opportunities), "eighteen potential opportunities, not only twelve")
	var first = model.state.opportunities[0]
	model.register_day(int(first.due), int(model.rules.rivals.olga.orders_per_opportunity) + 2)
	var target: Dictionary = recipes.filter(func(item): return item.id == first.recipe)[0]
	model.score({"promotion_id": first.recipe}, fixture.special_customer, target, 1, true, true, true, true, 0, true, int(first.due))
	check(model.state.stats.trend_hits == 0, "an unheard ordinary trend gives no challenge credit")
	check(not model.plan(first, int(first.notice), true), "preparation requires prior hearing")
	model.heard(first, int(first.notice))
	check(not model.plan(first, int(first.notice), false), "hearing does not invent inventory")
	check(not model.plan(first, int(first.due), true), "preparing after a trend starts is too late")
	check(model.plan(first, int(first.notice), true), "earlier shop preparation can be linked to a forecast")
	for index in int(model.rules.rivals.olga.orders_per_opportunity):
		model.score({"promotion_id": first.recipe}, fixture.special_customer, target, 1, true, true, true, true, 0, true, int(first.due))
	check(model.state.stats.trend_hits == model.rules.rivals.olga.orders_per_opportunity and model.state.stats.hit_events.size() == 1, "multiple orders from one event count as one distinct opportunity")
	var before = model.state.stats.trend_hits
	model.score({"promotion_id": fixture.rotation[-1]}, fixture.special_customer, target, 1, true, true, true, true, 0, true, int(first.due))
	check(model.state.stats.trend_hits == before + 1, "a prepared trend can be fulfilled without adding a current-promotion restriction")
	var valid = model.state.duplicate(true)
	check(model.validate(valid), "authored challenge state validates")
	var bad = valid.duplicate(true)
	bad.stats.valid = NAN
	check(not model.validate(bad), "non-finite statistics are rejected")
	bad = valid.duplicate(true)
	bad.opportunities[0].end = bad.opportunities[0].due
	check(not model.validate(bad), "invalid trend window is rejected")
	var competition = load("res://scripts/competition/competition.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/competition.json")))
	competition.modern_mode = true
	var pricing = load("res://scripts/economy/pricing.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://data/prices.json")))
	var event: Dictionary = competition.daily_events.rules.events[fixture.rise_event]
	competition.daily_events.state.records = [{"id": fixture.rise_event, "day": 1, "due": 2, "heard": true, "resolved": false, "mitigation": "", "action_day": 0}]
	var affected: Dictionary = recipes.filter(func(item): return (item.ingredients + item.topup).any(func(portion): return portion.name == event.ingredient))[0]
	var baseline = pricing.calculate(affected)
	check(competition.quote(affected, baseline, 2, {}).price == competition.money(float(baseline.price) * float(event.multiplier)), "free trading keeps ordinary event drink pricing")
	check(competition.market(2).outages.is_empty(), "free trading does not restore an old rival's supply restrictions")
	print("CHALLENGE RULES: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
