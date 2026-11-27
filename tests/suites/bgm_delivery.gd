extends SceneTree
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/bgm_delivery_cases.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	game.bar_ui.transitions.merge(fast, true)
	game._begin_rival_run(game.config.companions[0], fixture.rival, true)
	game.set_process(false)
	game.money = int(fixture.cash)
	for ingredient in game.stock: game.stock[ingredient] = float(fixture.stock_ml)
	game.stock_ledger.reset(game.stock)
	game.queue = [{"recipe_id": fixture.recipe, "customer_index": 0}]
	var audio = game.sound
	audio.set_level("master", 1)
	audio.set_level("music", 1)
	for case in fixture.cases:
		var previous: AudioStreamPlayer = audio.decks.music[int(audio.active_deck.music)]
		game.call(case.method)
		check(audio.context == case.context and audio.active_cue.music == case.cue, "real scene selects " + case.cue)
		var player: AudioStreamPlayer = audio.decks.music[int(audio.active_deck.music)]
		await create_timer(float(audio.manifest.settings.fade_seconds) + float(fixture.play_wait)).timeout
		check(player.playing and player.stream is AudioStreamOggVorbis and player.stream.loop, "delivered Ogg plays and loops: " + case.cue)
		check(audio.manifest.cues[case.cue].files == [case.file] and player.stream.get_length() == load(case.file).get_length(), "player uses delivered file: " + case.file)
		check(previous == player or not previous.playing, "crossfade stops outgoing player")
		check(is_equal_approx(player.volume_db, float(audio.manifest.cues[case.cue].gain_db)), "crossfade reaches configured gain")
		var peak = maxf(AudioServer.get_bus_peak_volume_left_db(int(audio.buses.music), 0), AudioServer.get_bus_peak_volume_right_db(int(audio.buses.music), 0))
		check(peak > float(fixture.peak_floor_db), "decoded audio reaches music bus: " + case.cue)
		var rng_before = game.rng.state
		var playback = player.get_stream_playback()
		audio.enter(case.context)
		check(player.get_stream_playback() == playback and game.rng.state == rng_before, "same context preserves playback and business RNG")
		player.seek(player.stream.get_length() - float(fixture.loop_tail))
		await create_timer(float(fixture.loop_wait)).timeout
		check(player.playing and player.get_playback_position() < float(fixture.loop_wait) + float(fixture.loop_tail), "actual end wraps into next loop: " + case.cue)
		if case.context == "shop":
			playback = player.get_stream_playback()
			var product = game.page.get_node("ShopShelves").products.keys()[0]
			game._buy_stock(product)
			check(player.get_stream_playback() == playback, "real purchase does not restart delivered shop music")
		paused = true
		audio.set_paused(true)
		var position = player.get_playback_position()
		await create_timer(float(fixture.play_wait), true).timeout
		check(player.playing and not player.stream_paused and player.get_playback_position() > position, "music continues through pause")
		check(is_equal_approx(AudioServer.get_bus_volume_db(int(audio.buses.music)), float(audio.manifest.settings.menu_duck_db)), "pause applies configured ducking")
		paused = false
		audio.set_paused(false)
		check(is_zero_approx(AudioServer.get_bus_volume_db(int(audio.buses.music))), "resume restores volume")
	for context in fixture.fallback_contexts:
		audio.enter(context)
		check(audio.active_cue.music == "music.bar", "undelivered context retains declared fallback: " + context)
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "user save/profile/settings unchanged")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("BGM DELIVERY: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
