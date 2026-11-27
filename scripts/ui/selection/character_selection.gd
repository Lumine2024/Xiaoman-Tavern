extends Control
## Shared native character selector. The reel is clipped; its position is the
## only animated state. A rival is sampled once before deceleration starts.
signal confirmed(entry: Dictionary)
signal back_requested

var sound
var settings: Dictionary
var artwork: Dictionary
var texture_cache: Dictionary = {}
var entries: Array = []
var rival_mode = false
var selected = 0
var rolling = false
var settled = false
var reel_position = 0.0:
	set(value):
		reel_position = value
		if is_instance_valid(reel): reel.queue_redraw()
var reel: Control
var heading: Label
var hint: Label
var name_label: Label
var title_label: Label
var effect: Label
var pitch: Label
var counter: Label
var action: Button
var back: Button
var seats: Array[Button] = []
var tween: Tween
var random = RandomNumberGenerator.new()

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not rival_mode: settings.slots = int(settings.companion_slots)
	random.randomize()
	gui_input.connect(_wheel_input)
	heading = _label(settings.rival_heading if rival_mode else settings.companion_heading, 34)
	hint = _label(settings.rival_hint if rival_mode else settings.companion_hint, 17, Color("a3b4aa"))
	reel = Control.new()
	reel.clip_contents = true
	reel.mouse_filter = Control.MOUSE_FILTER_STOP
	reel.gui_input.connect(_wheel_input)
	add_child(reel)
	reel.draw.connect(_draw_reel)
	name_label = _label("", 48)
	title_label = _label("", 21, Color("dcb779"))
	effect = _label("", 22)
	pitch = _label("", 19, Color("a3b4aa"))
	counter = _label("", 16, Color("dcb779"))
	for i in int(settings.slots):
		var seat = Button.new()
		seat.toggle_mode = true
		seat.text = "？" if rival_mode else (entries[i].name if i < entries.size() else settings.empty_name)
		seat.clip_text = true
		seat.add_theme_font_size_override("font_size", 15)
		seat.disabled = rival_mode or i >= entries.size()
		seat.pressed.connect(select.bind(i))
		add_child(seat)
		seats.append(seat)
	back = Button.new()
	back.text = settings.back
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
	action = Button.new()
	action.pressed.connect(_activate)
	add_child(action)
	resized.connect(_layout)
	_refresh()
	_layout()

func _exit_tree() -> void:
	if is_instance_valid(sound): sound.stop_loop("draw")
	if tween: tween.kill()

func _label(value: String, font_size: int, color = Color("eee5d2")) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _place(control: Control, x: float, y: float, w: float, h: float) -> void:
	control.position = size * Vector2(x, y)
	control.size = size * Vector2(w, h)

func _layout() -> void:
	_place(heading, .035, .02, .9, .065)
	_place(hint, .035, .10, .92, .045)
	_place(reel, .035, .17, .93, .66)
	# These labels retain the selected entry for callers. Text is
	# drawn inside each moving card so it travels with its portrait frame.
	for label in [name_label, title_label, effect, pitch]:
		_place(label, .35, .6, .30, .1)
		label.hide()
	_place(counter, .035, .86, .28, .045)
	var gap = .012
	var width = (.60 - gap * (settings.slots - 1)) / settings.slots
	for i in seats.size(): _place(seats[i], .35 + i * (width + gap), .86, width, .045)
	_place(back, .035, .935, .14, .055)
	_place(action, .62, .935, .33, .055)
	queue_redraw()
	reel.queue_redraw()

func _wheel_input(event: InputEvent) -> void:
	if rival_mode or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: return
	var direction = 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
	for distance in range(1, int(settings.slots) + 1):
		var index = posmod(selected + direction * distance, int(settings.slots))
		if index < entries.size():
			select(index)
			break
	accept_event()

func select(index: int) -> void:
	if rival_mode or rolling or index < 0 or index >= entries.size(): return
	selected = index
	if tween: tween.kill()
	tween = create_tween()
	tween.tween_property(self, "reel_position", float(index), float(settings.select_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_refresh()

func _activate() -> void:
	if rolling: return
	if not rival_mode or settled:
		confirmed.emit(entries[selected])
		return
	selected = random.randi_range(0, entries.size() - 1)
	rolling = true
	if is_instance_valid(sound): sound.loop("draw", "sfx.draw_roll")
	_refresh()
	tween = create_tween()
	var destination = float(int(settings.turns) * int(settings.slots) + selected)
	tween.tween_property(self, "reel_position", destination, float(settings.spin_seconds)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		rolling = false
		settled = true
		if is_instance_valid(sound):
			sound.stop_loop("draw")
			sound.play("sfx.draw_reveal")
		reel_position = float(selected)
		_refresh())

func _refresh() -> void:
	var hidden = rival_mode and not settled
	var entry: Dictionary = entries[selected]
	name_label.text = "？" if hidden else str(entry.name)
	title_label.text = settings.rival_tag if hidden else (str(entry.shop) + " · " + str(entry.axis) if rival_mode else str(entry.title))
	effect.text = settings.rolling if rolling else (settings.rival_hint if hidden else str(entry.change if rival_mode else entry.description))
	pitch.text = "" if hidden or not rival_mode else str(entry.pitch)
	counter.text = "%s     %s / %02d" % [settings.rival_tag if rival_mode else settings.companion_tag, "—" if hidden else "%02d" % (selected + 1), int(settings.slots)]
	action.text = settings.rolling if rolling else (settings.begin if settled else settings.roll) if rival_mode else settings.companion_confirm
	action.disabled = rolling
	back.disabled = rolling or settled
	for i in seats.size():
		seats[i].set_pressed_no_signal(not hidden and i == selected)
	queue_redraw()

func _draw() -> void:
	draw_style_box(_style(Color("101e23"), Color("45524b")), Rect2(Vector2.ZERO, size))

func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style

func _card_text(value: String, at: Vector2, width: float, font_size: int, color: Color) -> void:
	var paragraph = TextParagraph.new()
	paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER
	paragraph.width = width
	paragraph.add_string(value, get_theme_default_font(), font_size)
	paragraph.draw_outline(reel.get_canvas_item(), at, 2, Color("080806"))
	paragraph.draw(reel.get_canvas_item(), at, color)

func _art(path: String, area: Rect2, fit = false) -> void:
	if not texture_cache.has(path): texture_cache[path] = load(path)
	var texture: Texture2D = texture_cache[path]
	if fit:
		var dimensions = texture.get_size()
		var displayed = dimensions * minf(area.size.x / dimensions.x, area.size.y / dimensions.y)
		area = Rect2(area.get_center() - displayed / 2, displayed)
	reel.draw_texture_rect(texture, area, false)

func _draw_reel() -> void:
	var extent = reel.size
	var card: Dictionary = settings.card
	var width = extent.x * float(card.width_ratio)
	var step = width + extent.x * float(card.gap_ratio)
	var center = extent.x * .5
	var pad = float(card.padding)
	for offset in range(-2, 3):
		var ordinal = int(floor(reel_position)) + offset
		var index = posmod(ordinal, int(settings.slots))
		if rival_mode and settled and index != selected: continue
		var x = center + (ordinal - reel_position) * step
		if rival_mode and not settled:
			var back_rect = Rect2(x - width/2, 2, width, extent.y - 4)
			_art(artwork.cards.background, back_rect)
			_card_text("？", back_rect.position + Vector2(pad, back_rect.size.y * .45), width-pad*2, 48, Color("ead2a0"))
			continue
		var empty = index >= entries.size()
		var tint = Color("aab4ad") if empty else Color(settings.colors[index % settings.colors.size()])
		var rect = Rect2(x - width/2, 2, width, extent.y - 4)
		_art(artwork.cards.background, rect)
		var portrait = Rect2(rect.position + Vector2(pad, pad), Vector2(width - pad*2, rect.size.y * float(card.portrait_height_ratio)))
		# The selected frame has an opaque centre. Keep both portrait frames below
		# the character, confined to the illustration window above the live text.
		_art(artwork.cards.selected if absf(float(ordinal) - reel_position) < .5 else artwork.cards.frame, portrait)
		var path: String = artwork.cards.empty if empty else artwork["rivals" if rival_mode else "companions"].get(str(entries[index].id), artwork.cards.empty)
		_art(path, portrait.grow(-float(card.portrait_inset)), true)
		if not empty and not rival_mode and not artwork.companions.has(str(entries[index].id)):
			_card_text(settings.portrait_note, portrait.position + Vector2(0, portrait.size.y * .8), portrait.size.x, int(card.caption_font), Color("ead2a0"))
		var name = settings.empty_name if empty else str(entries[index].name)
		var title = "" if empty else (str(entries[index].shop) + " · " + str(entries[index].axis) if rival_mode else str(entries[index].title))
		var description = settings.empty_description if empty else str(entries[index].change if rival_mode else entries[index].description)
		_card_text(name, Vector2(rect.position.x+pad,rect.position.y+rect.size.y*.55), width-pad*2, int(card.name_font), tint)
		_card_text(title, Vector2(rect.position.x+pad,rect.position.y+rect.size.y*.64), width-pad*2, int(card.detail_font), Color("ead2a0"))
		_card_text(description, Vector2(rect.position.x+pad,rect.position.y+rect.size.y*.71), width-pad*2, int(card.detail_font), Color("eee5d2"))
		if rival_mode and not empty:
			_card_text(str(entries[index].pitch), Vector2(rect.position.x+pad,rect.position.y+rect.size.y*float(card.pitch_y_ratio)), width-pad*2, int(card.caption_font), Color("bbc9c0"))
