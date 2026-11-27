extends Control
## Replaceable shop art under real, paginated product controls.
var game
var page_index = 0
var names: Array = []
var sidebar: VBoxContainer
var catalog: VBoxContainer
var settings: Dictionary
var products: Dictionary = {}

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings = game.interface.shop
	names = game.selectable_liquids()
	names.sort()
	if game.tutorial_active:
		var target = game._find_recipe(game.tutorial.promotion_id).ingredients[0].name
		page_index = names.find(target) / int(settings.page_size)
	var background = TextureRect.new()
	background.texture = load(settings.background)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side_scroll = ScrollContainer.new()
	side_scroll.name = "ShopSidebar"
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(side_scroll)
	side_scroll.anchor_left = float(settings.layout.sidebar_left)
	side_scroll.anchor_right = float(settings.layout.sidebar_right)
	side_scroll.anchor_top = float(settings.layout.top)
	side_scroll.anchor_bottom = float(settings.layout.bottom)
	sidebar = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(sidebar)
	catalog = VBoxContainer.new()
	add_child(catalog)
	catalog.anchor_left = float(settings.layout.catalog_left)
	catalog.anchor_right = float(settings.layout.catalog_right)
	catalog.anchor_top = float(settings.layout.top)
	catalog.anchor_bottom = float(settings.layout.bottom)
	_render()

func _render() -> void:
	game.tutorial_purchase_button = null
	products.clear()
	game._clear(catalog)
	var nav = game._row(catalog)
	game._button(nav, settings.previous, func():
		page_index -= 1
		_render(), page_index == 0)
	var pages = ceili(float(names.size()) / float(settings.page_size))
	var page_label = game._label(nav, "%d / %d" % [page_index + 1, pages], 16)
	page_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game._button(nav, settings.next, func():
		page_index += 1
		_render(), page_index >= pages - 1)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = int(settings.columns)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for i in range(page_index * int(settings.page_size), mini((page_index + 1) * int(settings.page_size), names.size())):
		_product(grid, names[i])
	game._update_tutorial_hint.call_deferred()

func _product(grid: GridContainer, liquid: String) -> void:
	var card = game._panel(grid)
	card.add_theme_constant_override("separation", 3)
	var style: StyleBoxFlat = card.get_parent().get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.get_parent().add_theme_stylebox_override("panel", style)
	var frame = TextureRect.new()
	frame.texture = load(game.bar_assets.liquids[game.ingredient_label(liquid)])
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.custom_minimum_size.y = 48
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	var name_label = game._label(card, game.ingredient_label(liquid), 18, game.GOLD)
	var inventory = game._label(card, "库存 %d ml" % game.stock[liquid], 13, game.MUTED)
	var price_tag = RichTextLabel.new()
	price_tag.bbcode_enabled = true
	price_tag.fit_content = true
	price_tag.scroll_active = false
	price_tag.mouse_filter = Control.MOUSE_FILTER_PASS
	price_tag.add_theme_font_size_override("normal_font_size", int(settings.price_highlight.original_font_size))
	price_tag.add_theme_font_size_override("bold_font_size", int(settings.price_highlight.font_size))
	card.add_child(price_tag)
	_refresh_price(price_tag, liquid)
	var actions: Array = []
	var price = game._stock_price(liquid)
	var unavailable = game.competition.sold_out(liquid, game.day)
	var pack = game.pricing.catalog.ingredients[liquid].pack_ml
	var buy = game._button(card, "售罄" if unavailable else "＋%s ml / ¥%d" % [pack, price], game._buy_stock.bind(liquid), unavailable or game.money < price)
	actions.append({"button": buy, "packs": 1, "emergency": false, "bulk": false, "credit": false})
	if game.tutorial_active and liquid == game._find_recipe(game.tutorial.promotion_id).ingredients[0].name:
		game.tutorial_purchase_button = buy
	if unavailable and game.competition.can_emergency(liquid, game.day):
		var emergency_price = game._stock_price(liquid, true)
		var action = game._button(card, "应急采购 / ¥%d" % emergency_price, game._buy_stock.bind(liquid, 1, true), game.money < emergency_price)
		actions.append({"button": action, "packs": 1, "emergency": true, "bulk": false, "credit": false})
	elif not unavailable:
		var count = int(game.competition.rules.market.bulk_extra_packs)
		var bill = game._purchase_bill(liquid, count, game.pricing.pack_price(liquid, game.tiers), game.day, game.tiers, false, true)
		var action = game._button(card, "囤货 ×%d / ¥%d" % [count, bill.total], game._buy_stock.bind(liquid, count, false, true), game.money < int(bill.total))
		actions.append({"button": action, "packs": count, "emergency": false, "bulk": true, "credit": false})
		if game.competition.state.rival == "duren" and int(game.competition.state.credit_limit) > 0:
			var credit = int(game.competition.state.credit_limit) - int(game.competition.state.credit_used)
			var credit_button = game._button(card, "专项赊购 / ¥%d" % price, game._buy_stock.bind(liquid, 1, false, false, true), price > credit or (int(game.competition.state.credit_due_day) > 0 and int(game.competition.state.credit_due_day) <= game.day))
			actions.append({"button": credit_button, "packs": 1, "emergency": false, "bulk": false, "credit": true})
	products[liquid] = {"inventory": inventory, "actions": actions, "price_tag": price_tag, "name_label": name_label, "frame": frame}
	for child in card.get_children():
		if child is Button:
			child.add_theme_font_size_override("font_size", 14)
			for state in game.button_skins.profiles.common.textures:
				var button_style: StyleBox = child.get_theme_stylebox(state).duplicate()
				button_style.content_margin_top = 4
				button_style.content_margin_bottom = 4
				child.add_theme_stylebox_override(state, button_style)

func refresh() -> void:
	# Keep the actual controls, scroll container and keyboard focus alive.
	for liquid in products:
		var view: Dictionary = products[liquid]
		view.name_label.text = game.ingredient_label(liquid)
		view.frame.texture = load(game.bar_assets.liquids[game.ingredient_label(liquid)])
		view.inventory.text = "库存 %d ml" % game.stock[liquid]
		_refresh_price(view.price_tag, liquid)
		for action in view.actions:
			var bill = game._purchase_bill(liquid, int(action.packs), game.pricing.pack_price(liquid, game.tiers), game.day, game.tiers, action.emergency, action.bulk)
			var button: Button = action.button
			if bill.is_empty():
				button.disabled = true
				button.text = "售罄"
				continue
			var total = int(bill.total)
			if action.credit:
				button.text = "专项赊购 / ¥%d" % total
				button.disabled = total > int(game.competition.state.credit_limit) - int(game.competition.state.credit_used) or (int(game.competition.state.credit_due_day) > 0 and int(game.competition.state.credit_due_day) <= game.day)
			else:
				button.disabled = game.money < total
				button.text = ("应急采购 / ¥%d" % total) if action.emergency else (("囤货 ×%d / ¥%d" % [action.packs, total]) if action.bulk else "＋%s ml / ¥%d" % [game.pricing.catalog.ingredients[liquid].pack_ml, total])
	game._update_tutorial_hint()

func _refresh_price(tag: RichTextLabel, liquid: String) -> void:
	var base = game.pricing.pack_price(liquid, game.tiers)
	var ordinary = game._purchase_bill(liquid, 1, base, game.day, game.tiers, false, false, false)
	var before = int(ordinary.total) if not ordinary.is_empty() else game.competition.package_price(liquid, base, game.day, game.tiers, false, false)
	var current = game._stock_price(liquid)
	var presentation: Dictionary = settings.price_highlight
	var factor = game.competition.daily_events.price_factor(str(game.competition.ingredient_aliases.get(liquid, liquid)), game.day)
	var changed = not is_equal_approx(factor, 1.0) and current != before
	if changed:
		var color = presentation.up_color if current > before else presentation.down_color
		var arrow = presentation.up_arrow if current > before else presentation.down_arrow
		tag.text = "[color=%s][s]¥%d[/s]  [b]¥%d %s[/b][/color]" % [color, before, current, arrow]
		tag.tooltip_text = presentation.description.format({"before": before, "current": current})
	else:
		tag.text = "¥%d" % current
		tag.tooltip_text = ""
