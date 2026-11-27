extends Control
## Settlement still life, using the actual cup, ice and garnish from this order.
var game
var model
var table: TextureRect
var drink
var front: Panel

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 2.3
	custom_minimum_size = Vector2(560, 380)
	front = Panel.new()
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_theme_stylebox_override("panel", game._bar_style(Color(game.bar_ui.workbench_layout.cabinet_color)))
	add_child(front)
	table = TextureRect.new()
	table.name = "PresentationTable"
	var texture = AtlasTexture.new()
	texture.atlas = load("res://assets/bar/counter.png")
	var region: Array = game.bar_ui.workbench_layout.counter_crop
	var dimensions = texture.atlas.get_size()
	texture.region = Rect2(Vector2(region[0],region[1])*dimensions,Vector2(region[2],region[3])*dimensions)
	texture.filter_clip = true
	table.texture = texture
	table.material = ShaderMaterial.new()
	table.material.shader = preload("res://assets/materials/counter_surface.gdshader")
	var edges: Array = game.bar_ui.workbench_layout.counter_edges
	table.material.set_shader_parameter("edges", Vector4(edges[0], edges[1], edges[2], edges[3]))
	table.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)
	drink = preload("res://scripts/ui/bar/drink_display.gd").new()
	drink.name = "PresentedDrink"
	drink.assets = game.bar_assets
	drink.colors = game.drink_colors
	drink.settings = game.bar_ui
	drink.cup = model.cup if model.poured else ""
	drink.ice = model.ice
	drink.garnishes = model.garnishes.duplicate()
	drink.recipe_name = model.recipe.name
	drink.has_liquid = model.poured
	drink.bubbles = true
	drink.reduced_motion = game.pause_menu.reduced_motion
	add_child(drink)
	if not model.poured:
		var note = game._label(self, game.interface.result.no_drink, 22, game.MUTED)
		note.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		note.position -= Vector2(100,20)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var config: Dictionary = game.bar_ui.presentation
	var rect: Array = config.table_rect
	table.position = size * Vector2(rect[0],rect[1])
	table.size = size * Vector2(rect[2],rect[3])
	front.position = size * Vector2(.10,.74)
	front.size = size * Vector2(.80,.26)
	rect = config.drink_rect
	drink.position = size * Vector2(rect[0],rect[1])
	drink.size = size * Vector2(rect[2],rect[3])

func _process(_delta: float) -> void:
	if is_instance_valid(drink): drink.reduced_motion = game.pause_menu.reduced_motion
