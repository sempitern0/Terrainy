// original World Mix Shader: 2022 Kasper Arnklit Frandsen - Public Domain - No Rights Reserved
// additional code from a shader material automatically converted from a spatial material in Godot 4.1
// https://godotshaders.com/shader/beefed-up-world-normal-mix-shader/
shader_type spatial;

group_uniforms detail_map;
uniform bool use_detail_map = false;
uniform bool enable_detail_albedo = true;
uniform vec3 detail_uv_scale = vec3(1.0);
uniform sampler2D texture_detail_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D texture_detail_normal : hint_normal,filter_linear_mipmap,repeat_enable;
uniform sampler2D texture_detail_mask : hint_default_white,filter_linear_mipmap,repeat_enable;

group_uniforms world_normal_mix_parameters;
uniform float offset : hint_range(-1.0, 1.0) = 0.5;
uniform float fade : hint_range(0.0, 1.0) = 0.1;

uniform vec3 uv_scale_fg = vec3(1.0);
uniform vec3 uv_scale_bg = vec3(1.0);


uniform sampler2D albedo_texture_fg : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D orm_texture_fg : source_color;
uniform sampler2D normal_texture_fg: hint_normal,filter_linear_mipmap,repeat_enable;

uniform sampler2D albedo_texture_bg : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D orm_texture_bg : source_color;
uniform sampler2D normal_texture_bg: hint_normal,filter_linear_mipmap,repeat_enable;

uniform float normal_scale : hint_range(-16,16) = 1;
uniform float roughness : hint_range(0,1) = 1;
uniform float ao_light_affect : hint_range(0.0,1.0);


void fragment() {
	vec2 fg_uv = UV * uv_scale_fg.xy;
	vec2 bg_uv = UV * uv_scale_bg.xy;
	vec3 albedo_tex_fg = texture(albedo_texture_fg, fg_uv).rgb;
	vec3 orm_tex_fg = texture(orm_texture_fg, fg_uv).rgb;
	vec3 normal_tex_fg = texture(normal_texture_fg, fg_uv).rgb;

	vec3 albedo_tex_bg = texture(albedo_texture_bg, bg_uv).rgb;
	vec3 orm_tex_bg = texture(orm_texture_bg, bg_uv).rgb;
	vec3 normal_tex_bg = texture(normal_texture_bg, bg_uv).rgb;

	vec3 bg_normal = normal_tex_bg * 2.0 - 1.0;
	bg_normal.z = sqrt(1.0 - bg_normal.x * bg_normal.x - bg_normal.y * bg_normal.y);
	vec3 normal_applied = bg_normal.x * TANGENT + bg_normal.y * BINORMAL + bg_normal.z * NORMAL;
	vec3 up_vector_viewspace = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	float dot_product = dot(up_vector_viewspace, normal_applied);
	float mask = smoothstep(offset - fade, offset + fade, dot_product);

	ALBEDO = mix(albedo_tex_bg, albedo_tex_fg, mask);
	vec3 mixed_orm = mix(orm_tex_bg, orm_tex_fg, mask);
	AO = mixed_orm.r;
	AO_LIGHT_AFFECT = ao_light_affect;
	ROUGHNESS = mixed_orm.g * roughness;
	METALLIC = mixed_orm.b;
	NORMAL_MAP = mix(normal_tex_bg, normal_tex_fg, mask);

	if (use_detail_map) {
		vec2 detail_uv = UV * detail_uv_scale.xy;
		vec4 detail_tex = texture(texture_detail_albedo,detail_uv);
		vec4 detail_norm_tex = texture(texture_detail_normal,detail_uv);
		vec4 detail_mask_tex = texture(texture_detail_mask,detail_uv);
		if (enable_detail_albedo) {
		vec3 detail = mix(ALBEDO.rgb,detail_tex.rgb,detail_tex.a);
		ALBEDO = mix(ALBEDO,detail,detail_mask_tex.r);
	}

	vec3 detail_norm = mix(NORMAL_MAP,detail_norm_tex.rgb,detail_tex.a);
	NORMAL_MAP = mix(NORMAL_MAP,detail_norm,detail_mask_tex.r);
	}

	NORMAL_MAP_DEPTH = normal_scale;
}