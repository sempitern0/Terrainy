shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D main_texture : source_color;
uniform float main_uv_scale = 1.0;
uniform sampler2D secondary_texture : source_color;
uniform float secondary_uv_scale = 1.0;
uniform sampler2D blend_noise : source_color;

// Helper function to unpack a normal from 0-1 range (texture) to -1 to 1 range (vector).
vec3 unpack_normal(vec3 packed_normal) {
    return packed_normal * 2.0 - 1.0;
}

void fragment() {
	vec2 main_texture_uv_scale = UV * vec2(main_uv_scale);
	vec4 main_albedo = texture(main_texture, main_texture_uv_scale);

	vec2 secondary_texture_uv_scale = UV * vec2(secondary_uv_scale);
	vec4 secondary_albedo = texture(secondary_texture, secondary_texture_uv_scale);

	vec4 blend_noise_texture = texture(blend_noise, UV);
	
	vec3 final_albedo = mix(vec3(main_albedo.xyz), vec3(secondary_albedo.xyz), vec3(blend_noise_texture.xyz));
	
	// Makes the final texture uniform decomposing & composing the rgb channels
	vec3 albedo_rgb_to_hsv;

	{
		vec3 c = final_albedo;
		vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
		vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
		vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
		float d = q.x - min(q.w, q.y);
		float e = 1.0e-10;
		
		albedo_rgb_to_hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
	}

	// VectorDecompose
	float rgb_x = albedo_rgb_to_hsv.x;
	float rgb_y = albedo_rgb_to_hsv.y;
	float rgb_z = albedo_rgb_to_hsv.z;

	// VectorCompose:
	vec3 rgb_composed = vec3(rgb_x, rgb_y, rgb_z);
	
	vec3 albedo_hsv_to_rgb;
	{
		vec3 c = rgb_composed;
		vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
		vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
		albedo_hsv_to_rgb = c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
	}

	ALBEDO = albedo_hsv_to_rgb;
}
