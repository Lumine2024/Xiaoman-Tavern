extends SceneTree
var game
var checks = 0
var failures = 0
var output = ""
var fixture: Dictionary

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
		root.get_texture().get_image().save_png(output+suffix+".png")

func wheel(selector, direction: int) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = direction
	event.pressed = true
	event.position = selector.reel.get_global_rect().get_center()
	root.push_input(event, true)
	await process_frame

func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame

func make_drink(recipe: Dictionary) -> void:
	game._choose_companion(game.config.companions[0])
	game.promotion = recipe
	game._open_day(true)
	game.queue[0] = {"recipe_id":recipe.id,"customer_index":int(fixture.customer_index)}
	game._start_guest()
	game._advance_dialogue(0)
	while game.brew.stage < 2:
		var item = game.brew.target()
		game._toggle_pour(item.name)
		game._process(float(item.amount)/game._pour_rate())
		game._stop_pour()
		game._transfer()
	for item in recipe.pre_solids: game._add_pre_solid(item.name)
	game._advance_dialogue(int(game.guest.good_answer))
	if recipe.method == "直调":
		game._finish_straight()
		while game.workbench.straight_focus.shown: await process_frame
		check(game.brew.stage == 3 and not game.workbench.mix_focus.shown, "straight transition completes without timing minigame")
	else:
		game._toggle_mix()
		var duration = float(game.config.mix_cycle_seconds)
		if recipe.method in ["滚摇","长摇"]: duration *= float(game.config.long_mix_multiplier)
		game._process(float(game.config.mix_target)*duration)
		game.workbench.mix_focus.close()
	game._select_cup(recipe.cup)
	game._select_ice(game.brew.expected_ice())
	game._pour_into_glass()
	while game.brew.stage == 3:
		game._topup()
		check(is_zero_approx(game.workbench.glass.rotation), "topup leaves full glass upright")
		await process_frame
		check(is_zero_approx(game.workbench.glass.rotation), "topup never schedules glass tilt")
	game._advance_dialogue(0)
	game._special(true)
	for item in game.brew.expected_garnishes(): game._garnish(item)
	check(game.brew.final_errors() == 0, "presentation retains correct brew workflow")
	game._serve()

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cards_presentation_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	var original_path = game.config.save_path
	var original = FileAccess.get_file_as_string(original_path) if FileAccess.file_exists(original_path) else null
	game.config.save_path = fixture.save_path
	game.pause_menu.reduced_motion = false
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	game.bar_ui.measure_focus.merge(fast,true)
	game.bar_ui.mix_focus.merge(fast,true)
	game.bar_ui.straight_focus.merge(fast,true)
	game.set_process(false)
	game._show_companion_selection()
	await process_frame
	var selector = game.page.get_child(0)
	await wheel(selector,MOUSE_BUTTON_WHEEL_DOWN)
	check(selector.selected == 1, "wheel changes authored companion")
	await create_timer(float(selector.settings.select_seconds)).timeout
	await capture("-cards")
	await wheel(selector,MOUSE_BUTTON_WHEEL_DOWN)
	check(selector.selected == 2, "wheel reaches the third of five companions")
	await wheel(selector,MOUSE_BUTTON_WHEEL_UP)
	check(selector.selected == 1, "reverse wheel returns to previous companion")
	game._show_rival_selection(game.config.companions[0])
	await process_frame
	selector = game.page.get_child(0)
	var random_before = selector.random.state
	var selection_before = selector.selected
	await wheel(selector,MOUSE_BUTTON_WHEEL_DOWN)
	check(selector.selected == selection_before and selector.random.state == random_before, "wheel cannot select or redraw rival")
	for cup in fixture.cups:
		var recipe: Dictionary = game.recipes.filter(func(entry): return entry.cup == cup)[0]
		await make_drink(recipe)
		await capture("-"+cup)
		var scene = game.page.find_child("ServedDrinkPreview",true,false)
		check(scene != null, "settlement shows tabletop closeup")
		var drink = scene.drink
		check(drink.cup == game.brew.cup and drink.ice == game.brew.ice and drink.garnishes == game.brew.garnishes and drink.has_liquid, "display uses actual vessel, ice, liquid and garnish")
		check(is_equal_approx(scene.table.get_rect().get_center().x, drink.get_rect().get_center().x), "finished drink is centered on table")
		var rng_before = game.rng.state
		var elapsed_before = drink.elapsed
		await create_timer(float(fixture.pause_seconds)).timeout
		check(drink.elapsed > elapsed_before and game.rng.state == rng_before, "2D bubbles animate without consuming gameplay RNG")
		check(not drink.bubble_positions.is_empty(), "bubbles visible inside liquid")
		for at in drink.bubble_positions:
			check(Geometry2D.is_point_in_polygon(at,drink.liquid_points), "bubble stays inside cup liquid")
		if drink.ice != "无冰": check(drink.texture_cache.has(game.bar_assets.ice[drink.ice]), "actual ice texture is displayed")
		for garnish in drink.garnishes: check(drink.texture_cache.has(game.bar_assets.garnishes[garnish]), "actual garnish texture is displayed")
		await key(KEY_ESCAPE)
		elapsed_before = drink.elapsed
		await create_timer(float(fixture.pause_seconds),true).timeout
		check(is_equal_approx(elapsed_before,drink.elapsed), "pause freezes result bubbles")
		await key(KEY_ESCAPE)
		for dimensions in fixture.window_sizes:
			root.size = Vector2i(dimensions[0],dimensions[1])
			await process_frame
			await process_frame
			check(game.get_global_rect().encloses(game.page.get_global_rect()), "closeup and result controls fit viewport")
		game.pause_menu.reduced_motion = true
		await process_frame
		elapsed_before = drink.elapsed
		await create_timer(float(fixture.pause_seconds)).timeout
		check(is_equal_approx(elapsed_before,drink.elapsed), "reduced motion stops bubble movement")
		game.pause_menu.reduced_motion = false
	check((not FileAccess.file_exists(original_path)) if original == null else FileAccess.get_file_as_string(original_path) == original, "real player save preserved")
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path+suffix))
	print("CARDS AND PRESENTATION: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
