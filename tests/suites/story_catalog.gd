extends SceneTree
var checks = 0
var failures = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	var records = JSON.parse_string(FileAccess.get_file_as_string("res://data/customers.json"))
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/story_cases.json"))
	var catalog = preload("res://scripts/game/story_catalog.gd").new(data.duplicate(true))
	var rules_before = records.duplicate(true)
	var first = records[int(cases.customer_index)]
	var key = first.story_id
	catalog.content.customers[key].topic = cases.replacement
	catalog.content.customers[key].answers[0] = cases.replacement
	check(catalog.apply_customers(records), "valid text joins to rules")
	check(first.topic == cases.replacement and first.answers[0] == cases.replacement and first.choices[0].text == cases.replacement, "edited prose and choice label used")
	for index in range(records.size()):
		var copy = records[index].duplicate(true)
		for field in catalog.CUSTOMER_FIELDS: copy.erase(field)
		for choice in copy.get("choices", []): choice.erase("text")
		check(copy == rules_before[index], "prose does not change rules " + str(index))
	check(catalog.tutorial_text(cases.template_key, cases.values) == cases.expected_template, "tutorial variables render from authored text")
	for invalid in cases.invalid:
		var broken = data.duplicate(true)
		if invalid.kind == "missing": broken.customers.erase(key)
		elif invalid.kind == "field": broken.customers[key][invalid.field] = invalid.value
		elif invalid.kind == "count": broken.customers[key].answers = []
		var bad_catalog = preload("res://scripts/game/story_catalog.gd").new(broken)
		var untouched = rules_before.duplicate(true)
		check(not bad_catalog.apply_customers(untouched) and not bad_catalog.last_error.is_empty(), "reject invalid story " + invalid.kind)
		check(untouched == rules_before, "rejected story leaves rules untouched")
	print("STORY CATALOG: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
