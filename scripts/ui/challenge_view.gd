extends RefCounted
var game

func _init(owner) -> void:
	game = owner

func progress(parent: Node) -> void:
	var model = game.challenge
	if model.state.phase not in ["preparation", "active", "result"]: return
	model.update_net(game.stock_ledger, game.day)
	game._label(parent, model.rules.text.progress.format({"day": model.day(game.day), "days": int(model.rules.days), "calendar": game.day}), 18, game.GOLD)
	for metric in model.rules.rivals[model.state.rival].metrics:
		game._label(parent, metric_text(metric), 16, game.MINT)
	if model.state.phase == "preparation":
		game._button(parent, model.rules.text.details, details)
	game._button(parent, game.story_catalog.content.companions.progress.format({"name": game.companion.name}), companion_dialog)

func metric_text(metric: Dictionary) -> String:
	var actual = game.challenge.value(metric.key)
	var target = float(metric.target)
	return game.challenge.rules.text.metric.format({"label": metric.label, "actual": metric_number(metric.key, actual), "target": metric_number(metric.key, target), "remaining": metric_number(metric.key, maxf(0, target - actual))})

func metric_number(key: String, number: float) -> String:
	if key == "fulfillment": return "%.2f%%" % (number * 100)
	if key == "net": return "%.2f" % number
	return str(int(number))

func details() -> void:
	var dialog = AcceptDialog.new()
	dialog.theme = game.theme
	dialog.title = game.challenge.rules.text.heading
	dialog.dialog_text = "\n\n".join([game.challenge.rules.text.rules, game.challenge.rules.text.net, game.challenge.rules.text.careful, game.challenge.rules.text.quality])
	game.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(680, 430))

func selection(replay = false) -> void:
	game.playing = false
	game._clear(game.page)
	game._header(game.challenge.rules.text.heading)
	var column = game._scroll_column(game.page)
	for id in game.challenge.rules.rivals:
		if not replay and id in game.challenge.state.defeated: continue
		if game.challenge.state.phase == "free" and not game.challenge.state.results.is_empty() and not game.challenge.state.results[-1].won and id != game.challenge.state.rival: continue
		var card = game._panel(column)
		game._label(card, game.competition.data.rivals[id].name, 24, game.GOLD)
		for metric in game.challenge.rules.rivals[id].metrics:
			game._label(card, "%s：%s" % [metric.label, ("%.0f%%" % (float(metric.target) * 100)) if metric.key == "fulfillment" else str(int(metric.target))], 18)
		if id == "viola": game._label(card, game.challenge.rules.text.quality, 16)
		game._button(card, game.challenge.rules.text.confirm, choose_companion.bind(id))
	game._button(game.page, game.challenge.rules.text.free, free_trade)

func choose_companion(id: String, save = true) -> void:
	if game.challenge.state.phase in ["preparation", "active"] and game.companion_progress.state.locked: return
	game.companion_progress.state.pending_rival = id
	if save: game._save(game.current_phase)
	game.playing = false
	game.screen = "selection"
	game.sound.enter("selection")
	game.tutorial_context = ""
	game._clear(game.page)
	var selector = preload("res://scripts/ui/selection/character_selection.gd").new()
	selector.settings = game._read_json("res://data/character_selection.json")
	selector.settings.companion_heading = game.story_catalog.content.companions.heading
	selector.settings.companion_hint = game.story_catalog.content.companions.locked
	if game.pause_menu.reduced_motion: selector.settings.select_seconds = 0.0
	selector.sound = game.sound
	selector.artwork = game.character_art
	selector.entries = game.config.companions.duplicate(true)
	game.page.add_child(selector)
	selector.confirmed.connect(func(entry):
		game.companion = game.config.companions.filter(func(item): return item.id == entry.id)[0]
		start(id))
	selector.back_requested.connect(func():
		game.companion_progress.state.pending_rival = ""
		game._save(game.current_phase)
		selection(game.challenge.state.defeated.size() == game.challenge.rules.rivals.size()))

func start(id: String) -> void:
	if game.challenge.state.phase in ["preparation", "active"] and game.companion_progress.state.locked: return
	var model = game.challenge
	var ordinary_events = game.competition.daily_events.state.duplicate(true)
	var captain = game.competition.state.street.captain.duplicate(true)
	var reputation = game.competition.state.reputation
	game.competition.reset(id)
	game.competition.state.street.enabled = true
	game.competition.state.street.captain = captain
	game.competition.state.reputation = reputation
	game.competition.daily_events.state = ordinary_events
	game.queue = []
	game.guest_index = 0
	game.day_served = 0
	game.day_success = 0
	game.day_income = 0
	game.day_consumable_budget = 0.0
	game.stock_ledger.new_day()
	game.companion_progress.state.locked = false
	model.prepare(id, game.day + 1)
	game._sync_challenge()
	game.companion_progress.prepare(game)
	model.state.retry = game._snapshot("preparation")
	game._save("preparation")
	game.show_shop()

func free_trade() -> void:
	var ordinary_events = game.competition.daily_events.state.duplicate(true)
	var captain = game.competition.state.street.captain.duplicate(true)
	var reputation = game.competition.state.reputation
	game.competition.reset("")
	game.competition.state.street.captain = captain
	game.competition.state.reputation = reputation
	game.competition.daily_events.state = ordinary_events
	game.companion_progress.state.locked = false
	game.challenge.state.phase = "free"
	game._sync_challenge()
	game._save("shop")
	game.show_shop()

func rest() -> void:
	var ordinary_events = game.competition.daily_events.state.duplicate(true)
	var captain = game.competition.state.street.captain.duplicate(true)
	var reputation = game.competition.state.reputation
	game.competition.reset("")
	game.competition.state.street.captain = captain
	game.competition.state.reputation = reputation
	game.competition.daily_events.state = ordinary_events
	game.companion_progress.state.locked = false
	game.challenge.state.phase = "rest"
	game._sync_challenge()
	game._save("preparation")
	game.show_shop()

func retry() -> void:
	var snapshot: Dictionary = game.challenge.state.retry.duplicate(true)
	if snapshot.is_empty() or game.save_schema.decode(snapshot).is_empty(): return
	game._restore_document(snapshot)
	game.challenge.state.retry = snapshot
	game._save("preparation")
	game.show_shop()

func result() -> void:
	var model = game.challenge
	game.playing = false
	game.sound.enter("ending")
	game._clear(game.page)
	game._header(model.rules.text.heading)
	var column = game._scroll_column(game.page)
	var victory = model.won()
	game._label(column, model.rules.text.won if victory else model.rules.text.lost, 30, game.GOLD)
	progress(column)
	if victory: game._label(column, model.rules.text.closing[model.state.rival], 22, game.MINT)
	companion_details(column)
	var prose: Dictionary = game.story_catalog.content.companions
	var outcome: String = game.companion_progress.state.outcome
	if outcome == "success":
		var ending: Dictionary = prose.result[game.companion.id]
		game._label(column, ending.title, 28, game.GOLD)
		game._label(column, ending.action, 19, game.MINT)
		game._label(column, ending.line, 23)
	elif not outcome.is_empty():
		game._label(column, prose.failure if outcome == "failure" else prose.ordinary, 24, game.GOLD)
		if not prose.pending_prose.is_empty(): game._label(column, prose.pending_prose, 16, game.MUTED)
	if model.state.defeated.size() == model.rules.rivals.size() and not model.state.finale_seen:
		game._label(column, model.rules.text.finale, 30, game.GOLD)
		game._label(column, model.rules.text.recollections, 18)
		for entry in model.state.results:
			game._label(column, "%s · %d单 · 用心%d · 高阶完美%d · 行情%d · 净收益¥%.2f" % [game.competition.data.rivals[entry.rival].name, entry.stats.valid, entry.stats.careful, entry.stats.perfect, entry.stats.trend_hits, entry.stats.net], 16)
		for id in model.rules.text.closing: game._label(column, model.rules.text.closing[id], 17)
		if not model.state.finale_seen:
			model.state.finale_seen = true
			game._save("shop")
		game._button(column, model.rules.text.replay, selection.bind(true))
	elif model.state.defeated.size() == model.rules.rivals.size():
		game._button(column, model.rules.text.replay, selection.bind(true))
	elif victory:
		game._button(column, model.rules.text.next, selection)
		game._button(column, model.rules.text.rest, rest)
	if victory: game._button(column, model.rules.text.free, free_trade)
	else:
		game._button(column, model.rules.text.retry, retry)
		game._button(column, model.rules.text.accept, free_trade)

func opportunities(parent: Node) -> void:
	var model = game.challenge
	if model.state.rival != "olga" or model.state.phase not in ["preparation", "active"]: return
	for opportunity in model.state.opportunities:
		if game.day < int(opportunity.notice) or game.day >= int(opportunity.due): continue
		var card = game._panel(parent)
		game._label(card, model.rules.text.olga_notice.format({"drink": game._find_recipe(opportunity.recipe).name, "due": int(opportunity.due) - int(model.state.start_day) + 1}), 16, game.MINT)
		if int(opportunity.heard) < 0:
			game._button(card, model.rules.text.olga_hear, func():
				model.heard(opportunity, game.day)
				game._save("preparation" if game._in_preparation() else "shop")
				game.show_shop())
		else:
			game._button(card, model.rules.text.olga_prepare.format({"drink": game._find_recipe(opportunity.recipe).name}), func():
				if model.plan(opportunity, game.day, game._can_serve(game._find_recipe(opportunity.recipe))):
					game._save("preparation" if game._in_preparation() else "shop")
					game.show_shop()
				else: game.status_line.text = model.rules.text.olga_missing)
			if int(opportunity.prepared) >= 0: game._label(card, model.rules.text.olga_prepared, 14)

func companion_details(parent: Node) -> void:
	for line in game.companion_progress.lines(game): game._label(parent, line, 17, game.MINT)

func companion_dialog() -> void:
	game.challenge.update_net(game.stock_ledger, game.day)
	var dialog = AcceptDialog.new()
	dialog.theme = game.theme
	dialog.title = game.story_catalog.content.companions.progress.format({"name": game.companion.name})
	dialog.dialog_text = "\n\n".join(game.companion_progress.lines(game))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	game.add_child(dialog)
	dialog.popup_centered(Vector2i(760, 460))
