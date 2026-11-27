extends RefCounted
## Presentation-only text, joined to rule records through stable story IDs.
var content: Dictionary
var last_error = ""
const CUSTOMER_FIELDS = ["request_text", "topic", "answers", "reply", "rumor", "opening", "closing", "header", "order_note"]

func reject(message: String) -> bool:
	last_error = message
	return false

func _init(source: Dictionary) -> void:
	content = source

func apply_customers(records: Array) -> bool:
	# Validate everything before mutating any record.
	last_error = ""
	if content.get("version") != 1 or not content.get("customers") is Dictionary:
		return reject("Invalid story catalog version/customers")
	for record in records:
		var key = str(record.get("story_id", ""))
		if not content.get("customers", {}).has(key):
			return reject("Missing customer story: " + key)
		if not content.customers[key] is Dictionary: return reject("Invalid customer story: " + key)
		var prose: Dictionary = content.customers[key]
		for field in prose:
			if field not in CUSTOMER_FIELDS: return reject("Unknown story field: " + key + "." + field)
			if field == "answers":
				if not prose[field] is Array or prose[field].is_empty(): return reject("Invalid answers: " + key)
				for answer in prose[field]:
					if not answer is String: return reject("Non-text answer: " + key)
			elif not prose[field] is String: return reject("Non-text field: " + key + "." + field)
		for field in ["request_text", "topic", "answers", "reply", "rumor"]:
			if not prose.has(field):
				return reject("Missing story field: " + key + "." + field)
		if int(record.good_answer) >= prose.answers.size(): return reject("Missing good answer: " + key)
		if record.has("choices") and prose.answers.size() != record.choices.size():
			return reject("Story answer count differs from rules: " + key)
	for record in records:
		var prose: Dictionary = content.customers[record.story_id]
		record.merge(prose.duplicate(true), true)
		if record.has("choices"):
			for index in range(record.choices.size()):
				record.choices[index].text = prose.answers[index]
	return true

func tutorial_text(key: String, values: Dictionary = {}) -> String:
	if not content.tutorial.story.has(key):
		push_error("Missing tutorial story: " + key)
		return ""
	return str(content.tutorial.story[key]).format(values)
