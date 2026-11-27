extends RefCounted
## Shared nine-slice skins; text, hit areas and callbacks stay on native buttons.

static func apply(target: Theme, config: Dictionary) -> void:
	for profile in config.profiles.values():
		for type_name in profile.theme_types:
			if not str(profile.base_type).is_empty():
				target.set_type_variation(type_name, profile.base_type)
			for state in profile.textures:
				var style = StyleBoxTexture.new()
				style.texture = load(profile.textures[state])
				if state == "focus": style.draw_center = bool(profile.get("focus_draw_center", true))
				for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
					style.set_texture_margin(side, float(profile.texture_margins[side]))
					style.set_content_margin(side, float(profile.content_margins[side]))
				target.set_stylebox(state, type_name, style)

static func panel(config: Dictionary) -> StyleBoxTexture:
	var style = StyleBoxTexture.new()
	style.texture = load(config.texture)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, float(config.texture_margins[side]))
		style.set_content_margin(side, float(config.content_margins[side]))
	return style
