extends RefCounted
## Notebook UI state is separate from the economic order checkpoint.
var menu
var game
var settings: Dictionary
var section: String
var selected: Dictionary = {}
var query = ""
var favorites_only = false
var page_index = 0
var last_deleted: Array = []
var feedback = ""
var body: VBoxContainer
var list: VBoxContainer
var scroll: ScrollContainer
var count_label: Label
var status_label: Label
var page_label: Label
var previous: Button
var next: Button
var undo: Button
var actions: Dictionary = {}
var tabs: Dictionary = {}

func _init(host) -> void:
	menu = host
	game = host.game
	settings = game.interface.journal
	section = settings.default_section

func reset() -> void:
	selected.clear()
	query = ""
	favorites_only = false
	page_index = 0
	last_deleted.clear()
	feedback = ""

func build(parent: Node, requested: String) -> void:
	if requested in settings.sections: section = requested
	tabs.clear()
	var row = game._row(parent)
	var group = ButtonGroup.new()
	for id in settings.sections:
		var tab = game._button(row, settings.sections[id], change_section.bind(id))
		tab.name = "JournalTab_" + id
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = id == section
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs[id] = tab
	body = VBoxContainer.new()
	body.name = "JournalBody"
	body.custom_minimum_size.y = float(settings.body_height)
	body.add_theme_constant_override("separation", 8)
	parent.add_child(body)
	_draw_section()

func change_section(id: String) -> void:
	section = id
	for key in tabs: tabs[key].set_pressed_no_signal(key == id)
	_draw_section()

func _draw_section() -> void:
	game._clear(body)
	if section == "messages":
		_draw_messages()
		return
	var text = RichTextLabel.new()
	text.name = "JournalSectionText"
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.bbcode_enabled = false
	text.text = menu._journal_text(section)
	if text.text.is_empty(): text.text = settings.none
	text.add_theme_color_override("default_color", game.TEXT)
	body.add_child(text)

func _draw_messages() -> void:
	var filters = game._row(body)
	var search = LineEdit.new()
	search.name = "JournalSearch"
	search.placeholder_text = settings.search
	search.text = query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	search.text_changed.connect(func(value):
		query = value
		page_index = 0
		refresh(true))
	var favorites = CheckButton.new()
	favorites.name = "JournalFavoritesOnly"
	favorites.text = settings.favorites_only
	favorites.button_pressed = favorites_only
	filters.add_child(favorites)
	favorites.toggled.connect(func(value):
		favorites_only = value
		page_index = 0
		refresh(true))
	var bulk = game._row(body)
	actions.clear()
	for id in ["select_all", "select_none", "favorite_selected", "unfavorite_selected", "delete_selected", "clean"]:
		var button = game._button(bulk, settings[id], act.bind(id))
		button.name = "JournalAction_" + id
		button.add_theme_font_size_override("font_size", 15)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions[id] = button
	actions.clean.tooltip_text = settings.clean_hint
	var status = game._row(body)
	count_label = game._label(status, "", 15, game.MUTED)
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo = game._button(status, settings.undo, undo_delete)
	undo.name = "JournalUndo"
	undo.add_theme_font_size_override("font_size", 15)
	scroll = ScrollContainer.new()
	scroll.name = "JournalMessagesScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var pager = game._row(body)
	previous = game._button(pager, settings.previous, turn_page.bind(-1))
	page_label = game._label(pager, "", 15, game.MUTED)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next = game._button(pager, settings.next, turn_page.bind(1))
	status_label = game._label(body, feedback, 14, game.MINT)
	refresh()

func filtered() -> Array:
	var result = game.rumors.filter(func(note): return (not favorites_only or note in game.journal_favorites) and (query.strip_edges().is_empty() or (note + "\n" + game._journal_speaker_text(note)).to_lower().contains(query.strip_edges().to_lower())))
	result.reverse()
	return result

func refresh(reset_scroll = false) -> void:
	if not is_instance_valid(list): return
	for note in selected.keys():
		if note not in game.rumors: selected.erase(note)
	var offset = 0 if reset_scroll else scroll.scroll_vertical
	game._clear(list)
	var notes = filtered()
	var pages = maxi(1, ceili(float(notes.size()) / int(settings.page_size)))
	page_index = clampi(page_index, 0, pages - 1)
	for index in range(page_index * int(settings.page_size), mini(notes.size(), (page_index + 1) * int(settings.page_size))):
		var note: String = notes[index]
		var row = game._row(list)
		row.set_meta("note", note)
		var check = CheckBox.new()
		check.name = "JournalSelect"
		check.button_pressed = selected.has(note)
		row.add_child(check)
		check.toggled.connect(func(value):
			if value: selected[note] = true
			else: selected.erase(note)
			_update_actions())
		var text_column = VBoxContainer.new()
		text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_column)
		var speaker = game._label(text_column, game._journal_speaker_text(note), 14, game.MINT)
		speaker.name = "JournalMessageSpeaker"
		var label = game._label(text_column, note, 17)
		label.name = "JournalMessageText"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var star = game._button(row, settings.favorited if note in game.journal_favorites else settings.favorite, toggle_favorite.bind(note))
		star.name = "JournalFavorite"
		star.add_theme_font_size_override("font_size", 15)
	if notes.is_empty(): game._label(list, settings.none if game.rumors.is_empty() else settings.empty_search, 17, game.MUTED)
	previous.disabled = page_index == 0
	next.disabled = page_index + 1 == pages
	page_label.text = settings.page.format({"page": page_index + 1, "pages": pages})
	status_label.text = feedback
	_update_actions()
	scroll.set_deferred("scroll_vertical", offset)

func _update_actions() -> void:
	count_label.text = settings.count.format({"total": game.rumors.size(), "filtered": filtered().size(), "selected": selected.size()})
	for id in ["select_none", "favorite_selected", "unfavorite_selected", "delete_selected"]: actions[id].disabled = selected.is_empty()
	actions.select_all.disabled = filtered().is_empty()
	actions.clean.disabled = filtered().all(func(note): return note in game.journal_favorites)
	undo.disabled = last_deleted.is_empty()

func turn_page(delta: int) -> void:
	page_index += delta
	refresh(true)

func toggle_favorite(note: String) -> void:
	if note in game.journal_favorites: game.journal_favorites.erase(note)
	else: game.journal_favorites.append(note)
	_commit(settings.saved)

func act(id: String) -> void:
	match id:
		"select_all":
			for note in filtered(): selected[note] = true
			refresh()
		"select_none":
			selected.clear()
			refresh()
		"favorite_selected":
			for note in selected:
				if note not in game.journal_favorites: game.journal_favorites.append(note)
			_commit(settings.saved)
		"unfavorite_selected":
			for note in selected: game.journal_favorites.erase(note)
			_commit(settings.saved)
		"delete_selected": delete_notes(selected.keys())
		"clean": delete_notes(filtered().filter(func(note): return note not in game.journal_favorites))

func delete_notes(notes: Array) -> void:
	if notes.is_empty(): return
	last_deleted.clear()
	for index in game.rumors.size():
		var note = game.rumors[index]
		if note in notes: last_deleted.append({"text": note, "index": index, "favorite": note in game.journal_favorites, "speakers": game.journal_speakers.get(note, []).duplicate()})
	for entry in last_deleted:
		game.rumors.erase(entry.text)
		game.journal_favorites.erase(entry.text)
		game.journal_speakers.erase(entry.text)
		selected.erase(entry.text)
	_commit(settings.deleted.format({"count": last_deleted.size()}))

func undo_delete() -> void:
	var count = last_deleted.size()
	for entry in last_deleted:
		if entry.text not in game.rumors: game.rumors.insert(mini(int(entry.index), game.rumors.size()), entry.text)
		if entry.favorite and entry.text not in game.journal_favorites: game.journal_favorites.append(entry.text)
		if not game.journal_speakers.has(entry.text): game.journal_speakers[entry.text] = []
		for id in entry.speakers:
			if id not in game.journal_speakers[entry.text]: game.journal_speakers[entry.text].append(id)
	last_deleted.clear()
	_commit(settings.restored.format({"count": count}))

func _commit(message: String) -> void:
	feedback = message if game._persist_journal() else settings.save_failed
	refresh()
