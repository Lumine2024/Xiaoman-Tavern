extends SceneTree
## Read-only delivery audit. --strict fails while any cue is still missing.
func _initialize() -> void:
	var path = "res://data/audio.json"
	var args = OS.get_cmdline_user_args()
	var source_index = args.find("--manifest")
	if source_index >= 0 and source_index + 1 < args.size(): path = args[source_index + 1]
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or not manifest.get("cues") is Dictionary:
		push_error("Invalid audio manifest: " + path)
		quit(1)
		return
	var pending = 0
	var invalid = 0
	for id in manifest.cues:
		var cue = manifest.cues[id]
		if not cue is Dictionary or not cue.get("files") is Array or cue.get("group") not in ["music", "ambience", "sfx"] or not cue.get("loop") is bool:
			invalid += 1
			print("[INVALID] " + id)
			continue
		var available = false
		for file in cue.files:
			if not file is String:
				invalid += 1
				continue
			if not ResourceLoader.exists(file): continue
			if not load(file) is AudioStream:
				invalid += 1
				print("[INVALID STREAM] " + file)
			else: available = true
		if not available:
			pending += 1
			print("[PENDING] %s: %s" % [id, str(cue.files)])
	print("AUDIO DELIVERY: %d cues; %d pending; %d invalid" % [manifest.cues.size(), pending, invalid])
	quit(1 if invalid > 0 or ("--strict" in args and pending > 0) else 0)
