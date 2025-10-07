shader_type spatial;

render_mode depth_draw_always, cull_disabled;

uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_nearest, repeat_disable;

group_uniforms Surface_details;
uniform float uv_scale = 1.0;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float roughness: hint_range(0.0, 1.0, 0.1) = 0.2;
uniform float shallow_roughness_boost: hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float shallow_roughness_depth_start: hint_range(0.0, 5.0, 0.1) = 0.0;
uniform float shallow_roughness_depth_end: hint_range(0.0, 10.0, 0.1) = 0.0;

group_uniforms Water_Deep;
uniform vec4 base_color: source_color;
uniform vec4 deep_color: source_color;
uniform float depth_distance: hint_range(0.0, 20.0, 0.1) = 4.0;
uniform float beers_law: hint_range(0.0, 20.0, 0.1) = 12.0;
uniform float water_transparency: hint_range(0.0, 1.0, 0.01) = 0.05;

group_uniforms Refraction;
uniform float refraction_strength: hint_range(0.0, 8.0, 0.001) = 0.12;
uniform float underwater_fresnel_power: hint_range(0.0, 10.0, 0.1) = 0.5; 

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
uniform float time_factor = 4.0;
uniform float noise_zoom = 2.0;
uniform float noise_amplitude = 0.0;
// Each wave is defined by a vec4: direction (x,y), amplitude, frequency
uniform vec4 wave_1 = vec4(0.3, 4.0, 0.2, 0.6);
uniform vec4 wave_2 = vec4(-0.26, -0.19, 0.01, 0.47);
uniform vec4 wave_3 = vec4(-7.67, 5.63, 0.1, 0.38);
uniform vec4 wave_4 = vec4(-0.42, -1.63, 0.1, 0.28);
uniform vec4 wave_5 = vec4(1.66, 0.07, 0.15, 1.81);
uniform vec4 wave_6 = vec4(1.20, 1.14, 0.01, 0.33);
uniform vec4 wave_7 = vec4(-1.6, 7.3, 0.11, 0.73);
uniform vec4 wave_8 = vec4(-0.42, -1.63, 0.15, 1.52);

varying vec3 world_position;
varying mat4 inv_mvp;
varying mat3 tbn_matrix;
varying float height;


float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// Function to calculate edge depth
float edge(float depth) {
    depth = 2.0 * depth - 1.0;
	
    return near * far / (far - depth * (near - far));
}

// Function to calculate dynamic amplitude based on position and time
float dynamic_amplitude(vec2 pos, float time) {
    return 1.0 + 0.5 * sin(time + length(pos) * 0.1);
}

// Hash function for noise generation
float hash(vec2 p) {
    return fract(sin(dot(p * 17.17, vec2(14.91, 67.31))) * 4791.9511);
}

// 2D noise function
float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    vec2 a = vec2(1.0, 0.0);
    return mix(mix(hash(p + a.yy), hash(p + a.xy), f.x),
               mix(hash(p + a.yx), hash(p + a.xx), f.x), f.y);
}

// Fractional Brownian Motion (fBM) function for generating complex noise
float fbm(vec2 x) {
    float _height = 0.0;
    float amplitude = 0.5;
    float frequency = 3.0;
	
    for (int i = 0; i < 6; i++) {
        _height += noise(x * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
	
    return _height;
}

struct WaveResult {
    vec3 displacement;
    vec3 tangent;
    vec3 binormal;
    vec3 normal;
};

// Gerstner wave function to calculate wave displacement and normals
WaveResult gerstner_wave(vec4 params, vec2 pos, float time) {
    float steepness = params.z * dynamic_amplitude(pos, time);
    float wavelength = params.w;
    float k = TAU / wavelength;
    float c = sqrt(9.81 / k);
    vec2 d = normalize(params.xy);
    float f = k * (dot(d, pos.xy) - c * time);
    float a = steepness / k;

    vec3 displacement = vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));

    vec3 tangent = vec3(1.0 - d.x * d.x * steepness * sin(f), steepness * cos(f), -d.x * d.y * steepness * sin(f));
    vec3 binormal = vec3(-d.x * d.y * steepness * sin(f), steepness * cos(f), 1.0 - d.y * d.y * steepness * sin(f));
    vec3 normal = normalize(cross(tangent, binormal));

    return WaveResult(displacement, tangent, binormal, normal);
}

WaveResult wave(vec2 pos, float time) {
    WaveResult waveResult;
    waveResult.displacement = vec3(0.0);
    waveResult.tangent = vec3(1.0, 0.0, 0.0);
    waveResult.binormal = vec3(0.0, 0.0, 1.0);
    waveResult.normal = vec3(0.0, 1.0, 0.0);

    WaveResult wr;
    wr = gerstner_wave(wave_1, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_2, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_3, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_4, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_5, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_6, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_7, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    wr = gerstner_wave(wave_8, pos, time);
    waveResult.displacement += wr.displacement;
    waveResult.tangent += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal += wr.normal;

    // Add noise to the wave displacement for more natural look
    waveResult.displacement.y += fbm(pos.xy * (noise_zoom / 50.0)) * noise_amplitude;

    return waveResult;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    inv_mvp = inverse(PROJECTION_MATRIX * MODELVIEW_MATRIX);

	float time = TIME / time_factor;
	// Calculate wave displacement and normals
	WaveResult waveResult = wave(VERTEX.xz, time);
	// Apply wave displacement to the vertex position
	VERTEX += waveResult.displacement;
	// Store the height of the wave displacement
	height = waveResult.displacement.y;

	vec3 n = normalize((MODELVIEW_MATRIX * vec4(waveResult.normal, 0.0)).xyz);
	vec3 t = normalize((MODELVIEW_MATRIX * vec4(waveResult.tangent.xyz, 0.0)).xyz);
	vec3 b = normalize((MODELVIEW_MATRIX * vec4((cross(waveResult.normal, waveResult.tangent.xyz)), 0.0)).xyz);
	
	// Create TBN matrix for normal mapping
	tbn_matrix = mat3(t, b, n);

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
	
	float current_depth_diff = clamp((vertex_y - depth_texture_y), 0.0, 100.0);
	float shallow_blend = smoothstep(shallow_roughness_depth_start, shallow_roughness_depth_end, current_depth_diff);
	float final_roughness = mix(roughness + shallow_roughness_boost, roughness, shallow_blend);

	vec3 camera_world_position = CAMERA_POSITION_WORLD;
	float water_level_y = world_position.y; 
	bool is_camera_underwater = camera_world_position.y < water_level_y;
	
	if (is_camera_underwater) {
		float current_fragment_world_depth_from_camera = length(CAMERA_POSITION_WORLD.xyz - world_position);
	 	float absorption_blend = clamp(current_fragment_world_depth_from_camera / depth_distance, 0.0, 1.0);
       
		 absorption_blend = exp(-absorption_blend * beers_law);
		 float underwater_fresnel_effect = fresnel(underwater_fresnel_power, normalmap, VIEW); // Using the world-space normal and custom power
		
		 final_color = mix(deep_color.rgb * absorption_blend, refraction_texture, water_transparency + underwater_fresnel_effect);
	}
	
	if (use_edge_foam) {
		float foam_alpha = clamp(depth_color_adj.r * (1.0 - edge_fade), 0.0, 1.0);
		ALBEDO = mix(final_color, depth_color_adj, foam_alpha);
	} else {
		ALBEDO =  final_color;
	}
	
	ALPHA = base_color.a;
	NORMAL *= normal_strength;
	NORMAL_MAP = normalmap;
	METALLIC = metallic;
	ROUGHNESS = final_roughness * (1.0 - basic_fresnel);
}