extends SceneTree
var game
var fixture: Dictionary
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

func check_skin(button: Button, profile: String) -> void:
	for state in fixture.states:
		var style = button.get_theme_stylebox(state)
		check(style is StyleBoxTexture, "%s uses editable PNG for %s" % [button.text, state])
		if style is StyleBoxTexture:
			check(style.texture.resource_path == game.button_skins.profiles[profile].textures[state], "correct skin family: " + profile)

func capture(suffix: String) -> void:
	await process_frame
	await process_frame
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + suffix + ".png")

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/button_skins_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var originals: Dictionary = {}
	for path in game.save_slots.paths() + [game.interface.slots.profile_path]:
		for suffix in ["", ".bak"]:
			originals[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.interface.slots.merge(fixture.paths, true)
	game.save_slots.settings = game.interface.slots
	game.save_slots.default_path = fixture.legacy_path
	game.save_slots.active_slot = 0
	game.config.save_path = fixture.paths.manual_paths[0]
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	for profile in game.button_skins.profiles.values():
		var focus: Texture2D = load(profile.textures.focus)
		var image = focus.get_image()
		check(not profile.get("focus_draw_center", true) or image.get_pixel(image.get_width()/2, image.get_height()/2).a <= float(fixture.focus_alpha_max), "focus centre is omitted or transparent, preserving the active state")
		for path in profile.textures.values():
			var texture: Texture2D = load(path)
			check(texture.get_width() >= profile.texture_margins[0] + profile.texture_margins[2] and texture.get_height() >= profile.texture_margins[1] + profile.texture_margins[3], "nine-slice corners fit source PNG")
	game._show_companion_selection()
	var selector = game.page.get_child(0)
	check_skin(selector.action, "common")
	check(selector.seats[0].button_pressed and selector.seats[0].modulate == Color.WHITE, "selected seat uses PNG state without recolouring artwork")
	selector.select(1)
	check(selector.seats[1].button_pressed and not selector.seats[0].button_pressed, "seat selection updates native pressed state")
	game._choose_companion(game.config.companions[0])
	check_skin(game.recipe_option, "common")
	game.pause_menu.open()
	game.pause_menu.show_slots("save")
	for child in game.pause_menu.content.get_child(1).get_child(0).get_children(): check_skin(child, "save_slot")
	for dimensions in fixture.window_sizes:
		root.size = Vector2i(dimensions[0], dimensions[1])
		await capture("-slots-" + str(int(dimensions[0])))
		check(game.pause_menu.content.size.x <= root.get_visible_rect().size.x, "textured slot grid fits window")
	game.pause_menu.show_settings()
	for child in game.pause_menu.content.get_children():
		if child is CheckButton: check_skin(child, "common")
	game.pause_menu.close()
	game._open_day(true)
	game.set_process(false)
	for child in game.dialogue_box.get_children():
		if child is Button: check_skin(child, "dialogue")
	await capture("-dialogue")
	game._confirm_cycle_action(false)
	for child in game.get_children():
		if child is ConfirmationDialog:
			check_skin(child.get_ok_button(), "common")
			check_skin(child.get_cancel_button(), "common")
			child.hide()
	for path in originals:
		var content = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(content == originals[path], "user save and shared profile preserved")
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	for path in fixture.paths.manual_paths + fixture.paths.auto_paths + [fixture.paths.profile_path, fixture.legacy_path]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("BUTTON SKINS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
