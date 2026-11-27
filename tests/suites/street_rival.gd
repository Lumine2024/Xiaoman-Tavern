extends SceneTree
var game
var checks = 0
var failures = 0
var fixture: Dictionary
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/street_rival_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.interface.slots.profile_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	game._begin_rival_run(game.config.companions[0], "karn")
	check(game.competition.narrative(), "new run uses authored pilot")
	game._finish_preparation()
	check(game.current_phase == "promotion" and game.competition.state.street.card.is_empty(), "notice precedes card choice and menu")
	for size in fixture.windows:
		root.size = Vector2i(size[0], size[1])
		await capture("-cards-" + str(size[0]))
		for button in game.page.find_children("*", "Button", true, false):
			if button.text.begins_with("选「") and not button.disabled:
				check(button.get_global_rect().size.y > 0 and game.get_global_rect().has_point(button.get_global_rect().get_center()), "enabled counter card is visible inside viewport")
	game._select_counter_card("follow")
	check(game.competition.state.street.card == "follow", "card confirmation")
	check(not game.competition.street.choose(game.competition.state.street, "offset", game.day), "locked after selection")
	game._open_day(true)
	if not game.competition.state.receipts.has("opening"): game._answer_opening(game.competition.street.data.responses.keys()[0])
	check(game.queue.size() > 0 and game.current_phase == "reception", "real menu opens stock-only orders")
	check(game.last_save_ok, "real reception snapshot validates")
	var saved = game._snapshot("reception")
	check(not game.save_schema.decode(saved).is_empty(), "v7 roundtrip")
	var old = saved.duplicate(true)
	old.version = 6
	old.run.competition.erase("street")
	var migrated = game.save_schema.decode(old)
	check(migrated.is_empty(), "old documents are rejected without migration")
	var bad = saved.duplicate(true)
	bad.run.competition.street.respect = fixture.bad_respect
	check(game.save_schema.decode(bad).is_empty(), "invalid respect rejected")
	bad = saved.duplicate(true)
	bad.run.competition.street.copies = [{"kind": "recipe", "target": "invalid", "day": 1, "half": false}]
	check(game.save_schema.decode(bad).is_empty(), "invalid copied recipe rejected")
	var c = game.competition
	c.reset("karn")
	c.state.street.enabled = true
	c.street.choose(c.state.street, "follow", 1)
	for day in range(1, int(fixture.max_day) + 1):
		c.begin_day(game._find_recipe(fixture.simple), day)
		if day == int(fixture.observe_end): check(c.state.street.copies.size() == 1 and c.summary(day).contains(c.street.data.text.learning), "warning two days before copy")
		if day == int(fixture.copy_day):
			check(c.street.effective(c.state.street, day).is_empty(), "copy disables full card on D+2")
			check(c.quote(game._find_recipe(fixture.simple), game.pricing.calculate(game._find_recipe(fixture.simple)), day, game.tiers).margin_loss == 0, "disabled card removes margin cost too")
		check(abs(c.traffic_delta(game._find_recipe(fixture.simple), day)) <= int(c.street.data.numbers.traffic_cap), "traffic cap")
		if day == int(c.street.data.numbers.change_day):
			check(c.street.choose(c.state.street, "offset", day), "one change on D6")
			check(not c.street.choose(c.state.street, "attract", day), "no second change")
			check(c.street.respond(c.state.street, "reply", day), "D6 response")
			check(not c.street.respond(c.state.street, "irony", day), "D6 response cannot repeat")
		c.prepare_market(day, game.pricing.catalog, game.tiers, game.recipes, game.stock, game.rng)
		check(c.market(day + 1).outages.is_empty() and c.market(day + 1).variation == 0, "no unowned random market effects")
		c.close_day(game._find_recipe(fixture.simple), day)
	check(c.state.street.ending == "counterplay", "D14 non-match ending without rewards")
	check(c.state.permanent_traffic == 0, "no invented ending reward")
	check(c.state.street.copies.size() == int(c.street.data.numbers.max_copies), "copy limit across changed cards")
	var quiet = c.street.fresh()
	check(not c.street.respond(quiet, "reply", int(c.street.data.numbers.visit_day)), "no doorway taunt without advantage")
	for id in c.data.rivals:
		c.reset(id)
		c.state.street.enabled = true
		c.street.choose(c.state.street, "offset", 1)
		c.begin_day(game._find_recipe(fixture.medium), 1)
		for other in c.data.rivals:
			if other == id: continue
			check(not c.summary(1).contains(c.data.rivals[other].name) and not c.summary(1).contains(c.data.rivals[other].shop), "unselected rival absent from current street")
	var story = c.street.fresh()
	for beat in c.street.data.captain.beats:
		var guest = {"story_id": c.street.data.captain.id}
		c.street.captain_guest(story, guest, game.day, false)
		check(guest.get("topic") == beat.line, "captain advances one spoken beat")
		guest.longline_answer = 0
		c.street.captain_served(story, guest, game.day)
	check(story.captain.visits == c.street.data.captain.beats.size(), "five visits remembered")
	var blocked = {"story_id": c.street.data.captain.id}
	c.street.captain_guest(c.street.fresh(), blocked, game.day, true)
	check(not blocked.has("longline"), "competition interruption does not progress longline")
	game._begin_rival_run(game.config.companions[0], "karn")
	game._select_counter_card("offset")
	game.day = int(c.street.data.numbers.visit_day)
	game.competition.state.street.upper_hand = true
	game.competition.state.receipts.keep_card = true
	game.competition.state.history = [{"day": game.day - 1, "recipe_id": fixture.medium}]
	game.show_promotion()
	await capture("-visit")
	game._answer_street_visit("reply")
	check(game.competition.state.street.respect == 1, "actual doorway response persists respect")
	check(not game.save_schema.decode(game._snapshot("promotion")).is_empty(), "doorway state saves")
	game._next_cycle()
	check(game._snapshot("selection").run.competition.street.card.is_empty() and game.page.get_child(0).has_signal("confirmed"), "next narrative cycle draws a rival again")
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "user save protected")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("STREET RIVAL: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(1 if failures else 0)
