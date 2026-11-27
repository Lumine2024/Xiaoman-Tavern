shader_type canvas_item;
uniform float zoom = 1.0;
uniform vec2 source_point = vec2(0.5);
uniform vec2 current_point = vec2(0.5);
uniform float edge_feather = 0.04;
varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec2 sample_uv = (UV - current_point) / max(zoom, 0.001) + source_point;
	COLOR = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))) * vertex_modulate;
	vec2 edge = min(sample_uv, vec2(1.0) - sample_uv);
	COLOR.a *= smoothstep(0.0, edge_feather, min(edge.x, edge.y));
}
