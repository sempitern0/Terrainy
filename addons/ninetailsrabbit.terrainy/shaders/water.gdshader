shader_type spatial;

render_mode depth_draw_always, cull_disabled;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_nearest, repeat_disable;

uniform float uv_scale = 1.0;
uniform float roughness: hint_range(0.0, 1.0, 0.1) = 0.2;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Water_Deep;
uniform vec4 base_color: source_color;
uniform vec4 deep_color: source_color;
uniform float depth_distance: hint_range(0.0, 20.0, 0.1) = 4.0;
uniform float beers_law: hint_range(0.0, 20.0, 0.1) = 12.0;
uniform float water_transparency: hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float absorbance : hint_range(0.0, 10.0) = 2.0;

group_uniforms Refraction;
uniform float refraction_strength: hint_range(0.0, 8.0, 0.001) = 0.12;

group_uniforms Edge_Detection;
uniform bool use_edge_foam = true;
uniform float near = 7.0;
uniform float far = 1000.0;
uniform float edge_texture_scale = 3.5;
uniform float edge_texture_offset = 1.0;
uniform float edge_texture_speed = 0.1;
uniform float edge_foam_intensity = 2.0;
uniform float edge_fade_start = -3.0;
uniform float edge_fade_end = 6.6;
uniform sampler2D edge_foam_texture;

group_uniforms Waves;
uniform float normal_strength: hint_range(0.0, 1.0, 0.01) = 0.5;
uniform sampler2D normalmap_a: hint_normal;
uniform sampler2D normalmap_b: hint_normal;
uniform float normalmap_a_strength: hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float normalmap_b_strength: hint_range(0.0, 1.0, 0.01) = 0.4;
uniform vec2 wave_direction = vec2(0.1, 0.1);
uniform float wave_strength = 0.05;

varying vec3 world_position;
varying mat4 inv_mvp;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// Function to calculate edge depth
float edge(float depth) {
    depth = 2.0 * depth - 1.0;
	
    return near * far / (far - depth * (near - far));
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    //inv_mvp = inverse(PROJECTION_MATRIX * MODELVIEW_MATRIX);
	
}

void fragment() {
	float basic_fresnel = fresnel(3.0, NORMAL, VIEW);
	vec2 uv = UV * uv_scale;
	vec2 uv_movement = wave_direction * TIME * wave_strength;
	
	vec3 normalmap = texture(normalmap_a, uv + uv_movement).rgb * normalmap_a_strength;
	normalmap += texture(normalmap_b, uv - uv_movement).rgb * normalmap_b_strength;
	
	vec3 ref_normalmap = normalmap * 2.0 - (normalmap_a_strength + normalmap_b_strength);
	vec3 ref_normal = mix(NORMAL, TANGENT * ref_normalmap + BINORMAL * ref_normalmap + NORMAL * ref_normalmap, 1.0);
	vec2 ref_ofs = SCREEN_UV - ref_normal.xy * refraction_strength;
	
    float screen_depth_clean = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
    float screen_depth = textureLod(DEPTH_TEXTURE, ref_ofs, 0.0).r;
	vec3 screen = textureLod(SCREEN_TEXTURE, ref_ofs, 0.0).rgb;
	
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, screen_depth);
	vec3 ndc_clean = vec3(SCREEN_UV * 2.0 - 1.0, screen_depth_clean);
	
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z + VERTEX.z; // Check if object is in front of plane
	
	vec4 world;
	vec3 refraction_texture;
	
	if (linear_depth < 0.00001) {
		world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc_clean, 1.0);
		refraction_texture = textureLod(SCREEN_TEXTURE, SCREEN_UV, ROUGHNESS * 2.0).rgb;
	} else {
		world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		refraction_texture = textureLod(SCREEN_TEXTURE, ref_ofs, ROUGHNESS * 2.0).rgb;
	}
	
	float depth_texture_y = world.y / world.w;
	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float depth_blend = clamp((vertex_y - depth_texture_y) / depth_distance, 0.0, 1.0);
	depth_blend = exp(-depth_blend * beers_law);
	
	vec3 depth_color = mix(deep_color, base_color, depth_blend).rgb;
	//vec3 refraction_texture = 
	vec3 final_color = mix(depth_color, refraction_texture, water_transparency * depth_blend);
	
	float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos = edge(FRAGCOORD.z);
    float z_dif = z_depth - z_pos;
	
	// Calculate depth difference for edge detection
	vec2 edge_uv = world_position.xz * edge_texture_scale + edge_texture_offset + TIME * edge_texture_speed;
    float edge_fade = smoothstep(edge_fade_start, edge_fade_end, z_dif);
    vec3 depth_color_adj = mix(texture(edge_foam_texture, edge_uv).rgb * edge_foam_intensity, final_color, edge_fade);
	
	if (use_edge_foam) {
		ALBEDO =  final_color + depth_color_adj; // mix(final_color, screen, depth_blend * (1.0 - basic_fresnel)); 
	} else {
		ALBEDO =  final_color;
	}

	ALPHA = base_color.a;
	NORMAL *= normal_strength;
	NORMAL_MAP = normalmap;
	ROUGHNESS = roughness * (1.0 - basic_fresnel);
	METALLIC = metallic;
}