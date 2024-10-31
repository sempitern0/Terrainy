shader_type spatial;

uniform sampler2D grass_texture;
uniform float grass_texture_uv_size : hint_range(0.01, 100.0, 0.01) = 4.0;
// Modified version of the shader from DitzyNinja's Godojo that can be found in this video https://www.youtube.com/watch?v=x7ti3AEhV18
uniform sampler2D rock_texture;
uniform float rock_texture_uv_size : hint_range(0.01, 100.0, 0.01) = 4.0;

uniform sampler2D sand_texture;
uniform float sand_texture_uv_size : hint_range(0.01, 100.0, 0.01) = 4.0;

// If min rock slope and max rock slope are equals causes the shader to divide by 0 when normalizing the range
// and turn the material black
uniform float min_rock_slope: hint_range(0.0,1.0) = 0.5;
uniform float max_grass_slope: hint_range(0.0,1.0) = 0.9;
uniform float min_rockgrass_height = -8.0;
uniform float max_sand_height = -6.0;

varying float normal_y;
varying float vertex_y;

void vertex(){
	normal_y = NORMAL.y;
	vertex_y = VERTEX.y;
}

void fragment(){
	vec2 Grass_UV_Scaled = UV * grass_texture_uv_size;
	vec2 Rock_UV_Scaled = UV * rock_texture_uv_size;
	vec2 Sand_UV_Scaled = UV * sand_texture_uv_size;

	//Albedo Values
	vec3 grass_albedo = texture(grass_texture, Grass_UV_Scaled).xyz;
	vec3 rock_albedo = texture(rock_texture, Rock_UV_Scaled).xyz;
	vec3 sand_albedo = texture(sand_texture, Sand_UV_Scaled).xyz;

	//Weights
	float rock_grass_weight = normal_y;
	float sand_rockgrass_weight = vertex_y;

	//Calculating Rock/Grass Weight
	rock_grass_weight = max(min_rock_slope, rock_grass_weight);
	rock_grass_weight = min(max_grass_slope, rock_grass_weight);
	rock_grass_weight -= min_rock_slope;
	rock_grass_weight /= max_grass_slope - min_rock_slope;


	//Calculating Sand/RockGrass Weight
	sand_rockgrass_weight = max(min_rockgrass_height, sand_rockgrass_weight);
	sand_rockgrass_weight = min(max_sand_height, sand_rockgrass_weight);
	sand_rockgrass_weight -= min_rockgrass_height;
	sand_rockgrass_weight /= max_sand_height - min_rockgrass_height;

	//Mixing and Assigning Albedo
	vec3 rockgrass_albedo = mix(rock_albedo, grass_albedo, rock_grass_weight);
	ALBEDO = mix(sand_albedo, rockgrass_albedo, sand_rockgrass_weight);
}