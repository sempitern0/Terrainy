shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms General;
uniform float blend_factor : hint_range(0.1, 50.0) = 5.0;
uniform float fade_range = 5.0;
uniform float height_dirt = 5.0;
uniform float height_grass = 15.0;
uniform float height_mountain = 30.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms Dirt;
uniform sampler2D dirt_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform float dirt_blend_sharpness = 1.0;
uniform float dirt_uv_scale = 1.0;
uniform float dirt_stochastic_strength : hint_range(0.0, 1.0) = 0.3;
uniform float dirt_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0.5;

group_uniforms Grass;
uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform float grass_blend_sharpness = 1.0;
uniform float grass_uv_scale = 1.0;
uniform float grass_stochastic_strength : hint_range(0.0, 1.0) = 0.3;
uniform float grass_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0.5;

group_uniforms Mountain;
uniform sampler2D mountain_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform float mountain_blend_sharpness = 1.0;
uniform float mountain_uv_scale = 1.0;
uniform float mountain_stochastic_strength : hint_range(0.0, 1.0) = 0.3;
uniform float mountain_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0.5;


varying vec3 world_pos;
varying vec3 triplanar_normal_abs;



float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

mat2 rotate2d(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec2 stochastic_uv(vec2 uv, float strength, float max_angle) {
	vec2 tile = floor(uv);
	float angle = hash21(tile) * max_angle;
	vec2 offset = vec2(hash21(tile + 1.3), hash21(tile + 2.1)) - 0.5;
	vec2 local = fract(uv) + offset * strength;
	return rotate2d(angle) * (local - 0.5) + 0.5;
}


vec3 triplanar_rgb(
	sampler2D tex,
	vec3 pos,
	vec3 normal_abs,
	float blend_sharpness,
	float uv_scale,
	float strength,
	float max_angle
) {
	vec2 uv_xy = stochastic_uv(pos.xy * uv_scale, strength, max_angle);
	vec2 uv_xz = stochastic_uv(pos.xz * uv_scale, strength, max_angle);
	vec2 uv_yz = stochastic_uv(pos.yz * uv_scale, strength, max_angle);

	vec3 color_xy = texture(tex, uv_xy).rgb;
	vec3 color_xz = texture(tex, uv_xz).rgb;
	vec3 color_yz = texture(tex, uv_yz).rgb;

	vec3 weights = pow(normal_abs, vec3(blend_sharpness));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);

	return color_yz * weights.x + color_xz * weights.y + color_xy * weights.z;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	triplanar_normal_abs = abs(NORMAL);
}


void fragment() {
	float height = world_pos.y;

	float blend_dirt = 1.0 - smoothstep(height_dirt, height_dirt + fade_range, height);
	float blend_grass = smoothstep(height_dirt, height_grass, height) * (1.0 - smoothstep(height_grass, height_mountain, height));
	float blend_mountain = smoothstep(height_grass, height_mountain, height);

	blend_dirt = pow(blend_dirt, dirt_blend_sharpness);
	blend_grass = pow(blend_grass, grass_blend_sharpness);
	blend_mountain = pow(blend_mountain, mountain_blend_sharpness);

	float total = blend_dirt + blend_grass + blend_mountain + 0.0001;
	blend_dirt /= total;
	blend_grass /= total;
	blend_mountain /= total;

	vec3 albedo_dirt = triplanar_rgb(dirt_albedo, world_pos, triplanar_normal_abs, blend_factor, dirt_uv_scale, dirt_stochastic_strength, dirt_stochastic_rotation_max_angle);
	vec3 albedo_grass = triplanar_rgb(grass_albedo, world_pos, triplanar_normal_abs, blend_factor, grass_uv_scale, grass_stochastic_strength, grass_stochastic_rotation_max_angle);
	vec3 albedo_mountain = triplanar_rgb(mountain_albedo, world_pos, triplanar_normal_abs, blend_factor, mountain_uv_scale, mountain_stochastic_strength, mountain_stochastic_rotation_max_angle);

	ALBEDO = albedo_dirt * blend_dirt + albedo_grass * blend_grass + albedo_mountain * blend_mountain;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
