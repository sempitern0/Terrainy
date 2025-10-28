shader_type spatial;

uniform sampler2D red_channel_texture; // Canal rojo
uniform float uv_red_channel_texture : hint_range(0.1, 10.0) = 1.0;

uniform sampler2D green_channel_texture; // Canal verde
uniform float uv_green_channel_texture : hint_range(0.1, 10.0) = 1.0;

uniform sampler2D blue_channel_texture; // Canal azul
uniform float uv_blue_channel_texture : hint_range(0.1, 10.0) = 1.0;

uniform sampler2D alpha_channel_texture; // Canal alfa
uniform float uv_alpha_channel_texture : hint_range(0.1, 10.0) = 1.0;

uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

vec3 adjust_color(vec3 color) {
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;

	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(gray), color, saturation);

	return clamp(color, 0.0, 1.0);
}

void fragment() {
	vec4 vertex_color = COLOR;

	float total = vertex_color.r + vertex_color.g + vertex_color.b + vertex_color.a;
	
	if (total < 0.001) {
		vertex_color = vec4(1.0, 0.0, 0.0, 0.0);
	}

	vertex_color /= max(total, 1.0);

	vec2 uv_r = UV * uv_red_channel_texture;
	vec2 uv_g = UV * uv_green_channel_texture;
	vec2 uv_b = UV * uv_blue_channel_texture;
	vec2 uv_a = UV * uv_alpha_channel_texture;

	vec3 col_r = texture(red_channel_texture, uv_r).rgb;
	vec3 col_g = texture(green_channel_texture, uv_g).rgb;
	vec3 col_b = texture(blue_channel_texture, uv_b).rgb;
	vec3 col_a = texture(alpha_channel_texture, uv_a).rgb;

	vec3 blended =
		col_r * vertex_color.r +
		col_g * vertex_color.g +
		col_b * vertex_color.b +
		col_a * vertex_color.a;

	ALBEDO = adjust_color(blended);
}
