// https://github.com/bsubard/Godot-3D-Procedural-Infinite-Terrain/blob/main/Chunk.gdshader
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Textures ---
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0); // General tint

// Height-based textures
uniform sampler2D texture_albedo_snow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_rock : source_color, filter_linear_mipmap, repeat_enable; // Replaces original texture_albedo
uniform sampler2D texture_albedo_sand : source_color, filter_linear_mipmap, repeat_enable;
// Slope texture (applied over the height-based textures)
uniform sampler2D texture_albedo_slope : source_color, filter_linear_mipmap, repeat_enable; // Grey/scree texture for slopes

// --- Height Blending ---
uniform float snow_start_height : hint_range(0.0, 200.0) = 80.0;
uniform float snow_full_height : hint_range(0.0, 200.0) = 100.0; // Height above which it's fully snow
uniform float sand_start_height : hint_range(-200.0, 50.0) = 2.0;  // Height below which sand starts appearing
uniform float sand_full_height : hint_range(-200.0, 50.0) = -1.0; // Height below which it's fully sand
// Note: sand_full_height is usually below sand_start_height

// --- Slope Blending ---
uniform float slope_threshold : hint_range(-1.0, 1.0) = 0.7; // World normal Y threshold
uniform float slope_blend_range : hint_range(0.0, 1.0) = 0.2;

// --- Standard PBR ---
// Roughness is removed, using default values
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
// Optional metallic textures can be added if needed

// --- UV Control ---
uniform float world_uv_scale : hint_range(0.01, 10.0) = 0.1; // Controls texture tiling size in world units

// --- Varyings ---
varying float v_world_normal_y;
varying vec3 v_world_pos; // Pass world position

void vertex() {
	// Calculate world-space position
	// VERTEX is in model space. MODEL_MATRIX converts model to world.
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Calculate world-space normal Y component
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_normal_y = world_normal.y;
}

// Helper to sample textures using world coords
vec4 sample_world(sampler2D tex, vec3 world_pos, float scale) {
	// Use XZ plane for UVs, apply scaling
	vec2 world_uv = world_pos.xz * scale;
	return texture(tex, world_uv);
}

void fragment() {
	// Get world position and normal Y from varyings
	vec3 world_pos = v_world_pos;
	float world_normal_y = v_world_normal_y;

	// === 1. Height-Based Material Determination ===
	// Sample base textures using world coordinates
	vec3 albedo_snow = sample_world(texture_albedo_snow, world_pos, world_uv_scale).rgb;
	vec3 albedo_rock = sample_world(texture_albedo_rock, world_pos, world_uv_scale).rgb;
	vec3 albedo_sand = sample_world(texture_albedo_sand, world_pos, world_uv_scale).rgb;

	// Calculate blending factors based on world height
	float snow_mix = smoothstep(snow_start_height, snow_full_height, world_pos.y);
	// For sand, blend increases as height *decreases*, so swap start/full in smoothstep
	float sand_mix = smoothstep(sand_start_height, sand_full_height, world_pos.y);

	// Blend Albedo: Start with rock, blend in sand, then blend in snow
	vec3 height_albedo = mix(albedo_rock, albedo_sand, sand_mix);
	height_albedo = mix(height_albedo, albedo_snow, snow_mix);

	// --- Roughness blending removed ---

	// === 2. Slope Blending ===
	// Sample slope texture
	vec3 albedo_slope = sample_world(texture_albedo_slope, world_pos, world_uv_scale).rgb;
	// --- Slope roughness removed ---

	// Calculate slope blend factor (increases as slope gets steeper / normal_y decreases)
	float slope_edge0 = slope_threshold - slope_blend_range * 0.5;
	float slope_edge1 = slope_threshold + slope_blend_range * 0.5;
	float slope_mix_factor = smoothstep(slope_edge1, slope_edge0, world_normal_y);

	// Mix slope layer over the height-determined base material
	vec3 final_albedo = mix(height_albedo, albedo_slope, slope_mix_factor);
	// --- Final roughness calculation removed ---

	// === 3. Wetness Effect Near Water Level ===
	// --- Wetness calculations and effects removed ---

	// === 4. Final Output ===
	ALBEDO = final_albedo * albedo_tint.rgb;
	// ROUGHNESS = ... ; // Removed - uses default roughness
	METALLIC = metallic; // Apply base metallic (can add textures/blending if needed)
	SPECULAR = specular;
	}