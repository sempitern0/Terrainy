shader_type spatial;

render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;

uniform float blend_factor : hint_range(0.1, 50.0) = 5.0;
uniform float fade_range = 5.0;
uniform float height_dirt = 5.0;
uniform float height_grass = 15.0;
uniform float height_mountain = 30.0;
//uniform float roughness : hint_range(0.0, 1.0) = 1.0;
//uniform float ao_light_affect : hint_range(0.0, 1.0);

group_uniforms Dirt;
uniform sampler2D dirt_albedo : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
//uniform sampler2D dirt_orm : source_color;
uniform float dirt_blend_sharpness = 1.0;
uniform float dirt_uv_scale : hint_range(0.01, 10.0, 0.01) = 1.0;
uniform float dirt_stochastic_strength : hint_range(0.0, 1.0) = 0;
uniform float dirt_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0;

group_uniforms Grass;
uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
//uniform sampler2D grass_orm : source_color;
uniform float grass_blend_sharpness = 1.0;
uniform float grass_uv_scale : hint_range(0.01, 10.0, 0.01) = 1.0;
uniform float grass_stochastic_strength : hint_range(0.0, 1.0) = 0;
uniform float grass_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0;

group_uniforms Mountain;
uniform sampler2D mountain_albedo : source_color, repeat_enable, filter_linear_mipmap, hint_default_white;
//uniform sampler2D mountain_orm : source_color;
uniform float mountain_blend_sharpness = 1.0;
uniform float mountain_uv_scale : hint_range(0.01, 10.0, 0.01) = 1.0;
uniform float mountain_stochastic_strength : hint_range(0.0, 1.0) = 0;
uniform float mountain_stochastic_rotation_max_angle : hint_range(0.0, 3.14159) = 0;

// ================================================================
// Varyings
// Data passed from Vertex Shader to Fragment Shader
// ================================================================
varying vec3 world_pos;            // Original vertex position in world space
varying vec3 triplanar_normal_abs; // Absolute world-space normal for triplanar blending weights
varying mat3 tangent_2_local;

// Simple hash function to generate pseudo-random numbers based on a 2D input.
// Used for consistent random offsets per "tile" in stochastic sampling.
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);

    return mat2(vec2(c, s),  vec2(-s, c));
}

// Helper function to unpack a normal from 0-1 range (texture) to -1 to 1 range (vector).
vec3 unpack_normal(vec3 packed_normal) {
    return packed_normal * 2.0 - 1.0;
}

// Helper function to pack a normal from -1 to 1 range (vector) to 0-1 range (for NORMAL_MAP output).
vec3 pack_normal(vec3 unpacked_normal) {
    return unpacked_normal * 0.5 + 0.5;
}

vec2 rotate_uv(vec2 uv, float angle) {
    float s = sin(angle);
    float c = cos(angle);

    return mat2(vec2(c, -s), vec2(s, c)) * uv;
}


vec2 stochastic_uv(vec2 uv, float strength, float max_rotation_angle) {
    // Get the tile index based on floor of UV
    vec2 tile_index = floor(uv);

    // Use tile index to generate rotation and offset
    float angle = hash21(tile_index) * max_rotation_angle;
    vec2 offset = vec2(hash21(tile_index + 1.3), hash21(tile_index + 2.1)) - 0.5;

    // Apply rotation and offset within each tile
    vec2 local_uv = fract(uv) + offset * strength;
    local_uv = rotate_uv(local_uv - 0.5, angle) + 0.5;

    return local_uv;
}

// Triplanar texture sampling with 4-sample stochastic anti-tiling for RGB textures.
// Includes random per-tile rotation and offset.
// tex: The texture to sample.
// p: Scaled world position (uv_scale * world_pos).
// normal_abs: Absolute world normal for blending between X, Y, Z projections.
// k: Triplanar blend factor (blend_factor).
// strength: Stochastic displacement strength (stochastic_strength).
// max_rotation_angle: Maximum random rotation angle (stochastic_rotation_max_angle).
vec3 apply_triplanar_texture_stochastic_rgb(sampler2D tex, vec3 p, vec3 normal_abs, float k, float strength, float max_rotation_angle) {
    // Calculate base UVs for each projection plane
    vec2 uv_xy = p.xy; // For Z-axis projection (top-down)
    vec2 uv_yz = p.yz; // For X-axis projection (side)
    vec2 uv_xz = p.xz; // For Y-axis projection (side)

    // --- XY Plane Projection (Z-axis) ---
    // Get the integer part of UV for a consistent random seed per tile
    vec2 tile_id_xy = floor(uv_xy);
    // Generate random rotation angle for this tile
    float random_angle_xy = hash21(tile_id_xy) * max_rotation_angle;
    mat2 rot_mat_xy = rotate2d(random_angle_xy);
    // Generate two random offsets for displacement (ensure distinct hashes for x,y components)
    vec2 rand_offset_xy = vec2(hash21(tile_id_xy + vec2(0.1, 0.0)), hash21(tile_id_xy + vec2(0.0, 0.1))) * strength;

    // Calculate the 'base' sampling UV by applying rotation around tile center
    // and then adding the random offset.
    // This 'base_sampling_uv' is the reference point for the 4 samples and the blending.
    vec2 base_sampling_uv_xy = (uv_xy - tile_id_xy - vec2(0.5)) * rot_mat_xy + tile_id_xy + vec2(0.5) + rand_offset_xy;

    // Use the fractional part of this base sampling UV for the blending weights
    vec2 frac_uv_for_blend_xy = fract(base_sampling_uv_xy);
    float blend_x_xy = smoothstep(0.4, 0.6, frac_uv_for_blend_xy.x);
    float blend_y_xy = smoothstep(0.4, 0.6, frac_uv_for_blend_xy.y);

    // Sample the texture 4 times. The (0,0), (1,0), etc. offsets are relative to the
    // potentially rotated and offset grid.
    vec3 s00_xy = texture(tex, base_sampling_uv_xy).rgb;
    vec3 s10_xy = texture(tex, base_sampling_uv_xy + vec2(1.0, 0.0)).rgb;
    vec3 s01_xy = texture(tex, base_sampling_uv_xy + vec2(0.0, 1.0)).rgb;
    vec3 s11_xy = texture(tex, base_sampling_uv_xy + vec2(1.0, 1.0)).rgb;
    // Blend the 4 samples using bilinear interpolation based on fractional UV
    vec3 color_xy = mix(mix(s00_xy, s10_xy, blend_x_xy), mix(s01_xy, s11_xy, blend_x_xy), blend_y_xy);


    // --- YZ Plane Projection (X-axis) ---
    vec2 tile_id_yz = floor(uv_yz);
    float random_angle_yz = hash21(tile_id_yz) * max_rotation_angle;
    mat2 rot_mat_yz = rotate2d(random_angle_yz);
    vec2 rand_offset_yz = vec2(hash21(tile_id_yz + vec2(0.1, 0.0)), hash21(tile_id_yz + vec2(0.0, 0.1))) * strength;

    vec2 base_sampling_uv_yz = (uv_yz - tile_id_yz - vec2(0.5)) * rot_mat_yz + tile_id_yz + vec2(0.5) + rand_offset_yz;

    vec2 frac_uv_for_blend_yz = fract(base_sampling_uv_yz);
    float blend_x_yz = smoothstep(0.4, 0.6, frac_uv_for_blend_yz.x);
    float blend_y_yz = smoothstep(0.4, 0.6, frac_uv_for_blend_yz.y);

    vec3 s00_yz = texture(tex, base_sampling_uv_yz).rgb;
    vec3 s10_yz = texture(tex, base_sampling_uv_yz + vec2(1.0, 0.0)).rgb;
    vec3 s01_yz = texture(tex, base_sampling_uv_yz + vec2(0.0, 1.0)).rgb;
    vec3 s11_yz = texture(tex, base_sampling_uv_yz + vec2(1.0, 1.0)).rgb;
    vec3 color_yz = mix(mix(s00_yz, s10_yz, blend_x_yz), mix(s01_yz, s11_yz, blend_x_yz), blend_y_yz);

    // --- XZ Plane Projection (Y-axis) ---
    vec2 tile_id_xz = floor(uv_xz);
    float random_angle_xz = hash21(tile_id_xz) * max_rotation_angle;
    mat2 rot_mat_xz = rotate2d(random_angle_xz);
    vec2 rand_offset_xz = vec2(hash21(tile_id_xz + vec2(0.1, 0.0)), hash21(tile_id_xz + vec2(0.0, 0.1))) * strength;

    vec2 base_sampling_uv_xz = (uv_xz - tile_id_xz - vec2(0.5)) * rot_mat_xz + tile_id_xz + vec2(0.5) + rand_offset_xz;

    vec2 frac_uv_for_blend_xz = fract(base_sampling_uv_xz);
    float blend_x_xz = smoothstep(0.4, 0.6, frac_uv_for_blend_xz.x);
    float blend_y_xz = smoothstep(0.4, 0.6, frac_uv_for_blend_xz.y);

    vec3 s00_xz = texture(tex, base_sampling_uv_xz).rgb;
    vec3 s10_xz = texture(tex, base_sampling_uv_xz + vec2(1.0, 0.0)).rgb;
    vec3 s01_xz = texture(tex, base_sampling_uv_xz + vec2(0.0, 1.0)).rgb;
    vec3 s11_xz = texture(tex, base_sampling_uv_xz + vec2(1.0, 1.0)).rgb;
    vec3 color_xz = mix(mix(s00_xz, s10_xz, blend_x_xz), mix(s01_xz, s11_xz, blend_x_xz), blend_y_xz);

    // Calculate blend weights for triplanar projection itself (based on normal direction)
    vec3 blend_weights = pow(normal_abs, vec3(k));
    blend_weights /= dot(blend_weights, vec3(1.0)); // Normalize weights to sum to 1

    // Final triplanar blend: combine the three projected colors using the calculated weights
    return color_yz * blend_weights.x + color_xz * blend_weights.y + color_xy * blend_weights.z;
}
vec4 apply_triplanar_texture_stochastic_rgba(
    sampler2D tex,
    vec3 p,
    vec3 normal_abs,
    float k,
    float strength,
    float max_rotation_angle
) {
    vec2 uv_xy = p.xy;
    vec2 uv_yz = p.yz;
    vec2 uv_xz = p.xz;

    // XY
    vec2 tile_id_xy = floor(uv_xy);
    float random_angle_xy = hash21(tile_id_xy) * max_rotation_angle;
    mat2 rot_mat_xy = rotate2d(random_angle_xy);
    vec2 rand_offset_xy = vec2(hash21(tile_id_xy + vec2(0.1, 0.0)), hash21(tile_id_xy + vec2(0.0, 0.1))) * strength;
    vec2 base_uv_xy = (uv_xy - tile_id_xy - vec2(0.5)) * rot_mat_xy + tile_id_xy + vec2(0.5) + rand_offset_xy;
    vec2 frac_uv_xy = fract(base_uv_xy);
    float blend_x_xy = smoothstep(0.4, 0.6, frac_uv_xy.x);
    float blend_y_xy = smoothstep(0.4, 0.6, frac_uv_xy.y);
    vec4 s00_xy = texture(tex, base_uv_xy);
    vec4 s10_xy = texture(tex, base_uv_xy + vec2(1.0, 0.0));
    vec4 s01_xy = texture(tex, base_uv_xy + vec2(0.0, 1.0));
    vec4 s11_xy = texture(tex, base_uv_xy + vec2(1.0, 1.0));
    vec4 color_xy = mix(mix(s00_xy, s10_xy, blend_x_xy), mix(s01_xy, s11_xy, blend_x_xy), blend_y_xy);

    // YZ
    vec2 tile_id_yz = floor(uv_yz);
    float random_angle_yz = hash21(tile_id_yz) * max_rotation_angle;
    mat2 rot_mat_yz = rotate2d(random_angle_yz);
    vec2 rand_offset_yz = vec2(hash21(tile_id_yz + vec2(0.1, 0.0)), hash21(tile_id_yz + vec2(0.0, 0.1))) * strength;
    vec2 base_uv_yz = (uv_yz - tile_id_yz - vec2(0.5)) * rot_mat_yz + tile_id_yz + vec2(0.5) + rand_offset_yz;
    vec2 frac_uv_yz = fract(base_uv_yz);
    float blend_x_yz = smoothstep(0.4, 0.6, frac_uv_yz.x);
    float blend_y_yz = smoothstep(0.4, 0.6, frac_uv_yz.y);
    vec4 s00_yz = texture(tex, base_uv_yz);
    vec4 s10_yz = texture(tex, base_uv_yz + vec2(1.0, 0.0));
    vec4 s01_yz = texture(tex, base_uv_yz + vec2(0.0, 1.0));
    vec4 s11_yz = texture(tex, base_uv_yz + vec2(1.0, 1.0));
    vec4 color_yz = mix(mix(s00_yz, s10_yz, blend_x_yz), mix(s01_yz, s11_yz, blend_x_yz), blend_y_yz);

    // XZ
    vec2 tile_id_xz = floor(uv_xz);
    float random_angle_xz = hash21(tile_id_xz) * max_rotation_angle;
    mat2 rot_mat_xz = rotate2d(random_angle_xz);
    vec2 rand_offset_xz = vec2(hash21(tile_id_xz + vec2(0.1, 0.0)), hash21(tile_id_xz + vec2(0.0, 0.1))) * strength;
    vec2 base_uv_xz = (uv_xz - tile_id_xz - vec2(0.5)) * rot_mat_xz + tile_id_xz + vec2(0.5) + rand_offset_xz;
    vec2 frac_uv_xz = fract(base_uv_xz);
    float blend_x_xz = smoothstep(0.4, 0.6, frac_uv_xz.x);
    float blend_y_xz = smoothstep(0.4, 0.6, frac_uv_xz.y);
    vec4 s00_xz = texture(tex, base_uv_xz);
    vec4 s10_xz = texture(tex, base_uv_xz + vec2(1.0, 0.0));
    vec4 s01_xz = texture(tex, base_uv_xz + vec2(0.0, 1.0));
    vec4 s11_xz = texture(tex, base_uv_xz + vec2(1.0, 1.0));
    vec4 color_xz = mix(mix(s00_xz, s10_xz, blend_x_xz), mix(s01_xz, s11_xz, blend_x_xz), blend_y_xz);

    // Triplanar blending with control over blending strength
    vec3 weights = pow(normal_abs, vec3(k));
    weights /= max(dot(weights, vec3(1.0)), 0.0001);

    return color_yz * weights.x + color_xz * weights.y + color_xy * weights.z;
}
vec3 apply_triplanar_texture_stochastic_normal(
    sampler2D normal_map,
    vec3 pos,
    vec3 normal_abs,
    float blend_sharpness,
    float strength,
    float max_rotation_angle
) {
    // === Weights ===
    vec3 weights = pow(normal_abs, vec3(blend_sharpness));
    weights /= max(dot(weights, vec3(1.0)), 0.0001);

    // === Projected stochastic UVs ===
    vec2 uv_yz = stochastic_uv(pos.yz, strength, max_rotation_angle);
    vec2 uv_xz = stochastic_uv(pos.xz, strength, max_rotation_angle);
    vec2 uv_xy = stochastic_uv(pos.xy, strength, max_rotation_angle);

    // === Sample and unpack normal maps ===
    vec3 n_yz = unpack_normal(texture(normal_map, uv_yz).rgb);
    vec3 n_xz = unpack_normal(texture(normal_map, uv_xz).rgb);
    vec3 n_xy = unpack_normal(texture(normal_map, uv_xy).rgb);

	n_yz *= tangent_2_local;
	n_xz *= tangent_2_local;
	n_xy *= tangent_2_local;

    // === Reorient normals from tangent space to world-space projection axis ===
    // YZ projection (X facing) → local Z = +X
    vec3 world_n_yz = vec3(n_yz.z, n_yz.x, n_yz.y);
    // XZ projection (Y facing) → local Z = +Y
    vec3 world_n_xz = vec3(n_xz.x, n_xz.z, n_xz.y);
    // XY projection (Z facing) → local Z = +Z
    vec3 world_n_xy = vec3(n_xy.x, n_xy.y, n_xy.z);

    // === Blend and normalize ===
    vec3 blended = normalize(
        world_n_yz * weights.x +
        world_n_xz * weights.y +
        world_n_xy * weights.z
    );

    return blended;
}

// ================================================================
// Vertex Shader
// Prepares world-space position and absolute normal for triplanar mapping
// ================================================================
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    triplanar_normal_abs = abs(NORMAL);

	TANGENT = vec3(0.0,0.0,-1.0) * abs(triplanar_normal_abs.x);
	TANGENT += vec3(1.0,0.0,0.0) * abs(triplanar_normal_abs.y);
	TANGENT += vec3(1.0,0.0,0.0) * abs(triplanar_normal_abs.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0,1.0,0.0) * abs(triplanar_normal_abs.x);
	BINORMAL += vec3(0.0,0.0,-1.0) * abs(triplanar_normal_abs.y);
	BINORMAL += vec3(0.0,1.0,0.0) * abs(triplanar_normal_abs.z);
	BINORMAL = normalize(BINORMAL);

	tangent_2_local = MODEL_NORMAL_MATRIX * mat3(TANGENT, BINORMAL, NORMAL);
	//normalize all components, so the UVs don't get scaled when scaling mesh
	tangent_2_local[0] = normalize(tangent_2_local[0]);
	tangent_2_local[1] = normalize(tangent_2_local[1]);
	tangent_2_local[2] = normalize(tangent_2_local[2]);
}

// ================================================================
// Fragment Shader
// Calculates final material properties
// ================================================================
void fragment() {
	float height = world_pos.y;

	float blend_dirt = 1.0 - smoothstep(height_dirt, height_dirt + fade_range, height);
 	float blend_grass = smoothstep(height_dirt, height_grass, height) * (1.0 - smoothstep(height_grass, height_mountain, height));
    float blend_mountain = smoothstep(height_grass, height_mountain, height);

	//Apply blend sharpness
	blend_dirt = pow(blend_dirt, dirt_blend_sharpness);
	blend_grass = pow(blend_grass, grass_blend_sharpness);
	blend_mountain = pow(blend_mountain, mountain_blend_sharpness);

	 // Normalize weights (if necessary — this makes sure they add up to 1.0)
    float total = blend_dirt + blend_grass + blend_mountain;
    blend_dirt /= total;
    blend_grass /= total;
    blend_mountain /= total;

    vec3 albedo_dirt = apply_triplanar_texture_stochastic_rgb(
        dirt_albedo,
        world_pos * dirt_uv_scale,
        triplanar_normal_abs,
        blend_factor,
        dirt_stochastic_strength,
        dirt_stochastic_rotation_max_angle
    );
	
	  vec3 albedo_grass = apply_triplanar_texture_stochastic_rgb(
        grass_albedo,
        world_pos * grass_uv_scale,
        triplanar_normal_abs,
        blend_factor,
        grass_stochastic_strength,
        grass_stochastic_rotation_max_angle
    );

	  vec3 albedo_mountain = apply_triplanar_texture_stochastic_rgb(
        mountain_albedo,
        world_pos * mountain_uv_scale,
        triplanar_normal_abs,
        blend_factor,
        mountain_stochastic_strength,
        mountain_stochastic_rotation_max_angle
    );
	
	//vec3 orm_dirt = texture(dirt_orm, UV * dirt_uv_scale).rgb;
	//vec3 orm_grass = texture(grass_orm, UV * grass_uv_scale).rgb;
	//vec3 orm_mountain = texture(mountain_orm, UV * mountain_uv_scale).rgb;
//
	//vec3 mixed_orm = mix(orm_dirt, orm_grass, blend_factor);
	//mixed_orm = mix(mixed_orm, orm_mountain, blend_factor);
	//
	ALBEDO = albedo_dirt * blend_dirt + albedo_grass * blend_grass + albedo_mountain * blend_mountain;
	//AO = mixed_orm.r;
	//AO_LIGHT_AFFECT = ao_light_affect;
	//ROUGHNESS = mixed_orm.g * roughness;
	//METALLIC = mixed_orm.b;
}