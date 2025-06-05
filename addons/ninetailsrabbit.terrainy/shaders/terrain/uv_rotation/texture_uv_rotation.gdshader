shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D albedo_seam : source_color, repeat_enable, filter_linear_mipmap;

uniform float uv_scale = 1.0;
uniform vec2 pivot_point = vec2(0.500000, 0.500000);

// Noise type should be "cellular", fractal type "none" and return type "cell_value"
uniform sampler2D rotation_noise : source_color;

// This Noise type should be exactly the same as the rotation noise except for return type as "distance2sub"
// When changing any parameter of the rotation noise, the seam mending noise must be updated too
// The color ramp needs to be from white(left) and black(right) so the seams can be hidden.
uniform sampler2D seam_mending_noise : source_color;


void fragment() {
	vec2 albedo_uv = UV * vec2(uv_scale);

	float rotation_degrees;
	
	// Remap noise value [0, 1] to degrees [0, 360]
	float input_min_value = 0.00000;
	float input_max_value = 1.00000;
	float output_min_value = 0.00000;
	float output_max_value = 360.00000;
	{
		float __input_range = input_max_value - input_min_value;
		float __output_range = output_max_value - output_min_value;
		rotation_degrees = output_min_value + __output_range * ((texture(rotation_noise, UV).x - input_min_value) / __input_range);
	}

	vec2 final_albedo;
	
// Expression:7
	final_albedo = vec2(0.0, 0.0);
	{
		albedo_uv -= pivot_point;
		float rotation_radians = radians(rotation_degrees);
		float c = cos(rotation_radians);
		float s = sin(rotation_radians);
		
		final_albedo.x = albedo_uv.x * c + albedo_uv.y * s;
		final_albedo.y = albedo_uv.y * c - albedo_uv.x * s;
		
		final_albedo += pivot_point;
	}

	ALBEDO =  mix(vec3(texture(albedo_seam, final_albedo).xyz), vec3(texture(albedo_texture, albedo_uv).xyz), vec3(texture(seam_mending_noise, UV).xyz));
}
