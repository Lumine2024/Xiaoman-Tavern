extends SceneTree
var failures = 0
var checks = 0
var requested: Array[String] = []
var played: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/sfx_delivery_cases.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.config.save_path = fixture.save_path
	game.set_process(false)
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game._begin_rival_run(game.config.companions[0], fixture.rival, true)
	for ingredient in game.stock: game.stock[ingredient] = float(fixture.stock_ml)
	game.stock_ledger.reset(game.stock)
	game.queue = [{"recipe_id": fixture.recipe, "customer_index": 0}]
	game.guest_index = 0
	game._start_guest()
	game.sound.cue_requested.connect(func(id): requested.append(id))
	game.sound.cue_played.connect(func(id): played.append(id))
	game.brew.stage = 3
	game._select_ice(fixture.silent_ice)
	check(not requested.has(fixture.ice_cue) and not played.has(fixture.ice_cue), "no-ice selection requests no ice audio")
	game._select_ice(fixture.audible_ice)
	check(requested.count(fixture.ice_cue) == 1 and played.has(fixture.ice_cue), "real ice selection reaches delivered Ogg playback")
	game.brew.stage = 2
	game.workbench.straight_focus.settings.hold_seconds = float(fixture.shake_seconds)
	game.pause_menu.reduced_motion = false
	var rng_before = game.rng.state
	game._finish_straight()
	await create_timer(float(fixture.start_wait)).timeout
	check(game.workbench.straight_shake_left > 0 and played.has(fixture.straight_cue), "straight animation plays actual shaker audio while moving")
	check(game.sound.loops.has("mix") and game.sound.loops.mix.playing, "straight sound is a real loop player")
	paused = true
	game.sound.set_paused(true)
	check(game.sound.loops.mix.stream_paused, "pause freezes straight shaking audio")
	paused = false
	game.sound.set_paused(false)
	await create_timer(float(fixture.finish_wait)).timeout
	check(game.workbench.straight_shake_left == 0 and not game.sound.loops.mix.playing, "straight audio stops when visual shaking finishes")
	check(game.rng.state == rng_before, "operation audio does not alter business RNG")
	game.brew.stage = 2
	game.pause_menu.reduced_motion = true
	var before = played.count(fixture.straight_cue)
	game._finish_straight()
	await create_timer(float(fixture.start_wait)).timeout
	check(played.count(fixture.straight_cue) == before, "reduced-motion path skips both shaking and its sound")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("SFX DELIVERY: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
