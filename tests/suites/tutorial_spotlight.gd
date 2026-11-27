extends SceneTree
var checks = 0
var failures: Array = []
var game
var output = ""
var captured: Array = []
var seen_drawers: Array = []
var independent_guests: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func click_at(point: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event, true)
	await process_frame
func settle() -> void:
	await process_frame
	await process_frame
	game.tutorial_director.refresh()
func capture(key: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or key in captured: return
	captured.append(key)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "-" + key + ".png")

func independent_item(kind: String, item: String):
	var bench = game.workbench
	if not bench.drawer.visible: return bench.drawer_buttons.get_node(kind)
	if bench.drawer_kind != kind: return bench.drawer.get_child(0).get_child(0).get_child(1)
	for card in bench.drawer_items.get_children():
		if card.get_child(0).name == item:
			bench.drawer_scroll.ensure_control_visible(card)
			await process_frame
			return card.get_child(0)
	return null

func independent_target():
	var b = game.brew
	var bench = game.workbench
	if bench.measure_focus.shown:
		game._process(float(b.target().amount) / game._pour_rate())
		return bench.measure_focus.overlay
	if bench.mix_focus.shown:
		game._process(float(game.config.mix_target) * float(game.config.mix_cycle_seconds))
		return bench.mix_focus.overlay
	if game._dialogue_unlocked() and game.dialogue < 3:
		var buttons = game.dialogue_box.get_children().filter(func(c): return c is BaseButton)
		return buttons[int(game.guest.good_answer) if game.dialogue == 1 else 0]
	if b.stage < 2:
		if b.measured > 0: return bench.shaker
		return await independent_item("base" if b.target().name in game.config.base_names else "mixer", b.target().name)
	if b.stage == 2: return bench.shaker
	if b.stage == 3:
		if b.poured: return await independent_item("topup", b.recipe.topup[b.topup_index].name)
		if game.selected_cup != b.recipe.cup: return await independent_item("cups", b.recipe.cup)
		if game.selected_ice != b.expected_ice(): return await independent_item("ice", b.expected_ice())
		return bench.shaker
	if b.stage == 4: return bench.glass
	var missing = b.expected_garnishes().filter(func(item): return item not in b.garnishes)
	if not missing.is_empty(): return await independent_item("garnishes", missing[0])
	return bench.bell
func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tutorial_cases.json"))
	var args = OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.mix_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.straight_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.set_process(false)
	var user_path = game.config.save_path
	var user_exists = FileAccess.file_exists(user_path)
	var user_before = FileAccess.get_file_as_string(user_path) if user_exists else ""
	game.config.save_path = fixture.normal_save_path
	game._begin_tutorial()
	await settle()
	var director = game.tutorial_director
	check(director.step == "promotion" and director.targets.size() == 1, "only opening action is enabled")
	var actions = 0
	var completed_drinks = 0
	while not game.tutorial_context.is_empty() and actions < int(fixture.spotlight.max_actions):
		await settle()
		if director.step == "independent" and game.tutorial_context == "reception":
			check(not director.veil.visible and not director.story_panel.visible and director.targets.is_empty(), "independent guest has no spotlight or input gate")
			var number = game.guest_index + 1
			if number not in independent_guests:
				independent_guests.append(number)
				# Open an unrelated drawer with actual input: no lesson restricts it.
				var drawer = game.workbench.drawer_buttons.get_node("mixer")
				await click_at(director.rect_for(drawer).get_center())
				check(game.workbench.drawer.visible, "independent player can open unrelated drawer")
				await capture("independent-" + str(number))
				var request_button = game.dialogue_box.get_children().filter(func(c): return c is BaseButton)[0]
				request_button.grab_focus()
				for down in [true, false]:
					var enter = InputEventKey.new()
					enter.keycode = KEY_ENTER
					enter.pressed = down
					root.push_input(enter, true)
				await settle()
				check(game.dialogue == 1, "independent practice permits normal keyboard activation")
			var independent_control = await independent_target()
			check(is_instance_valid(independent_control), "independent action reachable")
			if not is_instance_valid(independent_control): break
			await click_at(director.rect_for(independent_control).get_center())
			actions += 1
			continue
		if director.step == "explore_shop":
			check(not director.veil.visible and director.targets.is_empty(), "shop becomes freely explorable")
			var shop = game.page.get_node("ShopShelves")
			var previous_page = shop.page_index
			await click_at(shop.catalog.get_child(0).get_child(0).get_global_rect().get_center())
			check(shop.page_index == previous_page - 1, "tutorial player can browse other shelves")
			completed_drinks = game.day_success
			await click_at(game.tutorial_action.get_global_rect().get_center())
			actions += 2
			continue
		check(not director.targets.is_empty(), "reachable target for " + director.step)
		if director.targets.is_empty(): break
		check(not "{" in director.story_label.text and not "}" in director.story_label.text, "all narrative placeholders resolved: " + director.step)
		if director.step == "drawer":
			var kind = str(director.targets[0].name)
			check(director.story_label.text.contains(game.bar_ui.drawer_names[kind]), "narrative names the highlighted drawer: " + kind)
			if kind not in seen_drawers: seen_drawers.append(kind)
			await capture("drawer-" + kind)
		if game.tutorial_context == "reception":
			check(game.get_global_rect().encloses(game.page.get_global_rect()), "narration fits viewport")
			if director.step == "request":
				# Real mouse events on a dark, enabled bell must never submit a drink.
				var served = game.day_served
				game.workbench.bell.disabled = false
				await click_at(director.rect_for(game.workbench.bell).get_center())
				check(game.day_served == served and game.dialogue == 0, "dark bell blocks actual pointer input")
				game.workbench.bell.disabled = true
				# A previously focused dark button cannot be triggered by keyboard.
				game.workbench.shaker.grab_focus()
				var enter = InputEventKey.new()
				enter.keycode = KEY_ENTER
				enter.pressed = true
				root.push_input(enter, true)
				check(game.brew.measured == 0 and game.brew.ingredient_index == 0, "dark keyboard focus blocked")
			if director.step == "pour":

				game._process(float(game.brew.target().amount) / game._pour_rate())
			if director.step == "mix_stop":
				var multiplier = float(game.config.long_mix_multiplier) if game.brew.recipe.method in ["滚摇", "长摇"] else 1.0
				game._process(float(game.config.mix_target) * float(game.config.mix_cycle_seconds) * multiplier)
		if director.step in fixture.spotlight.captures: await capture(director.step)
		var key = director.step
		var target = director.targets[0]
		if key == "chat":
			check(director.targets.size() == game.guest.answers.size(), "all narrative replies remain player choices")
			target = director.targets[int(game.guest.good_answer)]
		
		var rect = director.rect_for(target)
		check(rect.has_area(), "target visible without manual scrolling: " + key)
		check(not director.veil._has_point(rect.get_center()), "lit button accepts input: " + key)
		print("CLICK ", actions, " / ", game.guest_index, " / ", key, " / ", target.name)
		if key == "finish": completed_drinks = game.day_success
		await click_at(rect.get_center())
		actions += 1
	for kind in fixture.spotlight.expected_drawers:
		check(kind in seen_drawers, "drawer narration covered: " + kind)
	check(independent_guests == fixture.independent_guest_numbers.map(func(number): return int(number)), "only specified guests brew independently")
	check(game.tutorial_context.is_empty(), "tutorial finishes through actual spotlight clicks")
	check(completed_drinks == fixture.expected_orders.size(), "six drinks succeed through spotlight")
	check(not director.veil.visible, "spotlight removed on title")
	check(game._load_game(), "second cycle save resumes")
	await settle()
	check(game.progress.cycle == 2 and not director.veil.visible, "completed tutorial stays complete on reload")
	game.show_start()
	await settle()
	check(not director.veil.visible, "story exit removes blocker")
	game._choose_companion(game.config.companions[0])
	await settle()
	check(not director.veil.visible, "normal game has no spotlight")
	check(FileAccess.file_exists(user_path) == user_exists and (not user_exists or FileAccess.get_file_as_string(user_path) == user_before), "real user save untouched throughout validation")
	print("TUTORIAL SPOTLIGHT: %d checks; %d failures; %d clicks" % [checks, failures.size(), actions])
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	quit(0 if failures.is_empty() else 1)
