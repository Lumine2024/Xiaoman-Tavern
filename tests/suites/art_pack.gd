extends SceneTree
## Real selectors and receptions: verify stable IDs and untinted delivered PNGs.
var game
var checks = 0
var failures = 0
var output = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/art_pack_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected: Dictionary = {}
	for path in game.save_slots.paths() + [game.interface.slots.profile_path]:
		for suffix in ["", ".bak"]:
			protected[path+suffix] = FileAccess.get_file_as_bytes(path+suffix) if FileAccess.file_exists(path+suffix) else null
	game.config.save_path = fixture.save_path
	game.set_process(false)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	await capture("-title")
	for group in ["cards", "companions", "rivals", "customers"]:
		for path in game.character_art[group].values():
			check(load(path) is Texture2D, "delivered artwork imports: " + path)
	game._show_companion_selection()
	await capture("-companions")
	var selector = game.page.get_child(0)
	for entry in selector.entries:
		check(game.character_art.companions.has(entry.id) and load(game.character_art.companions[entry.id]) is Texture2D, "all five companions have delivered portraits: " + entry.id)
	game._show_rival_selection(game.config.companions[0])
	selector = game.page.get_child(0)
	for entry in selector.entries:
		check(game.character_art.rivals.has(entry.id), "rival ID has art: " + entry.id)
	selector.selected = int(fixture.rival_index)
	selector.reel_position = float(selector.selected)
	selector.settled = true
	selector._refresh()
	await capture("-rivals")
	game._choose_companion(game.config.companions[0])
	game._open_day(true)
	for i in game.customers.size():
		game.queue[0].customer_index = i
		game._start_guest()
		var portrait = game.page.find_child("GuestPortrait", true, false)
		var id: String = game.customers[i].story_id
		check(game.character_art.customers.has(id), "customer story ID has art: " + id)
		check(portrait.texture.resource_path == game.character_art.customers[id], "reception uses independent portrait: " + id)
		check(portrait.modulate == Color.WHITE, "portrait retains source colours: " + id)
		await capture("-guest-" + id)
	for window_size in fixture.window_sizes:
		root.size = Vector2i(window_size[0], window_size[1])
		await capture("-reception-" + str(window_size[0]))
	game.show_shop()
	await capture("-shop")
	for path in protected:
		var content = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(content == protected[path], "user save and profile unchanged: " + path)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("DARK ART PACK: %d checks; %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
