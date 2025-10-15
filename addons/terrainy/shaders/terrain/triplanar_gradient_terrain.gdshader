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

group_uniforms Grass;
uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform float grass_blend_sharpness = 1.0;
uniform float grass_uv_scale = 1.0;

group_uniforms Mountain;
uniform sampler2D mountain_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform float mountain_blend_sharpness = 1.0;
uniform float mountain_uv_scale = 1.0;


varying vec3 world_pos;
varying vec3 triplanar_normal_abs;


float fast_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453);
}

vec2 simple_stochastic(vec2 uv, float strength) {
	vec2 tile = floor(uv);
	vec2 offset = vec2(fast_hash(tile), fast_hash(tile + 3.17)) - 0.5;
	return uv + offset * strength;
}

vec3 triplanar_rgb_lite(sampler2D tex, vec3 pos, vec3 normal_abs, float blend_sharpness) {
	float t = clamp(pos.y * 0.05 + 0.5, 0.0, 1.0);
	return textureLod(tex, vec2(t, 0.5), 1.5).rgb;
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

	vec3 albedo_dirt = triplanar_rgb_lite(dirt_albedo, world_pos, triplanar_normal_abs, blend_factor);
	vec3 albedo_grass = triplanar_rgb_lite(grass_albedo, world_pos, triplanar_normal_abs, blend_factor);
	vec3 albedo_mountain = triplanar_rgb_lite(mountain_albedo, world_pos, triplanar_normal_abs, blend_factor);

	ALBEDO = albedo_dirt * blend_dirt + albedo_grass * blend_grass + albedo_mountain * blend_mountain;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
