shader_type canvas_item;

// Source-space silhouette, independent of wood brightness. The dark delivery
// has a nearly opaque brown exterior, so colour keying erases wood detail.
uniform vec4 edges;

void fragment() {
	float top = mix(edges.x, edges.y, UV.x);
	float bottom = mix(edges.z, edges.w, UV.x);
	COLOR.a *= smoothstep(top, top + 0.006, UV.y)
		* (1.0 - smoothstep(bottom - 0.006, bottom, UV.y));
}
