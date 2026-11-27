extends SceneTree
const Report = preload("res://scripts/brewing/mistake_report.gd")
var game
var fixture: Dictionary
var output = ""
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func frames() -> void:
	await process_frame
	await process_frame
	await process_frame
func capture(label: String) -> void:
	await frames()
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func make_drink(case: Dictionary):
	var recipe: Dictionary = game._find_recipe(case.recipe).duplicate(true)
	var customer: Dictionary = game.customers.filter(func(item): return item.story_id == fixture.standard_customer)[0].duplicate(true)
	customer.order_spec = {}
	if case.get("solids", false): recipe.pre_solids = fixture.synthetic_pre_solids.duplicate(true)
	if case.get("no_ice", false): customer.no_ice = true
	if case.get("reservation", false):
		customer.reservation_optional = {}
		for item in recipe.ingredients:
			customer.reservation_optional[item.name] = item.amount
			item.amount = game.rulings.reservation.amounts.get(item.name, item.amount)
	var brew = game.BrewModel.new(game.config, recipe, customer)
	while brew.stage < 2:
		var item = brew.target()
		var amount = float(item.amount)
		if case.get("reservation", false): amount = float(customer.reservation_optional[item.name])
		var first = brew.ingredient_index == 0
		if first and case.get("amount", false): amount *= float(fixture.quantity_multiplier)
		if first and case.get("mixed", false):
			brew.add_liquid(item.name, float(fixture.mixed_amount))
			brew.add_liquid(fixture.wrong_liquid, amount - float(fixture.mixed_amount))
		else: brew.add_liquid(fixture.wrong_liquid if first and case.get("ingredient", false) else item.name, amount)
		brew.transfer()
	brew.mix_at(float(fixture.bad_mix) if case.get("mix", false) else float(game.config.mix_target))
	brew.choose_vessel(fixture.wrong_cup if case.get("cup", false) else recipe.cup, fixture.wrong_ice if case.get("ice", false) else brew.expected_ice())
	brew.finish_pour()
	for item in recipe.topup: brew.add_topup(fixture.wrong_topup if case.get("topup", false) else item.name)
	brew.handle_special(not case.get("special", false))
	if not case.get("missing", false):
		for item in brew.expected_garnishes(): brew.add_garnish(item)
	if case.get("extra", false): brew.add_garnish(fixture.wrong_garnish)
	return brew

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/message_reasons_cases.json"))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game._begin_rival_run(game.config.companions[0], fixture.rival, true)
	game.set_process(false)
	game.stock_only_mode = true
	game._sync_challenge()
	game.queue = [{"recipe_id": fixture.recipe, "customer_index": 0}]
	game._start_guest()
	game.set_process(false)
	var checkpoint = game.reception_checkpoint.duplicate(true)
	var old = game._snapshot("reception")
	old.run.erase("journal_speakers")
	old.run.rumors = [fixture.old_message]
	var decoded = game.save_schema.decode(old)
	check(not decoded.is_empty() and decoded.run.journal_speakers.is_empty(), "older v8 messages do not gain invented speakers")
	game._record_rumor(fixture.old_message)
	check(game._journal_speaker_text(fixture.old_message) == game.interface.journal.unknown_speaker, "source-less records explicitly show unrecorded source")
	for id in fixture.speakers:
		game.guest = game.customers.filter(func(customer): return customer.story_id == id)[0].duplicate(true)
		game.queue[0].message_text = fixture.message
		game.dialogue = 1
		game.brew.stage = 2
		game._advance_dialogue(0)
	check(game.journal_speakers[fixture.message] == fixture.speakers and game.rumors.count(fixture.message) == 1, "shared wording records each actual speaker without duplicate messages")
	game._record_rumor(fixture.message, fixture.speakers[0])
	check(game.journal_speakers[fixture.message].size() == fixture.speakers.size(), "repeat hearings do not duplicate the speaker")
	game.dialogue = 2
	game.guest.rumor = fixture.message
	game.intel_level = "full"
	game._advance_dialogue(0)
	check(game.journal_speakers[fixture.message].size() == fixture.speakers.size(), "third-segment rival conversation preserves the actual speaker")
	game.journal_favorites = [fixture.message]
	game.pause_menu.open_journal("messages")
	await frames()
	var book = game.pause_menu.journal
	var search = book.body.find_child("JournalSearch", true, false)
	search.text = fixture.speakers[0]
	search.text_changed.emit(search.text)
	check(book.filtered() == [fixture.message], "message search also finds speaker names")
	for window in fixture.windows:
		root.size = Vector2i(window[0], window[1])
		await capture("-speakers-" + str(int(window[0])))
	book.delete_notes([fixture.message])
	check(not game.journal_speakers.has(fixture.message), "deletion removes matching speaker metadata")
	book.undo_delete()
	check(game.journal_speakers[fixture.message] == fixture.speakers and fixture.message in game.journal_favorites, "undo restores speakers and favorite together")
	var saved = game.save_store.load_snapshot(fixture.save_path, game.save_schema.decode)
	check(not saved.is_empty() and saved.run.journal_speakers[fixture.message] == fixture.speakers, "source metadata is saved during the current order")
	check(saved.run.stock == checkpoint.run.stock and saved.run.rng == checkpoint.run.rng, "attribution does not advance the economic checkpoint or RNG")
	var invalid = saved.duplicate(true)
	invalid.run.journal_speakers[fixture.message] = [fixture.invalid_speaker]
	check(game.save_schema.decode(invalid).is_empty(), "unknown speaker identity is rejected")
	invalid = saved.duplicate(true)
	invalid.run.journal_speakers[fixture.message] = fixture.speakers[0]
	check(game.save_schema.decode(invalid).is_empty(), "malformed speaker container is rejected")
	game.pause_menu.close()
	check(game._load_game() and game.journal_speakers[fixture.message] == fixture.speakers, "actual reload preserves attribution")
	game.set_process(false)
	var modifiers = {"low_tier": false, "exclude_cup": false}
	for case in fixture.cases:
		var brew = make_drink(case)
		game.brew = brew
		game.guest = brew.customer
		game.dialogue = 3
		var report = Report.build(game, modifiers, false)
		check(brew.final_errors() == int(case.errors) and report.count == int(case.errors), case.id + " preserves the numeric scoring contract")
		check(report.items.map(func(item): return item.code) == case.codes, case.id + " reports exactly the counted causes")
		for item in report.items: check(not Report.reason(game, item).is_empty(), case.id + " formats actual data into a readable cause")
	game.brew = make_drink(fixture.cases[0])
	game.guest = game.brew.customer
	game.dialogue = 1
	var report = Report.build(game, modifiers, false)
	check(report.count == 2 and report.items.map(func(item): return item.data.segment) == [2, 3], "each uncompleted conversation contributes one named point")
	game.dialogue = 3
	game.guest.order_spec = {"recipe": fixture.recipe, "minimum_tier": game.config.base_tiers.values()[0].size()}
	report = Report.build(game, modifiers, false)
	check(report.count == 1 and report.items[0].code == "tier" and not report.items[0].data.details.is_empty(), "requested grade shortfall names the actual family and levels")
	game.guest.order_spec.minimum_tier = int(game.competition.rules.rivals.viola.min_base_tier)
	report = Report.build(game, {"low_tier": true, "exclude_cup": false}, false)
	check(report.count == 0 and "tier_excluded" in report.notes, "existing rival grade exclusion is explained without double scoring")
	game.brew = make_drink(fixture.cases.filter(func(case): return case.id == "cup")[0])
	game.guest = game.brew.customer
	report = Report.build(game, {"low_tier": false, "exclude_cup": true}, false)
	check(report.count == 0 and "cup_excluded" in report.notes, "existing cup exclusion is explained without adding a point")
	game.remaining = 0
	report = Report.build(game, modifiers, true)
	check("timeout" in report.notes and report.count == game.brew.final_errors(), "timeout is shown as status rather than invented additional mistakes")
	game.remaining = float(game.dialogue_rules.base_patience)
	report = Report.build(game, modifiers, true)
	check("abandoned" in report.notes, "voluntary abandonment is distinguished from elapsed time")
	game.brew = make_drink(fixture.cases[-1])
	game.guest = game.brew.customer
	game.dialogue = 1
	game.playing = true
	game._settle(false)
	check(game.last_mistake_report.count == int(fixture.cases[-1].errors) + 2, "actual settlement uses the same detailed report for its score")
	check(game.page.find_children("MistakeReason_*", "Label", true, false).size() == game.last_mistake_report.items.size(), "settlement displays every counted cause in its scrolling details")
	for window in fixture.windows:
		root.size = Vector2i(window[0], window[1])
		await capture("-mistakes-" + str(int(window[0])))
		check(game.get_global_rect().encloses(game.page.get_global_rect()), "settlement remains within window " + str(int(window[0])))
	for path in protected: check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real user data protected: " + path)
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.queue_free()
	await frames()
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("MESSAGE SOURCES AND MISTAKES: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
