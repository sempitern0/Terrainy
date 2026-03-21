shader_type spatial;

const float SMOOTHSTEP_AA = 0.01;
uniform sampler2D surfaceNoise;
uniform sampler2D distortNoise;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

uniform float beer_factor = 0.8;
uniform vec4 foam_color: source_color  = vec4(1.0);
uniform float foam_max_distance = 0.4;
uniform float foam_min_distance = 0.04;

uniform vec2 surface_noise_tiling = vec2(1.0, 4.0);
uniform vec3 surface_noise_scroll = vec3(0.03, 0.03, 0.0);
uniform float surface_noise_cutoff: hint_range(0, 1) = 0.777;
uniform float surface_distortion_amount: hint_range(0, 1) = 0.27;

uniform vec4 _DepthGradientShallow: source_color = vec4(0.325, 0.807, 0.971, 0.725);
uniform vec4 _DepthGradientDeep: source_color = vec4(0.086, 0.407, 1, 0.749);
uniform float _DepthMaxDistance: hint_range(0, 1) = 1.0;
uniform float _DepthFactor = 1.0;

// --- NUEVO: PARÁMETROS DE ESTILO CARTOON ---
group_uniforms Visual_Polish;
uniform int depth_layers : hint_range(2, 10) = 4; // Cuántas bandas de color quieres
uniform float caustics_amount : hint_range(0, 1) = 0.5;
uniform float caustics_scale = 0.5;
group_uniforms;

varying vec2 noiseUV;
varying vec2 distortUV;
varying vec3 viewNormal;

vec4 alphaBlend(vec4 top, vec4 bottom) {
	vec3 color = (top.rgb * top.a) + (bottom.rgb * (1.0 - top.a));
	float alpha = top.a + bottom.a * (1.0 - top.a);
	return vec4(color, alpha);
}

void vertex() {
	viewNormal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	noiseUV = UV * surface_noise_tiling;
	distortUV = UV;
}

void fragment(){
	float depthVal = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	float depth = PROJECTION_MATRIX[3][2] / (depthVal + PROJECTION_MATRIX[2][2]);
	depth = depth + VERTEX.z;
	depth = exp(-depth * beer_factor);
	depth = 1.0 - depth;

    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depthVal, 1.0);
    view_pos /= view_pos.w;
    vec3 existingNormal = normalize(cross( dFdx(view_pos.xyz), dFdy(view_pos.xyz)));

	float normalDot = clamp(dot(existingNormal.xyz, viewNormal), 0.0, 1.0);
	float foamDistance = mix(foam_max_distance, foam_min_distance, normalDot);
	
	float foamDepth = clamp(depth / foamDistance, 0.0, 1.0);
	float surfaceNoiseCutoff = foamDepth * surface_noise_cutoff;
	
	vec4 distortNoiseSample = texture(distortNoise, distortUV);
	vec2 distortAmount = (distortNoiseSample.xy * 2.0 -1.0) * surface_distortion_amount;
	
	// --- MEJORA: CÁUSTICAS FALSAS ---
	// Reutilizamos el ruido de distorsión para crear un efecto de luz bajo el agua
	vec2 caustics_uv = (UV * caustics_scale) + (distortAmount * 0.5) + (TIME * surface_noise_scroll.xy * 0.5);
	float caustics_sample = texture(surfaceNoise, caustics_uv).r;
	float caustics_mask = (1.0 - depth); // Solo se ven en zonas poco profundas
	float caustics_final = smoothstep(0.5, 0.55, caustics_sample) * caustics_amount * caustics_mask;

	vec2 noise_uv = vec2(
		(noiseUV.x + TIME * surface_noise_scroll.x) + distortAmount.x , 
		(noiseUV.y + TIME * surface_noise_scroll.y + distortAmount.y)
	);
	float surfaceNoiseSample = texture(surfaceNoise, noise_uv).r;
	float surfaceNoiseAmount = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);
	
	// --- MEJORA: DEPTH STEPPING (POSTERIZACIÓN) ---
	float rawWaterDepth = clamp(depth / _DepthMaxDistance, 0.0, 1.0) * _DepthFactor;
	float steppedDepth = floor(rawWaterDepth * float(depth_layers)) / float(depth_layers);
	
	vec4 waterColor = mix(_DepthGradientShallow, _DepthGradientDeep, steppedDepth);
	
	// Aplicar las cáusticas al color base del agua
	waterColor.rgb += caustics_final * foam_color.rgb;

	vec4 surfaceNoiseColor = foam_color;
    surfaceNoiseColor.a *= surfaceNoiseAmount;
	vec4 color = alphaBlend(surfaceNoiseColor, waterColor);
	
    ALBEDO = color.rgb;
	ALPHA = color.a;
}