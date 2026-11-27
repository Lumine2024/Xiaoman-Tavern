extends SceneTree
## Export the existing flat UI backgrounds, without text, as editable PNGs.
## Explicitly run this tool only when regenerating the original templates:
## it overwrites every configured button skin. Requires a graphical renderer.

func _initialize() -> void:
	call_deferred("export_templates")

func export_templates() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Button PNG export needs a graphical renderer.")
		quit(1)
		return
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Supply button_skins.json and button_skin_templates.json after --.")
		quit(1)
		return
	var skins = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var source = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var exports: Array = []
	var exported_paths: Dictionary = {}
	for profile in skins.profiles.values():
		for state in profile.textures:
			var target: String = profile.textures[state]
			if exported_paths.has(target): continue
			exported_paths[target] = true
			var viewport = SubViewport.new()
			viewport.size = Vector2i(profile.template_size[0], profile.template_size[1])
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var panel = Panel.new()
			panel.size = viewport.size
			var style = StyleBoxFlat.new()
			style.bg_color = Color("#" + source.states[state].fill)
			style.border_color = Color("#" + source.states[state].border)
			style.draw_center = source.states[state].draw_center
			style.set_border_width_all(int(source.border_width))
			style.set_corner_radius_all(int(source.corner_radius))
			panel.add_theme_stylebox_override("panel", style)
			viewport.add_child(panel)
			exports.append({"viewport":viewport, "path":target})
	await process_frame
	await RenderingServer.frame_post_draw
	for item in exports:
		var path = ProjectSettings.globalize_path(item.path)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var result = item.viewport.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Could not export " + path)
			quit(1)
			return
	print("Exported %d button background PNGs (no text)." % exports.size())
	quit()
