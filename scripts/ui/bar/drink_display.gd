extends Control
## Scalable, shared drink artwork. Decoration and bubbles never alter brew state.
var assets: Dictionary
var colors: Dictionary
var settings: Dictionary
var cup = ""
var ice = ""
var garnishes: Array = []
var recipe_name = ""
var has_liquid = false
var bubbles = false
var reduced_motion = false
var elapsed = 0.0
var bubble_positions: Array[Vector2] = []
var liquid_points = PackedVector2Array()
var texture_cache: Dictionary = {}
var ice_rect = Rect2()
var ice_polygons: Array[PackedVector2Array] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if bubbles and has_liquid and not reduced_motion:
		elapsed += delta
		queue_redraw()

func _texture(path: String) -> Texture2D:
	if not texture_cache.has(path): texture_cache[path] = load(path)
	return texture_cache[path]

func _fit(texture: Texture2D, area: Rect2) -> Rect2:
	var dimensions = texture.get_size()
	var displayed = dimensions * minf(area.size.x/dimensions.x, area.size.y/dimensions.y)
	return Rect2(area.get_center() - displayed/2, displayed)

func _draw() -> void:
	bubble_positions.clear()
	liquid_points.clear()
	ice_rect = Rect2()
	ice_polygons.clear()
	if cup.is_empty() or not assets.cups.has(cup): return
	var glass_texture = _texture(assets.cups[cup])
	var rect = _fit(glass_texture, Rect2(Vector2.ZERO, size))
	draw_texture_rect(glass_texture, rect, false)
	for point in settings.glass_liquids[cup]:
		liquid_points.append(rect.position + Vector2(point[0], point[1]) * rect.size)
	var bounds = Rect2(liquid_points[0], Vector2.ZERO)
	for point in liquid_points: bounds = bounds.expand(point)
	if has_liquid:
		draw_colored_polygon(liquid_points, Color("#" + colors.drinks[recipe_name]))
		draw_line(liquid_points[0], liquid_points[1], Color("fff0bd"), 1.5)
		if bubbles: _draw_bubbles(bounds)
	if not ice.is_empty() and ice != "无冰":
		var dimensions = bounds.size * Vector2(settings.presentation.ice_width_ratio, settings.presentation.ice_height_ratio)
		dimensions.y = maxf(dimensions.y, rect.size.y * float(settings.presentation.ice_min_height_ratio))
		var area = Rect2(bounds.get_center()-dimensions/2, dimensions)
		var texture = _texture(assets.ice[ice])
		var region: Array = settings.presentation.ice_regions[ice]
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(region[0],region[1])*texture.get_size(),Vector2(region[2],region[3])*texture.get_size())
		atlas.filter_clip = true
		ice_rect = _fit(atlas, area)
		# Anchor the fitted artwork itself, including wide crushed ice, rather
		# than its enclosing area. Both tabletop and settlement use this node.
		ice_rect.position.y = bounds.end.y - bounds.size.y * float(settings.presentation.ice_bottom_inset_ratio) - ice_rect.size.y
		var outline = PackedVector2Array([ice_rect.position, Vector2(ice_rect.end.x, ice_rect.position.y), ice_rect.end, Vector2(ice_rect.position.x, ice_rect.end.y)])
		ice_polygons = Geometry2D.intersect_polygons(outline, liquid_points)
		for polygon in ice_polygons:
			var uvs = PackedVector2Array()
			for point in polygon: uvs.append((atlas.region.position + (point - ice_rect.position) / ice_rect.size * atlas.region.size) / texture.get_size())
			draw_colored_polygon(polygon, Color.WHITE, uvs, texture)
	for i in garnishes.size():
		var texture = _texture(assets.garnishes[garnishes[i]])
		var dimensions = rect.size * Vector2(settings.presentation.garnish_width_ratio, settings.presentation.garnish_height_ratio)
		var x = lerpf(bounds.position.x, bounds.end.x, float(i+1)/float(garnishes.size()+1))
		var area = Rect2(Vector2(x-dimensions.x/2, bounds.position.y-dimensions.y*.6), dimensions)
		draw_texture_rect(texture, _fit(texture, area), false)

func _draw_bubbles(bounds: Rect2) -> void:
	var config: Dictionary = settings.presentation.bubbles
	for i in int(config.count):
		var phase = fposmod(elapsed / float(config.period) + float(i) / float(config.count), 1.0)
		var x_fraction = fposmod(float(i) * float(config.spacing), 1.0)
		var at = Vector2(lerpf(bounds.position.x, bounds.end.x, x_fraction), lerpf(bounds.end.y, bounds.position.y, phase))
		var radius = lerpf(float(config.radius_min), float(config.radius_max), x_fraction)
		var contained = true
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			if not Geometry2D.is_point_in_polygon(at+direction*radius, liquid_points): contained = false
		if not contained: continue
		bubble_positions.append(at)
		draw_arc(at, radius, 0, TAU, 16, Color(1, 1, 0.96, float(config.alpha)), 1.0, true)
