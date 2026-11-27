extends SceneTree
var checks=0
var failures: Array[String]=[]
var game
var fixture: Dictionary
var C=preload("res://scripts/competition/competition.gd")
var Planner=preload("res://scripts/economy/order_planner.gd")

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures.append(label)
		push_error(label)

func model(id: String) -> RefCounted:
	var result=C.new(game.competition.data)
	result.reset(id)
	return result

func quote(m,recipe: Dictionary,day: int,tiers: Dictionary={}) -> Dictionary:
	return m.quote(recipe,game.pricing.calculate(recipe,tiers),day,tiers)

func receipt(m,q: Dictionary,recipe: Dictionary,wrong_cup=false,tiers: Dictionary={}) -> int:
	return C.money(float(q.price)*float(m.modifiers(q,recipe,wrong_cup,false,tiers).revenue_multiplier))

func run() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/rival11_cases.json"))
	var expected: Dictionary=fixture.expected
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.bar_ui.transitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui_test_settings.json")), true)
	game.config.save_path=fixture.save_path
	game._choose_companion(game.config.companions[0])
	game.set_process(false)
	var simple=game._find_recipe(fixture.simple)
	var hard=game._find_recipe(fixture.hard)
	var cheap=game._find_recipe(fixture.cheap)
	var classic=game._find_recipe(fixture.classic)
	var day=int(game.competition.rules.timeline.pressure_day)
	var rng=RandomNumberGenerator.new()
	rng.seed=int(fixture.seed)
	# A01: timetable and no-rival mode.
	for id in [""]+game.competition.rules.rivals.keys():
		var m=model(id)
		for date in fixture.dates:
			check(m.active(int(date))==(id!="" and int(date)>=day),"A01 pressure "+id+str(date))
			check(m.dialogue(int(date)).is_empty()==(id=="" or int(date)<int(m.rules.timeline.rumor_day)),"A01 rumors")
	# A02/A03: quote equals settlement; only over-60 simple guard loses traffic.
	var k=model("karn")
	k.begin_day(simple,day)
	var guard=quote(k,simple,day)
	check(guard.price==expected.guard_price,"A02 guard price")
	check(int(fixture.base_customers)+k.traffic_delta(simple,day,guard.price)==int(expected.guard_customers),"A02 guard customers")
	check(receipt(k,guard,simple)*int(k.rules.limits.promotion_guaranteed_orders)==int(expected.guard_three),"A02 guard three")
	k.state.strategy="follow"
	var matched=quote(k,simple,day)
	check(matched.price==expected.match_price,"A02 match price")
	check(int(fixture.base_customers)+k.traffic_delta(simple,day,game.pricing.calculate(simple).price)==int(expected.match_customers),"A02 restores exactly one")
	check(receipt(k,matched,simple)*int(k.rules.limits.promotion_guaranteed_orders)==int(expected.match_three),"A02 no hidden margin penalty")
	k.close_day(simple,day)
	k.begin_day(simple,day+1)
	check(quote(k,simple,day+1).price==expected.match_price,"A02 next-day fixed quote")
	k.state.strategy="hold"
	for recipe in [cheap,hard]:
		k.state.last_promotion=recipe.id
		check(k.traffic_delta(recipe,day,game.pricing.calculate(recipe).price)==0,"A03 cheap/hard retains traffic")
		check(Planner.new(k,game.pricing,day,{}).three(recipe,game.stock,0).orders.size()==int(k.rules.limits.promotion_guaranteed_orders),"A03 three reserved")
	# A04/A05: copy and classic are min penalties, never multiplied.
	var b=model("bella")
	b.begin_day(hard,day)
	b.state.promotion_streak=int(b.profile().copy_offer_start_streak_day)-1
	var before=receipt(b,quote(b,hard,day),hard)
	b.state.promotion_streak=int(b.profile().copy_offer_start_streak_day)
	var after=receipt(b,quote(b,hard,day),hard)
	check(before==expected.hard_price and after==expected.copy_price,"A04 copy actual receipts")
	check((before-after)*int(b.rules.limits.promotion_guaranteed_orders)==int(expected.copy_difference),"A04 three cups differ by 42")
	b.state.last_promotion=classic.id
	check(receipt(b,quote(b,classic,day),classic)==expected.classic_copy_price,"A05 duplicate penalty once")
	check(b.promotion_factor(hard,day)==1,"A04 no order-weight penalty")
	# A06: same rival reason is one loss, protected auxiliaries, no warm content.
	var m=model("marta")
	m.content.regular_customer_ids=[fixture.regular]
	m.state.regular_visits[fixture.regular]=day-int(m.profile().missed_regular_days)-1
	var crushed=game._find_recipe(fixture.crushed)
	m.begin_day(crushed,day)
	check(int(fixture.base_customers)+m.traffic_delta(crushed,day,game.pricing.calculate(crushed).price)==int(expected.guard_customers),"A06 combined Marta loss")
	check(is_zero_approx(m.outage_probability(fixture.cream,day,{})),"A06 shortage rate zero")
	check(m.procurement_factor(fixture.cream,day,{})==1 and m.profile().warm_recipe_ids.is_empty(),"A06 no price discount or invented warm recipe")
	# A07: exclusive expiry and ordinary/emergency prices have separate bases.
	var d=model("duren")
	var outage_day=int(fixture.outage_start)
	for date in range(outage_day,int(fixture.outage_expiry)+1):
		d.state.markets[str(date)]={"day":date,"variation":0.0,"outages":{fixture.lime:int(fixture.outage_expiry)},"order":[fixture.lime],"substitutes":{}}
	check(d.sold_out(fixture.lime,outage_day) and d.sold_out(fixture.lime,outage_day+1) and not d.sold_out(fixture.lime,int(fixture.outage_expiry)),"A07 D10 D11 out, D12 expiry")
	check(float(game.stock[fixture.lime])>0,"A07 existing stock remains")
	var cream_base=game.pricing.pack_price(fixture.cream)
	check(d.package_price(fixture.cream,cream_base,outage_day,{})==expected.cream_regular,"A07 30*1.15 rounds to 35")
	check(d.package_price(fixture.cream,cream_base,outage_day,{},true)==expected.cream_emergency,"A07 emergency 42, not stacked")
	check(is_equal_approx(d.outage_probability(fixture.lime,outage_day,{}),float(d.rules.market.base_aux_outage_probability)+float(d.profile().outage_delta_pp)/100.0),"A07 8 percent")
	# A08: global cap and deterministic releasing, with real cash feasibility.
	d.state.last_promotion=hard.id
	d.prepare_market(outage_day,game.pricing.catalog,{},game.recipes,game.stock,rng)
	check(d.market(outage_day+1).outages.size()<=int(d.rules.limits.max_outages_total),"A08 outage cap")
	var stock=game.stock.duplicate(true)
	for name in stock:
		stock[name]=0.0
	var p=Planner.new(d,game.pricing,outage_day,{})
	d.state.markets[str(outage_day)].outages={}
	var budget=int(p.three(simple,stock,int(fixture.cash)).cost)
	d.state.markets[str(outage_day)].outages={fixture.lime:outage_day+2,"汤力水":outage_day+2}
	var saved_order=d.market(outage_day).order.duplicate()
	check(p.three(simple,stock,budget).is_empty(),"A08 cash rejects emergency-priced plan")
	check(p.repair_market([simple],stock,budget),"A08 restores a three-cup path")
	check(d.market(outage_day).order==saved_order,"A08 no re-roll during repair")
	# A09: legal substitution neither adds brew errors nor penalizes difficult band.
	for recipe in [simple,hard]:
		d.state.last_promotion=recipe.id
		var q=quote(d,recipe,outage_day)
		q.legal_substitute=true
		check(receipt(d,q,recipe)==(expected.substitute_simple if recipe.id==simple.id else expected.substitute_hard),"A09 legal substitute "+recipe.id)
	check(int(d.rules.market.substitute_brew_errors)==0,"A09 no synthetic brew error")
	# A10: first-tier, wrong cup, second-tier all use the single strongest factor.
	var v=model("viola")
	v.begin_day(hard,day)
	var q=quote(v,hard,day)
	check(receipt(v,q,hard)==expected.viola_low and receipt(v,q,hard,true)==expected.viola_low,"A10 both failures still 112")
	var levels={}
	for family in game.config.base_tiers:
		levels[family]=int(v.profile().min_base_tier)-1
	q=quote(v,hard,day,levels)
	check(receipt(v,q,hard,false,levels)==expected.viola_upgraded,"A10 second-tier 155")
	check(v.modifiers(q,hard,true,false,levels).exclude_cup,"A10 cup removed from generic penalty")
	# A11: real catalog basket, fee once/day, pack limits and sold-out check.
	var o=model("olga")
	var next_day=day+1
	o.state.markets[str(next_day)]={"day":next_day,"variation":fixture.rising_variation,"outages":{},"order":[],"substitutes":{}}
	var packs={}
	var bases={}
	for id in fixture.basket_recipes:
		var recipe=game._find_recipe(id)
		for item in recipe.ingredients+recipe.topup:
			packs[item.name]=1
			bases[item.name]=game.pricing.pack_price(item.name)
	var base_sum=0
	var market_sum=0
	for name in packs:
		base_sum+=int(bases[name])
		market_sum+=o.package_price(name,bases[name],next_day,{})
	check(base_sum==expected.lock_basket_base and market_sum==expected.lock_basket_market,"A11 711/754 catalog basket")
	var fee=o.lock_service(day,packs,bases,int(fixture.cash))
	check(fee==expected.lock_fee and o.lock_service(day,packs,bases,int(fixture.cash))<0,"A11 fee fixed 8, once/day")
	var total=fee
	for name in packs:
		var bill=o.purchase_bill(name,1,bases[name],next_day,{})
		total+=int(bill.total)
		o.commit_purchase(bill,next_day)
	check(total==expected.lock_basket_total and market_sum-total==int(expected.lock_basket_saving),"A11 total719 saving35")
	check(o.purchase_bill(fixture.lime,1,bases[fixture.lime],next_day,{}).total==o.package_price(fixture.lime,bases[fixture.lime],next_day,{}),"A11 excess quantity uses market")
	o.state.markets[str(next_day)].outages[fixture.lime]=next_day+1
	check(o.purchase_bill(fixture.lime,1,bases[fixture.lime],next_day,{}).is_empty(),"A11 lock cannot bypass outage")
	var before_market=o.market(next_day).duplicate(true)
	o.prepare_market(day,game.pricing.catalog,{},game.recipes,game.stock,rng)
	var cached=o.state.duplicate(true)
	o.prepare_market(day,game.pricing.catalog,{},game.recipes,game.stock,rng)
	check(o.state==cached and o.market(next_day)==before_market,"A11 market and forecast cached")
	# A12: net flow limits; one confirmed ending effective next day, once only.
	k.state.today_traffic=-2
	k.state.traffic_sources={"switch":-1,"event":-1}
	k.state.strategy="hold"
	k.state.last_promotion=simple.id
	check(k.traffic_delta(simple,day,expected.guard_price)==-int(k.rules.limits.traffic_loss_per_day),"A12 traffic clamps")
	k.state.hold_days=int(k.profile().counterplay.hard_promotion_without_match_streak_days)
	k.state.favorable_choices=int(k.rules.endings.alliance_choices)
	var ending_day=int(k.rules.timeline.ending_day)
	k._check_ready(ending_day)
	check(not k.confirm_ending("counterplay",ending_day-1),"A12 no early ending confirmation")
	check(k.confirm_ending("counterplay",ending_day) and not k.confirm_ending("alliance",ending_day),"A12 one ending only")
	check(k.active(ending_day),"A12 confirmation keeps today's pressure")
	k.apply_pending_ending(ending_day+1)
	var reward=k.state.permanent_traffic
	k.apply_pending_ending(ending_day+2)
	check(not k.active(ending_day+1) and k.state.permanent_traffic==reward,"A12 next-day effect, reward once")
	# Persistence uses the production schema with the actual Olga contract.
	game.competition=o
	game.day=day
	var saved_locks=o.state.locks.duplicate(true)
	check(game._save("promotion"),"A11 save contract")
	check(game._load_game(),"A11 load contract")
	check(game.competition.state.locks==saved_locks,"A11 locked quantities persist")
	game.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture.save_path+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.save_path+suffix))
	print("RIVAL V1.1: %d checks; %d failures; A01-A12" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
