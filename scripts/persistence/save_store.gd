extends RefCounted
## Validate before touching live state. Replace through a same-directory temp file.
var last_error = ""
var loaded_backup = false
var obsolete_check: Callable
var removed_obsolete = false

func _read(path: String, decode: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	if obsolete_check.is_valid() and obsolete_check.call(parser.data):
		file.close()
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK: removed_obsolete = true
		return {}
	return decode.call(parser.data)

func load_snapshot(path: String, decode: Callable) -> Dictionary:
	last_error = ""
	loaded_backup = false
	removed_obsolete = false
	var snapshot = _read(path, decode)
	if not snapshot.is_empty():
		return snapshot
	snapshot = _read(path + ".bak", decode)
	if not snapshot.is_empty():
		loaded_backup = true
		return snapshot
	last_error = "旧版经营存档已删除，请新建进度。" if removed_obsolete else "存档及备份不可用，未修改当前进度。"
	return {}

func write_snapshot(path: String, snapshot: Dictionary, decode: Callable) -> bool:
	last_error = ""
	if decode.call(snapshot).is_empty():
		last_error = "当前进度校验失败，未覆盖存档。"
		return false
	var absolute = ProjectSettings.globalize_path(path)
	var temporary = absolute + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "无法创建临时存档：" + path
		return false
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or _read(temporary, decode).is_empty():
		last_error = "临时存档写入失败，原存档已保留。"
		return false
	# Never replace a healthy backup with an unreadable primary file.
	if not _read(path, decode).is_empty():
		if DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
			last_error = "无法更新存档备份，原存档已保留。"
			return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		last_error = "无法替换存档，原存档及备份已保留。"
		return false
	return true
