extends SceneTree
var game
var fixture: Dictionary
var checks = 0
var failures = 0
var output = ""

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

func click(control: Control) -> void:
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await frames()

func capture(label: String) -> void:
	await frames()
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + label + ".png")

func inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(point, polygon): return true
	for index in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])) <= float(fixture.geometry_epsilon): return true
	return false

func run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journal_ice_cases.json"))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0].get_basename()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var protected = {}
	for path in game.save_slots.paths() + [game.save_slots.default_path, game.interface.slots.profile_path, game.interface.menu.settings_path]:
		for suffix in ["", ".bak"]: protected[path + suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	game.config.save_path = fixture.save_path
	var fast = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json"))
	for key in ["transitions", "measure_focus", "mix_focus", "straight_focus"]: game.bar_ui[key].merge(fast, true)
	game.set_process(false)
	game._begin_rival_run(game.config.companions[0], fixture.rival, true)
	game.stock_only_mode = true
	game._sync_challenge()
	game.queue = [{"recipe_id": fixture.recipe, "customer_index": int(fixture.customer_index)}]
	game._start_guest()
	check(game.playing and not game.reception_checkpoint.is_empty(), "real receiving order has a checkpoint")
	var economic_checkpoint = game.reception_checkpoint.duplicate(true)
	var legacy = game._snapshot("reception")
	legacy.run.erase("journal_favorites")
	legacy.run.rumors = [fixture.legacy_prefixes[0] + fixture.notes[0], fixture.legacy_prefixes[1] + fixture.notes[0], fixture.notes[1]]
	var decoded = game.save_schema.decode(legacy)
	check(not decoded.is_empty() and decoded.run.rumors == [fixture.notes[0], fixture.notes[1]] and decoded.run.journal_favorites.is_empty(), "older v8 notebook strips prefixes and merges duplicate display text")
	legacy.run.journal_favorites = [fixture.legacy_prefixes[1] + fixture.notes[0]]
	check(game.save_schema.decode(legacy).run.journal_favorites == [fixture.notes[0]], "favorites survive normalized legacy text")
	legacy.run.journal_favorites = [fixture.notes[-1]]
	check(game.save_schema.decode(legacy).is_empty(), "orphan favorite is rejected before restore")
	legacy.run.journal_favorites = fixture.notes[0]
	check(game.save_schema.decode(legacy).is_empty(), "invalid favorite container is rejected")
	var cues = []
	game.sound.cue_requested.connect(func(id): cues.append(id))
	for kind in fixture.message_samples:
		game.queue[0].message_kind = kind
		game.queue[0].message_text = fixture.message_samples[kind]
		game.dialogue = 1
		game.brew.stage = 2
		game._draw_dialogue()
		var label = game.dialogue_box.get_child(1)
		check(label.text == fixture.message_samples[kind] and label.get_theme_color("font_color") == game.MINT, "messages share text-only presentation and color: " + kind)
		cues.clear()
		game._advance_dialogue(0)
		check(game.rumors.has(fixture.message_samples[kind]) and cues.has("sfx.intel"), "both sources share acknowledgment audio and have no classifier prefix: " + kind)
	game.rumors = fixture.notes.duplicate()
	game.journal_speakers.clear()
	game.journal_favorites = [fixture.notes[0]]
	var target = game.brew.target()
	game.stock[target.name] -= float(fixture.mid_order_spend)
	game.stock_ledger.consume(target.name, float(fixture.mid_order_spend))
	game.money -= int(fixture.mid_order_spend)
	var rng_before = game.rng.state
	game.pause_menu.open_journal()
	game.pause_menu.page_transition.cancel()
	var book = game.pause_menu.journal
	await frames()
	check(paused and book.tabs.size() == game.interface.journal.sections.size(), "journal pauses gameplay and exposes every section")
	for id in book.tabs:
		await click(book.tabs[id])
		check(book.section == id and book.tabs[id].button_pressed, "real tab click selects " + id)
	check(not game.pause_menu._journal_text("companion").contains(game.competition.rival().name), "companion section does not mix in rival information")
	check(game.pause_menu._journal_text("rival").contains(game.competition.rival().name), "opponent section keeps rival and challenge information")
	for window in fixture.windows:
		root.size = Vector2i(window[0], window[1])
		await frames()
		check(game.get_global_rect().encloses(game.pause_menu.content.get_parent().get_global_rect()), "notebook panel fits window " + str(window[0]))
		await capture("-messages-" + str(window[0]))
	var search = book.body.find_child("JournalSearch", true, false)
	search.text = fixture.query
	search.text_changed.emit(search.text)
	await frames()
	check(book.filtered() == [fixture.notes[0]], "search finds text across the full notebook")
	await click(book.actions.select_all)
	check(book.selected.keys() == [fixture.notes[0]], "select all selects current search results")
	await click(book.actions.unfavorite_selected)
	check(game.journal_favorites.is_empty(), "bulk favorite removal uses actual controls")
	await click(book.actions.favorite_selected)
	check(game.journal_favorites == [fixture.notes[0]], "bulk favorites persist through actual controls")
	await click(book.actions.delete_selected)
	check(fixture.notes[0] not in game.rumors and game.journal_favorites.is_empty(), "explicitly selected favorites can be deleted without orphaning their metadata")
	await click(book.undo)
	check(game.rumors == fixture.notes and game.journal_favorites == [fixture.notes[0]], "undo restores a deleted favorite and its original position")
	await click(book.actions.select_none)
	search.text = ""
	search.text_changed.emit("")
	await frames()
	await click(book.body.find_child("JournalFavoritesOnly", true, false))
	check(book.filtered() == [fixture.notes[0]], "favorite filter shows only player favorites")
	await capture("-favorites")
	await click(book.body.find_child("JournalFavoritesOnly", true, false))
	await click(book.actions.clean)
	check(game.rumors == [fixture.notes[0]] and game.journal_favorites == [fixture.notes[0]], "cleanup removes unstarred notes and protects favorites")
	await click(book.undo)
	check(game.rumors == fixture.notes and game.journal_favorites == [fixture.notes[0]], "undo restores original positions and favorites")
	var last_row = book.list.get_child(0)
	var selected_text: String = last_row.get_meta("note")
	await click(last_row.get_node("JournalFavorite"))
	check(selected_text in game.journal_favorites, "single-record star button favorites its record")
	await click(book.list.get_child(0).get_node("JournalFavorite"))
	check(selected_text not in game.journal_favorites, "single-record star button removes its favorite")
	last_row = book.list.get_child(0)
	await click(last_row.get_node("JournalSelect"))
	check(book.selected.has(selected_text), "row checkbox selects the actual record")
	await click(book.actions.delete_selected)
	check(selected_text not in game.rumors, "batch delete removes selected record")
	var saved = game.save_store.load_snapshot(fixture.save_path, game.save_schema.decode)
	check(not saved.is_empty() and saved.run.rumors == game.rumors and saved.run.journal_favorites == game.journal_favorites, "cleanup and favorites are saved immediately during reception")
	check(saved.run.money == economic_checkpoint.run.money and saved.run.stock == economic_checkpoint.run.stock and saved.run.stock_ledger == economic_checkpoint.run.stock_ledger, "notebook edits preserve the order-start economic checkpoint")
	check(game.rng.state == rng_before, "search and organization do not draw gameplay random numbers")
	game.pause_menu.close()
	check(game._load_game() and selected_text not in game.rumors and fixture.notes[0] in game.journal_favorites, "actual reload retains deletion and favorites")
	game.set_process(false)
	for index in int(fixture.many_count): game._record_rumor(fixture.many_note.format({"index": index}))
	game.pause_menu.open_journal("messages")
	game.pause_menu.page_transition.cancel()
	await frames()
	check(book.list.get_child_count() == int(game.interface.journal.page_size), "large notebook renders only a bounded page")
	await click(book.next)
	check(book.page_index == 1, "pagination reaches older notes")
	await capture("-many-messages")
	game.pause_menu.close()
	game.scene_transition.cancel()
	root.size = Vector2i(fixture.windows[-1][0], fixture.windows[-1][1])
	var gallery = PanelContainer.new()
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(gallery)
	var grid = GridContainer.new()
	grid.columns = int(fixture.gallery_columns)
	gallery.add_child(grid)
	var drinks = []
	for ice in fixture.ice_types:
		for cup in game.bar_assets.cups:
			var column = VBoxContainer.new()
			grid.add_child(column)
			game._label(column, cup + " · " + ice, 18, game.GOLD)
			var drink = load("res://scripts/ui/bar/drink_display.gd").new()
			drink.assets = game.bar_assets
			drink.colors = game.drink_colors
			drink.settings = game.bar_ui
			drink.cup = cup
			drink.ice = ice
			drink.recipe_name = game.recipes.filter(func(recipe): return recipe.cup == cup)[0].name
			drink.has_liquid = true
			drink.custom_minimum_size = Vector2(fixture.gallery_drink_size[0], fixture.gallery_drink_size[1])
			column.add_child(drink)
			drinks.append(drink)
	await capture("-ice-gallery")
	for drink in drinks:
		var bottom = drink.liquid_points[0].y
		var top = bottom
		for point in drink.liquid_points:
			bottom = maxf(bottom, point.y)
			top = minf(top, point.y)
		check(is_equal_approx(drink.ice_rect.end.y, bottom - (bottom - top) * float(game.bar_ui.presentation.ice_bottom_inset_ratio)), "ice rests at cup bottom: " + drink.cup + drink.ice)
		check(not drink.ice_polygons.is_empty() and drink.ice_polygons.all(func(polygon): return Array(polygon).all(func(point): return inside(point, drink.liquid_points))), "ice stays inside tapered bowl: " + drink.cup + drink.ice)
	var drink = drinks[0]
	drink.ice = fixture.no_ice
	drink.queue_redraw()
	await frames()
	check(drink.ice_rect == Rect2() and drink.ice_polygons.is_empty(), "no-ice artwork remains empty")
	gallery.queue_free()
	game._begin_rival_run(game.config.companions[0], fixture.rival, true)
	check(game.rumors.is_empty() and game.journal_favorites.is_empty() and book.last_deleted.is_empty(), "new run cannot inherit messages or undo data from another run")
	for path in protected: check((FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null) == protected[path], "real user data protected: " + path)
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	game.queue_free()
	await frames()
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	print("JOURNAL AND ICE: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
