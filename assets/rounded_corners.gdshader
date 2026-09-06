shader_type canvas_item;

// Rounded-corner mask for album cover thumbnails.
// Rounds the corners of the control to `corner_radius` pixels.

uniform float corner_radius : hint_range(0.0, 200.0) = 12.0;
uniform vec2 control_size = vec2(1.0, 1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 size = control_size;
	vec2 p = local_pos;
	float r = min(corner_radius, min(size.x, size.y) * 0.5);

	// Signed distance to the rounded rectangle boundary.
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - r);
	float dist = length(max(q, vec2(0.0))) - r;

	float alpha = 1.0 - smoothstep(0.0, 1.0, dist);
	COLOR.a *= alpha;
}
