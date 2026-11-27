extends SceneTree
## Integration coverage uses production rules and a separate disposable save path.
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func write_text(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func last_dialog(game) -> AcceptDialog:
	var found: AcceptDialog
	for child in game.get_children():
		if child is AcceptDialog and not child.is_queued_for_deletion():
			found = child
	return found

func reset_fields(run_state: Dictionary) -> Dictionary:
	var result = run_state.duplicate(true)
	result.erase("rng")
	return result

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_cases.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.measure_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.mix_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.bar_ui.straight_focus.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path = fixture.save_path
	game.set_process(false)
	game._choose_companion(game.config.companions[0])
	check(game.last_save_ok, "fresh save written")
	var initial = game._snapshot("promotion")
	check(not game.save_schema.decode(initial).is_empty(), "valid v2 envelope")
	game._show_cycle_menu()
	last_dialog(game).custom_action.emit("advance")
	check(last_dialog(game) is ConfirmationDialog, "advance requires confirmation")
	last_dialog(game).get_cancel_button().pressed.emit()
	await process_frame
	check(game._snapshot("promotion") == initial, "cancelled advance preserves all state")
	game._show_cycle_menu()
	last_dialog(game).custom_action.emit("save")
	await process_frame
	check(game.last_save_ok and not game.playing, "save and return to title succeeds")
	check(game._load_game() and game._snapshot("promotion") == initial, "continue after returning to title")
	for item in fixture.invalid_cases:
		var invalid = initial.duplicate(true)
		var node = invalid
		for index in range(item.path.size() - 1):
			node = node[item.path[index]]
		node[item.path.back()] = item.value
		check(game.save_schema.decode(invalid).is_empty(), "reject invalid field " + str(item.path))
	var old_document = initial.duplicate(true)
	old_document.version = int(initial.version) - 1
	write_text(fixture.save_path, JSON.stringify(old_document))
	write_text(fixture.save_path + ".bak", JSON.stringify(old_document))
	check(not game._load_game(), "old save is rejected and removed")
	check(not FileAccess.file_exists(fixture.save_path) and not FileAccess.file_exists(fixture.save_path + ".bak"), "old primary and backup removed")
	if is_instance_valid(game.storage_dialog): game.storage_dialog.queue_free()
	await process_frame
	check(game._save("promotion"), "current snapshot can be saved after old file removal")
	game.recipe_option.select(game.recipes.size() - 1)
	game.recipe_option.item_selected.emit(game.recipe_option.selected)
	var chosen = game.promotion.id
	game._load_game()
	check(game.promotion.id == chosen and game.recipes[game.recipe_option.selected].id == chosen, "promotion selection restored")
	game._open_day()
	var checkpoint = game._snapshot("reception")
	var target = game.brew.target()
	game._toggle_pour(target.name)
	game._process(float(target.amount) / game._pour_rate())
	check(game.brew.measured > 0, "partial pour exists before reload")
	game._load_game()
	check(game.stock == checkpoint.run.stock and game.brew.measured == 0, "checkpoint restores stock and restarts customer")
	check(game.queue == checkpoint.run.queue and game.guest_index == checkpoint.run.guest_index, "queue is not rerolled")
	check(game.dialogue == 0 and not game.pouring and not game.mixing, "transient interaction flags cleared")
	# Persisting settlement must not award or deduct anything again on reload.
	game._abandon()
	var settled = game._snapshot("reception")
	game._load_game()
	check(game.money == settled.run.money and game.day_served == settled.run.day_served, "settled order is not replayed")
	check(game.guest_index == settled.run.guest_index, "resume at next customer")
	# Force dirty state in all collections to expose state leaking into a reset.
	game._show_cycle_menu()
	last_dialog(game).custom_action.emit("advance")
	last_dialog(game).get_ok_button().pressed.emit()
	await process_frame
	var advanced = game.progress.snapshot()
	check(advanced.cycle == initial.meta.cycle + 1 and advanced.ability_grants.size() == initial.meta.ability_grants.size() + 1, "cycle advances exactly once")
	check(advanced.ability_grants[0].effect.is_empty(), "cycle ability grant is empty")
	check(game.run_effects.ability.is_empty() and game.run_effects.stage_difficulty.is_empty() and game.run_effects.cycle_difficulty.is_empty(), "all difficulty and ability hooks are no-ops")
	check(reset_fields(game._snapshot("promotion").run) == reset_fields(initial.run), "next cycle resets every run field")
	game._open_day()
	game._process(float(game.config.order_seconds))
	game._restart_cycle()
	check(game.progress.snapshot() == advanced, "restart preserves cycle and grants")
	check(reset_fields(game._snapshot("promotion").run) == reset_fields(initial.run), "restart clears dirty run state")
	game._load_game()
	check(game.progress.snapshot() == advanced, "cycle and grants persist across load")
	check(game._load_game() and game.progress.snapshot() == advanced, "reloading never grants duplicate effects")
	# A truncated primary falls back to the previous valid generation.
	game._save("promotion")
	write_text(fixture.save_path, fixture.invalid_json)
	check(game._load_game() and game.save_store.loaded_backup, "recover truncated primary from backup")
	check(game._save("promotion"), "replace corrupt primary after recovery")
	check(not game.save_schema.decode(JSON.parse_string(FileAccess.get_file_as_string(fixture.save_path + ".bak"))).is_empty(), "healthy backup survives corrupt primary replacement")
	# Unsupported versions and broken backups must not partially change live state.
	var before = game._snapshot("promotion")
	var future = before.duplicate(true)
	future.version = fixture.unsupported_version
	write_text(fixture.save_path, JSON.stringify(future))
	write_text(fixture.save_path + ".bak", fixture.invalid_json)
	check(not game._load_game(), "reject unsupported primary and broken backup")
	check(game._snapshot("promotion") == before, "failed load leaves live state intact")
	var invalid = before.duplicate(true)
	invalid.run.phase = "reception"
	check(not game.save_store.write_snapshot(fixture.save_path, invalid, game.save_schema.decode), "invalid snapshots cannot overwrite disk")
	check(JSON.parse_string(FileAccess.get_file_as_string(fixture.save_path)).version == future.version, "failed validation preserves original file")
	check(not game.save_store.write_snapshot(fixture.unwritable_path, before, game.save_schema.decode), "write failure is reported")
	game._choose_companion(game.config.companions[0])
	check(game.progress.snapshot() == initial.meta, "new game clears cycle history")
	check(reset_fields(game._snapshot("promotion").run) == reset_fields(initial.run), "new game resets all run fields")
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture.save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("SAVE SYSTEM: %d checks; %d failures; old-save removal, validation, backup, checkpoint, reset, cycles" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
