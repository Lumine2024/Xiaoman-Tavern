extends RefCounted
## Legacy display prefixes are formatting, never a player-facing truth label.
static func clean(text: String) -> String:
	for prefix in ["闲聊：", "消息："]:
		if text.begins_with(prefix): return text.trim_prefix(prefix)
	return text

static func normalize(notes: Array) -> Array:
	var result: Array = []
	for note in notes:
		var text = clean(note)
		if not text.is_empty() and text not in result: result.append(text)
	return result
