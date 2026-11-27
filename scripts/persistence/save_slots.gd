extends RefCounted
## Slots are independent run documents; onboarding completion is a separate profile.
var game
var settings: Dictionary
var default_path: String
var active_slot = -1
var store = preload("res://scripts/persistence/save_store.gd").new()

func managed() -> bool:
	return game.config.save_path == default_path or game.config.save_path in settings.manual_paths

func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

func paths() -> Array:
	var result: Array = settings.manual_paths.duplicate()
	result.append_array(settings.auto_paths)
	return result

func any_exists() -> bool:
	return paths().any(func(path): return exists(path))

func read(path: String) -> Dictionary:
	return store.load_snapshot(path, game.save_schema.decode)

func _profile(source: Dictionary) -> Dictionary:
	if source.get("version") != 1 or not source.get("tutorial_completed") is bool: return {}
	return source.duplicate(true)

func profile_state() -> Dictionary:
	var profile = store.load_snapshot(settings.profile_path, _profile)
	if not profile.is_empty(): return profile
	return {} if exists(settings.profile_path) else {"version": 1, "tutorial_completed": false}

func complete_tutorial() -> bool:
	return store.write_snapshot(settings.profile_path, {"version": 1, "tutorial_completed": true}, _profile)

func stamped(snapshot: Dictionary, slot: int) -> Dictionary:
	var result = snapshot.duplicate(true)
	result.file_info = {"saved_at": Time.get_unix_time_from_system(), "slot": slot}
	return result

func autosave(snapshot: Dictionary) -> void:
	if not managed(): return
	var target: String = settings.auto_paths[0]
	var oldest = INF
	for path in settings.auto_paths:
		var document = read(path)
		var timestamp = float(document.get("file_info", {}).get("saved_at", 0))
		if timestamp < oldest:
			oldest = timestamp
			target = path
	# The active canonical slot is already committed; report a secondary failure clearly.
	if not store.write_snapshot(target, stamped(snapshot, active_slot), game.save_schema.decode):
		game._storage_notice(store.last_error)

func activate(path: String, document: Dictionary) -> void:
	active_slot = settings.manual_paths.find(path)
	if path in settings.auto_paths:
		var index = int(document.get("file_info", {}).get("slot", -1))
		if index >= 0 and index < settings.manual_paths.size(): active_slot = index
	game.config.save_path = settings.manual_paths[active_slot] if active_slot >= 0 else default_path

func describe(document: Dictionary) -> String:
	var run: Dictionary = document.run
	var who = run.companion
	for companion in game.config.companions:
		if companion.id == who: who = companion.name
	var timestamp = float(document.get("file_info", {}).get("saved_at", 0))
	var time_text = settings.time_unknown
	if timestamp > 0:
		time_text = Time.get_datetime_string_from_unix_time(int(timestamp) + int(Time.get_time_zone_from_system().bias) * 60, true)
	return "%s\n第 %d 周目 · 第 %d 日 · ¥%d\n同行者：%s · %s" % [time_text, document.meta.cycle, run.day, run.money, who, settings.phases.get(run.phase, run.phase)]

# Only explicit managed run paths may be removed; never the shared profile.
func delete_slot(path: String) -> bool:
	store.last_error = ""
	if path not in paths(): return false
	if game.screen != "title" and path == game.config.save_path:
		store.last_error = settings.delete_active
		return false
	for suffix in [".tmp", ".bak", ""]:
		var target = path + suffix
		if FileAccess.file_exists(target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) != OK:
			store.last_error = settings.delete_error
			return false
	return true
