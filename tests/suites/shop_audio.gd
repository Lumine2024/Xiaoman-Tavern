extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""
var played: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func capture(label: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/shop_audio_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	game.interface.menu.settings_path = fixture.settings_path
	var transitions = game.bar_ui.transitions.duplicate(true)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game._begin_rival_run(game.config.companions[0], "karn")
	game.set_process(false)
	game.money = int(fixture.cash)
	game.scene_transition.cancel()
	game.bar_ui.transitions.merge(transitions, true)
	var shop = game.page.get_node("ShopShelves")
	shop.page_index = int(fixture.page_index)
	shop._render()
	await process_frame
	var name: String = shop.products.keys()[0]
	var button: Button = shop.products[name].actions[0].button
	var scroll: ScrollContainer = shop.catalog.get_child(1)
	scroll.get_child(0).custom_minimum_size.y = float(fixture.scroll_height)
	button.grab_focus()
	await process_frame
	scroll.scroll_vertical = int(fixture.scroll_position)
	await process_frame
	var scroll_before = scroll.scroll_vertical
	var generation = game.scene_transition.generation
	var stock_before = float(game.stock[name])
	var cash_before = game.money
	var unit_price = game._stock_price(name)
	var pack = float(game.pricing.catalog.ingredients[name].pack_ml)
	for index in int(fixture.purchases):
		button.pressed.emit()
		check(shop == game.page.get_node("ShopShelves") and shop.products[name].actions[0].button == button, "purchase retains real shop and button")
		check(shop.page_index == int(fixture.page_index) and scroll.scroll_vertical == scroll_before, "purchase retains page and scroll")
		check(not game.scene_transition.busy and game.scene_transition.generation == generation, "purchase never starts fade")
		check(root.gui_get_focus_owner() == button, "repeat purchase keeps keyboard focus")
	check(game.money == cash_before - unit_price * int(fixture.purchases), "each repeat purchase charges exact cash")
	check(game.stock[name] == stock_before + pack * int(fixture.purchases), "each repeat purchase adds exact stock")
	check(shop.products[name].inventory.text.contains(str(int(game.stock[name]))), "inventory text updates in place")
	check(game.header_stats.text.contains(str(game.money)), "cash header updates immediately")
	check(game.last_save_ok and not game.save_slots.read(fixture.save_path).is_empty(), "purchase still saves")
	game.money = 0
	shop.refresh()
	check(shop.products.values().all(func(view): return view.actions.all(func(action): return action.credit or action.button.disabled)), "all visible unaffordable purchases disable together")
	game.money = cash_before - unit_price * int(fixture.purchases)
	game._refresh_shop_purchase()
	await capture("-shop")
	# Silent PCM is a real test stream, not a delivered game sound.
	var sample = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = int(fixture.sample_rate)
	var pcm = PackedByteArray()
	pcm.resize(int(fixture.sample_frames) * 2)
	pcm.fill(0)
	sample.data = pcm
	check(ResourceSaver.save(sample, fixture.audio_path) == OK, "external temporary stream is available")
	var audio = game.sound
	var rng_before = game.rng.state
	audio.cue_played.connect(func(id): played.append(id))
	check(not audio.play("sfx.not_configured"), "unknown cue is silent")
	audio.manifest.cues["sfx.purchase"].files = [fixture.missing_path]
	check(not audio.play("sfx.purchase"), "undelivered file is silent")
	for cue in audio.manifest.cues.values(): cue.files = [fixture.audio_path]
	audio.manifest.settings.fade_seconds = float(fixture.fade_seconds)
	# Re-enter after replacing real delivered streams with the synthetic fixture.
	audio._switch("music", "")
	audio.enter("shop")
	await create_timer(float(fixture.play_wait)).timeout
	var music: AudioStreamPlayer = audio.decks.music[int(audio.active_deck.music)]
	check(music.playing and music.stream is AudioStreamWAV and music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "real background stream loops natively")
	var playback = music.get_stream_playback()
	audio.enter("shop")
	check(music.get_stream_playback() == playback, "same context never restarts background playback")
	game._buy_stock(name)
	check(music.get_stream_playback() == playback, "real repeat purchase never restarts installed music")
	check(played.has("sfx.purchase"), "real purchase reaches actual sound player")
	check(not audio.play("sfx.purchase"), "immediate duplicate sound is rate limited")
	await create_timer(float(audio.manifest.cues["sfx.purchase"].cooldown_ms) / 1000.0 + float(fixture.play_wait)).timeout
	check(audio.play("sfx.purchase"), "sound can play again after cooldown")
	audio.loop("test", "sfx.pour")
	check(audio.loops.test.playing, "continuous pouring uses real loop player")
	paused = true
	audio.set_paused(true)
	check(audio.loops.test.stream_paused and music.playing, "pause freezes world sound while music continues")
	check(not audio.play("sfx.bell") and audio.play("sfx.ui_back"), "pause permits menu sound and blocks world sound")
	paused = false
	audio.set_paused(false)
	check(not audio.loops.test.stream_paused, "world loop resumes at unpause")
	audio.stop_world_loops()
	check(not audio.loops.test.playing, "leaving scene stops continuous sound")
	audio.manifest.cues["music.rival"].files = [fixture.missing_path]
	audio.enter("rival")
	check(audio.active_cue.music == "music.bar", "optional missing music uses declared fallback")
	check(game.rng.state == rng_before, "audio variants never consume business RNG")
	var config = ConfigFile.new()
	config.set_value("external", "keep", true)
	config.save(fixture.settings_path)
	game.pause_menu.open()
	game.pause_menu.show_settings()
	var previous_sfx = float(audio.levels.sfx)
	var slider = game.pause_menu.content.get_node("Audio_music")
	slider.value = float(fixture.music_level)
	check(is_equal_approx(float(audio.levels.music), float(fixture.music_level)) and float(audio.levels.sfx) == previous_sfx, "music slider changes its own group")
	config.load(fixture.settings_path)
	check(is_equal_approx(float(config.get_value("audio", "music")), float(fixture.music_level)) and config.get_value("external", "keep"), "audio settings persist without erasing other sections")
	audio.set_level("master", 0)
	check(AudioServer.is_bus_mute(int(audio.buses.master)), "zero master level mutes output")
	await create_timer(float(game.bar_ui.transitions.fade_out_seconds) + float(game.bar_ui.transitions.fade_in_seconds) + float(fixture.play_wait)).timeout
	for size in fixture.window_sizes:
		root.size = Vector2i(size[0], size[1])
		await capture("-settings-" + str(size[0]))
	game.pause_menu.close()
	for path in protected:
		check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real save/profile/settings protected")
	for path in [fixture.save_path, fixture.audio_path, fixture.settings_path]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("SHOP AUDIO: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(1 if failures else 0)
