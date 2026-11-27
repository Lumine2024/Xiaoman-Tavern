extends SceneTree
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/economy_cases.json"))
	var oracle = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pricing_reference.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path = fixture.save_path
	game._choose_companion(game.config.companions[0])
	game.set_process(false)
	for row in oracle:
		# The unchanged gold cases describe the delivered pricing-v1 catalogue recipes.
		var actual = game.pricing.calculate(game.pricing.catalog.recipes[row.id], row.tiers)
		check(actual.price == row.price, row.id + " Decimal price " + str(row.tiers))
		check(absf(float(actual.cost) - float(row.cost)) < 0.000001, row.id + " Decimal cost")
	var revised = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pricing_rulings_reference.json"))
	for row in revised:
		game.stock_only_mode = bool(row.unified)
		var actual = game.pricing.calculate(game._find_recipe(row.id), row.tiers)
		check(actual.price == row.price and absf(float(actual.cost) - float(row.cost)) < 0.000001, row.id + " revised DOCX Decimal reference")
	game.stock_only_mode = false
	for name in game.pricing.catalog.ingredients:
		check(is_finite(game.pricing.pack_price(name)), "priced liquid " + name)
	for customer in game.customers:
		if customer.has("choices"):
			check(customer.choices.size() == 3, customer.name + " three answers")
			check(customer.choices.any(func(choice): return choice.answer == "cold" or choice.get("leak", false)), customer.name + " conversational trap")
	game.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture.save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path + suffix))
	print("ECONOMY: %d checks; %d failures; Decimal reference and authored dialogue; rival acceptance is tests/suites/rival11.gd" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
