shader_type spatial;

render_mode depth_draw_always, cull_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms Surface_Details;
uniform float uv_scale: hint_range(0.0, 100.0, 0.1) = 1.0;
uniform bool uv_triplanar = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float metallic: hint_range(0.0, 1.0) = 0.6;
uniform float specular : hint_range(0.0, 1.0, 0.01);

group_uniforms Water_Colors;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.66, 1.0);
uniform vec3 deep_color : source_color = vec3(0.0, 0.25, 0.45);
uniform float depth_fade_distance : hint_range(0.0, 10.0) = 1.0;
uniform float absorbance : hint_range(0.0, 10.0) = 2.0;

group_uniforms Normals;
uniform sampler2D water_normal_noise: hint_default_white;
uniform float normal_strength: hint_range(0.0, 1.0, 0.01) = 0.5;

group_uniforms Foam;
uniform float foam_amount : hint_range(0.0, 2.0) = 0.2;
uniform vec3 foam_color : source_color = vec3(1);

group_uniforms Waves;
uniform float wave_time_scale: hint_range(0.0, 10.0, 0.1) = 1.0;

varying vec3 uv_world_pos;

vec3 screen(vec3 base, vec3 blend){
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

void vertex() {
	uv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 base_uv = UV;
	vec2 screen_uv = SCREEN_UV;

	if (uv_triplanar) {
		base_uv = uv_world_pos.xz;
	}

	base_uv.x += sin(TIME * wave_time_scale + (base_uv.x + base_uv.y) * 25.0) * 0.01;
	base_uv.y += cos(TIME * wave_time_scale + (base_uv.x - base_uv.y) * 25.0) * 0.01;
	screen_uv.x += sin(TIME * wave_time_scale + (screen_uv.x + screen_uv.y) * 25.0) * 0.01;
	screen_uv.y += cos(TIME * wave_time_scale + (screen_uv.x - screen_uv.y) * 25.0) * 0.01;

	/// DEPTH TEXTURE MANIPULATION ///
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;

  	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);

	float depth_texture_y = world.y / world.w;
	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float vertical_depth = vertex_y - depth_texture_y;

	// CHANGES THE COLOR OF GEOMETRY BEHIND IT AS THE WATER GETS DEEPER
	float depth_fade_blend = exp(-vertical_depth / depth_fade_distance);
	depth_fade_blend = clamp(depth_fade_blend, 0.0, 1.0);
	/// END DEPTH TEXTURE MANIPULATION ///

	// WHEN THE WATER GETS MORE SHALLOW, MORE TRANSPARENT
	float alpha_blend = -vertical_depth * absorbance;
	alpha_blend = clamp(1.0 - exp(alpha_blend), 0.0, 1.0);

	float foam_blend = clamp(1.0 - (vertical_depth / foam_amount), 0.0, 1.0);
	vec3 foam = foam_blend * foam_color;

	vec3 final_albedo = mix(deep_color, shallow_color, depth_fade_blend);
	final_albedo = screen(final_albedo, foam);

	ALBEDO = final_albedo;
	NORMAL_MAP = texture(water_normal_noise, base_uv * uv_scale).rgb;
	NORMAL *= normal_strength;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	if (FRONT_FACING) {
		ALPHA = alpha_blend;
	} else {
		ALPHA = 1.0;
	}
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
