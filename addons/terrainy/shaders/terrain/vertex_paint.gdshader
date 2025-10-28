shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast   : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;


vec3 adjust_color(vec3 color) {
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;

	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(gray), color, saturation);

	return clamp(color, 0.0, 1.0);
}

void fragment() {
	vec3 vertex_color = COLOR.rgb;

	if (vertex_color == vec3(0.0)) {
		vertex_color = vec3(1.0); // White color by default
	}

	ALBEDO = adjust_color(vertex_color);
	ALPHA = 1.0;
}