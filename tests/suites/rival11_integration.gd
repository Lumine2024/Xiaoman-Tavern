extends SceneTree
var failures: Array[String]=[]
var checks=0
var game
var fixture: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		push_error(label)

func shop(id: String) -> void:
	game._begin_rival_run(game.config.companions[1],id,true)
	game.competition.state.street.enabled = false
	game.show_promotion()
	game.set_process(false)
	game.day=int(game.competition.rules.timeline.pressure_day)
	game.promotion=game._find_recipe(fixture.hard)
	game.money=int(fixture.cash)
	game.queue=[{"recipe_id":fixture.hard,"customer_index":0}]
	game.guest_index=1
	game.day_served=1
	game.show_shop()

func open(id: String,recipe_id: String,levels=0) -> void:
	game._begin_rival_run(game.config.companions[1],id,true)
	game.competition.state.street.enabled = false
	game.show_promotion()
	game.set_process(false)
	game.day=int(game.competition.rules.timeline.pressure_day)
	for family in game.tiers:
		game.tiers[family]=levels
	for index in range(game.recipes.size()):
		if game.recipes[index].id==recipe_id:
			game.recipe_option.select(index)
	game._open_day(true)
	game.set_process(false)
	game.queue[0].recipe_id=recipe_id
	game.queue[0].customer_index=0
	game.queue[0].quote=game.competition.quote(game._find_recipe(recipe_id),game.pricing.calculate(game._find_recipe(recipe_id),game.tiers),game.day,game.tiers)
	game._start_guest()
	game.set_process(false)
	game.guest.favorite=""

func complete(wrong_cup=false) -> int:
	game.brew.stage=5
	game.brew.cup="__wrong_cup__" if wrong_cup else game.brew.recipe.cup
	game.brew.ice=game.brew.expected_ice()
	game.brew.garnishes=game.brew.expected_garnishes().duplicate()
	game.brew.errors=1 if wrong_cup else 0
	game.dialogue=3
	game.rapport=false
	var before=game.money
	game._settle(false)
	check(game.last_mistake_report.count == 0, "legacy compliant order and excluded cup add no generic mistake")
	return game.money-before

func run() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/rival11_cases.json"))
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# This isolated v1.1 acceptance suite uses the immutable original menu
	# underlying its gold prices and baskets. Current ruled recipes are tested
	# by economy.gd, message_reasons.gd and the ordinary-game suites.
	for index in game.recipes.size():
		var source: Dictionary = game.pricing.catalog.recipes[game.recipes[index].id].duplicate(true)
		source.difficulty = game.config.difficulty_names[source.id[0]]
		if not source.cup.ends_with("杯"): source.cup += "杯"
		game.recipes[index] = source
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path=fixture.save_path
	game.config.customers_min=fixture.base_customers
	game.config.customers_max=fixture.base_customers
	open("karn",fixture.simple)
	check(game.queue.size()==int(fixture.expected.guard_customers),"actual guard queue has five")
	check(game.queue.filter(func(order): return order.recipe_id==fixture.simple).size()>=int(game.competition.rules.limits.promotion_guaranteed_orders),"actual queue reserves three")
	var saved_price=game.queue[0].quote.price
	for family in game.tiers:
		game.tiers[family]=game.config.base_tiers[family].size()-1
	check(complete()==saved_price,"settlement uses captured price, not changed upgrades")
	open("viola",fixture.hard)
	check(complete()==int(fixture.expected.viola_low),"actual correct cup/low grade pays112")
	open("viola",fixture.hard)
	check(complete(true)==int(fixture.expected.viola_low),"actual cup/low grade has no generic or judge double penalty")
	open("viola",fixture.hard,int(game.competition.rules.rivals.viola.min_base_tier)-1)
	check(complete()==int(fixture.expected.viola_upgraded),"actual second-tier pays155")
	shop("bella")
	var menu_ids=game.recipes.map(func(recipe): return recipe.id)
	var initial=game.money
	game._license_recipe()
	check(initial-game.money==int(game.pricing.catalog.other_prices.design_events.collaboration.price),"actual collaboration pays catalog80")
	check(game.recipes.map(func(recipe): return recipe.id)==menu_ids,"licensed recipe remains usable")
	game._license_recipe()
	check(initial-game.money==int(game.pricing.catalog.other_prices.design_events.collaboration.price),"collaboration cannot pay twice")
	shop("olga")
	var next_day=game.day+1
	game.competition.state.markets[str(next_day)]={"day":next_day,"variation":fixture.rising_variation,"outages":{},"order":[],"substitutes":{}}
	var basket={}
	for id in fixture.basket_recipes:
		var recipe=game._find_recipe(id)
		for item in recipe.ingredients+recipe.topup:
			basket[item.name]=true
	game._show_lock_service()
	var dialogs=game.get_children().filter(func(child): return child is AcceptDialog and not child.is_queued_for_deletion())
	var dialog=dialogs.back()
	for spin in dialog.find_children("*","SpinBox",true,false):
		if spin.get_meta("ingredient","") in basket:
			spin.value=1
	initial=game.money
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(initial-game.money==int(fixture.expected.lock_fee),"real lock dialog charges8")
	check(game.competition.state.locks[str(next_day)].packs.size()==basket.size(),"lock dialog captures selected quantities")
	check(game._load_game(),"service resumes after load")
	game._next_day()
	for name in basket:
		game._buy_stock(name)
	check(initial-game.money==int(fixture.expected.lock_basket_total),"real purchases plus fee total719")
	check(game.stock_ledger.daily.procurement==int(fixture.expected.lock_basket_base),"cash procurement separated from service fee")
	# Credit can be drawn in multiple purchases, then suspends while overdue.
	shop("duren")
	game.competition.state.informed.append("R-07")
	game._accept_credit()
	game.money=0
	game._buy_stock(fixture.cream,1,false,false,true)
	game._buy_stock(fixture.cream,1,false,false,true)
	check(int(game.competition.state.credit_used)==2*int(fixture.expected.cream_regular),"credit supports multiple same-day packs")
	check(game.money==0 and game.stock_ledger.daily.procurement==0,"credit is not cash income")
	game._next_day()
	var debt=game.competition.state.credit_used
	game._buy_stock(fixture.cream,1,false,false,true)
	check(game.competition.state.credit_used==debt,"unpaid debt blocks further borrowing")
	var obsolete = game._snapshot("promotion")
	obsolete.version = 3
	check(game.save_schema.decode(obsolete).is_empty(), "obsolete business document rejected")
	# Opening with no supplies creates a concrete, cash-feasible procurement plan.
	open("",fixture.simple)
	game.show_promotion()
	game.money=int(fixture.cash)
	for name in game.stock:
		game.stock[name]=0.0
	game.stock_ledger.reset(game.stock)
	game._open_day()
	check(not game.pending_open_plan.is_empty(),"opening proposes explicit procurement")
	var proposed=game.pending_open_plan.plan.duplicate(true)
	var confirmations=game.get_children().filter(func(child): return child is ConfirmationDialog and not child.is_queued_for_deletion())
	confirmations.back().get_ok_button().pressed.emit()
	await process_frame
	# Customer patience is sampled on reception, after procurement approval.
	var planned_fields=game.queue.duplicate(true)
	for order in planned_fields:
		order.erase("patience")
	var actual_orders=planned_fields.map(func(order): return JSON.stringify(order))
	var proposed_orders=proposed.orders.map(func(order): return JSON.stringify(order))
	actual_orders.sort()
	proposed_orders.sort()
	check(actual_orders==proposed_orders,"approved plan retains exact proposed orders")
	check(game.stock_ledger.daily.procurement==int(proposed.cost) and game.money==int(fixture.cash)-int(proposed.cost),"approved plan charges and records exact bill")
	var args=OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name()!="headless":
		shop("olga")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].get_basename()+"-shop.png")
		game._show_lock_service()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].get_basename()+"-lock.png")
	game.queue_free()
	await process_frame
	await create_timer(float(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/audio_release.json")).seconds)).timeout
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture.save_path+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path+suffix))
	print("RIVAL V1.1 INTEGRATION: %d checks; %d failures; receipts, services, credit, migration, reserved opening" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
