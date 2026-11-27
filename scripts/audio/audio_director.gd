extends Node
## Optional assets: missing cues stay silent. Audio owns its RNG and no game state.
signal cue_requested(id: String)
signal cue_played(id: String)
var game
var manifest: Dictionary
var levels: Dictionary
var buses: Dictionary = {}
var decks: Dictionary = {}
var active_deck: Dictionary = {}
var active_cue: Dictionary = {}
var fades: Dictionary = {}
var loops: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cache: Dictionary = {}
var last_played: Dictionary = {}
var random = RandomNumberGenerator.new()
var context = ""
var paused = false
var voice_index = 0

func _exit_tree() -> void:
	for tween in fades.values():
		if tween != null: tween.kill()
	for player in voices + loops.values() + decks.get("music", []) + decks.get("ambience", []):
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	cache.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if manifest.is_empty(): manifest = preload("res://scripts/game/resource_data.gd").read("res://data/audio.json")
	levels = manifest.settings.defaults.duplicate(true)
	var settings = ConfigFile.new()
	if settings.load(game.interface.menu.settings_path) == OK:
		for group in levels: levels[group] = clampf(float(settings.get_value("audio", group, levels[group])), 0, 1)
	random.randomize()
	for group in levels:
		var bus_name = "Master" if group == "master" else "Xiaoman_" + group
		var index = AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		buses[group] = index
		set_level(group, float(levels[group]))
	for group in ["music", "ambience"]:
		decks[group] = [_player(group), _player(group)]
		active_deck[group] = 0
		active_cue[group] = ""
	for index in int(manifest.settings.voice_count): voices.append(_player("sfx"))
	get_tree().node_added.connect(_node_added)
	_bind_tree(get_tree().root)

func _player(group: String) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.bus = AudioServer.get_bus_name(int(buses[group]))
	add_child(player)
	return player

func set_level(group: String, value: float) -> void:
	if not levels.has(group): return
	levels[group] = clampf(value, 0, 1)
	var gain = float(levels[group])
	if group == "music" and paused: gain *= db_to_linear(float(manifest.settings.menu_duck_db))
	if buses.has(group):
		AudioServer.set_bus_mute(int(buses[group]), gain <= 0)
		AudioServer.set_bus_volume_db(int(buses[group]), linear_to_db(maxf(gain, 0.000001)))

func _resolve(id: String) -> String:
	var checked = []
	while manifest.cues.has(id) and id not in checked:
		checked.append(id)
		for path in manifest.cues[id].files:
			if ResourceLoader.exists(path): return id
		id = manifest.cues[id].get("fallback", "")
	return ""

func _stream(id: String) -> AudioStream:
	var definition: Dictionary = manifest.cues[id]
	var paths: Array = definition.files.filter(func(path): return ResourceLoader.exists(path))
	if paths.is_empty(): return null
	var path: String = paths[random.randi_range(0, paths.size() - 1)]
	var key = path + str(definition.loop)
	if cache.has(key): return cache[key]
	var resource = load(path)
	if not resource is AudioStream: return null
	var stream: AudioStream = resource.duplicate()
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3: stream.loop = bool(definition.loop)
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if definition.loop else AudioStreamWAV.LOOP_DISABLED
		if definition.loop: stream.loop_end = int(stream.get_length() * stream.mix_rate)
	cache[key] = stream
	return stream

func enter(next_context: String) -> void:
	if not manifest.contexts.has(next_context): return
	context = next_context
	for group in ["music", "ambience"]: _switch(group, manifest.contexts[context][group])

func _switch(group: String, requested: String) -> void:
	var id = _resolve(requested)
	if active_cue[group] == id: return
	active_cue[group] = id
	if fades.has(group): fades[group].kill()
	var old: AudioStreamPlayer = decks[group][int(active_deck[group])]
	var next_index = 1 - int(active_deck[group])
	var next: AudioStreamPlayer = decks[group][next_index]
	next.stop()
	active_deck[group] = next_index
	var tween = create_tween().set_parallel(true)
	fades[group] = tween
	tween.tween_property(old, "volume_db", float(manifest.settings.silence_db), float(manifest.settings.fade_seconds))
	if id.is_empty():
		tween.chain().tween_callback(old.stop)
		return
	next.stream = _stream(id)
	if next.stream == null: return
	next.volume_db = float(manifest.settings.silence_db)
	next.play()
	next.stream_paused = group == "ambience" and paused
	tween.tween_property(next, "volume_db", float(manifest.cues[id].gain_db), float(manifest.settings.fade_seconds))
	tween.chain().tween_callback(old.stop)
	cue_played.emit(id)

func play(id: String) -> bool:
	cue_requested.emit(id)
	var resolved = _resolve(id)
	if resolved.is_empty(): return false
	var definition: Dictionary = manifest.cues[resolved]
	if paused and not definition.get("ui", false): return false
	var now = Time.get_ticks_msec()
	if now - int(last_played.get(id, -1000000)) < int(definition.get("cooldown_ms", 0)): return false
	var stream = _stream(resolved)
	if stream == null: return false
	last_played[id] = now
	var player = voices[voice_index % voices.size()]
	voice_index += 1
	player.stop()
	player.stream = stream
	player.volume_db = float(definition.gain_db)
	player.set_meta("ui", definition.get("ui", false))
	player.stream_paused = false
	player.play()
	cue_played.emit(resolved)
	return true

func loop(channel: String, requested: String) -> void:
	var id = _resolve(requested)
	if loops.has(channel) and loops[channel].get_meta("cue") == id: return
	if not loops.has(channel): loops[channel] = _player("sfx")
	var player: AudioStreamPlayer = loops[channel]
	player.stop()
	player.set_meta("cue", id)
	if id.is_empty(): return
	player.stream = _stream(id)
	if player.stream == null: return
	player.volume_db = float(manifest.cues[id].gain_db)
	player.play()
	player.stream_paused = paused
	cue_played.emit(id)

func stop_loop(channel: String) -> void:
	if loops.has(channel):
		loops[channel].stop()
		loops[channel].set_meta("cue", "")

func stop_world_loops() -> void:
	for channel in loops: stop_loop(channel)

func set_paused(value: bool) -> void:
	paused = value
	set_level("music", float(levels.music))
	for player in decks.ambience: player.stream_paused = value
	for player in loops.values(): player.stream_paused = value
	for player in voices:
		if not player.get_meta("ui", false): player.stream_paused = value

func _process(_delta: float) -> void:
	if game == null: return
	if paused != get_tree().paused: set_paused(get_tree().paused)
	if game.playing and game.pouring: loop("pour", "sfx.pour")
	else: stop_loop("pour")
	var mixing = ""
	if game.playing and game.mixing and game.brew != null: mixing = manifest.mix_cues.get(game.brew.recipe.method, "")
	elif game.playing and is_instance_valid(game.workbench) and game.workbench.straight_shake_left > 0: mixing = "sfx.mix_straight"
	if mixing.is_empty(): stop_loop("mix")
	else: loop("mix", mixing)

func _node_added(node: Node) -> void:
	if node is BaseButton: _bind_button.call_deferred(node)

func _bind_tree(node: Node) -> void:
	if node is BaseButton: _bind_button(node)
	for child in node.get_children(): _bind_tree(child)

func _bind_button(button) -> void:
	if not is_instance_valid(button) or button.has_meta("audio_bound") or button.get_meta("audio_skip_ui", false): return
	button.set_meta("audio_bound", true)
	button.pressed.connect(func(): play("sfx.ui_click"))
