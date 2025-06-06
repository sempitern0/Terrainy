class_name ChunkTerrain extends Node3D

@export var collision_type: TerrainyCore.CollisionType = TerrainyCore.CollisionType.Trimesh

@export_category("Base continent")
@export var noise_continent: FastNoiseLite
@export var continent_randomize_seed: bool = true
@export var continent_slope_scale: float = 8.0
@export var continent_min_height: float = -10.0
@export var continent_max_height: float = 25.0

@export_category("Mountain Control")
@export var noise_mountain: FastNoiseLite
@export var mountain_randomize_seed: bool = true

@export var mountain_scale: float = 40.0
@export var mountain_start_height: float = 10.0
@export var mountain_fade_height: float = 10.0

@export_category("Valley Control")
@export var noise_valley: FastNoiseLite
@export var valley_randomize_seed: bool = true
@export var valley_carve_scale: float = 15.0
@export var valley_apply_threshold: float = 5.0

@export_category("Erosion Control")
@export var noise_erosion: FastNoiseLite
@export var erosion_randomize_seed: bool = true
@export var erosion_scale: float = 2.5


var chunk_size_x: int = 32
var chunk_size_z: int = 32
var vertices_x: int = 33
var vertices_z: int = 33
var origin_coords: Vector2i = Vector2i.ZERO
var generated: bool = false


func set_size(_chunk_size_x: int, _chunk_size_z: int, _vertices_x: int, _vertices_z: int) -> ChunkTerrain:
	chunk_size_x = _chunk_size_x
	chunk_size_z = _chunk_size_z
	vertices_x = _vertices_x
	vertices_z = _vertices_z
	
	return self


func generate(coords: Vector2i = origin_coords, word_scale: float = 10.0) -> void:
	if not generated:
		generated = true
		#global_position.x = coords.x * chunk_size_x * word_scale
		#global_position.z = coords.y * chunk_size_z * word_scale
		
		var chunk_mesh_instance: MeshInstance3D = MeshInstance3D.new()
		chunk_mesh_instance.name = "ChunkTerrain[%d]_[%d]" % [coords.x, coords.y]
		
		var surface_tool: SurfaceTool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

		var step_x_world_units = chunk_size_x / float(vertices_x - 1)
		var step_z_world_units = chunk_size_z / float(vertices_z - 1)
		
		for z in range(vertices_z):
			for x in range(vertices_x):
				var vertex_x = x * step_x_world_units 
				var vertex_z = z * step_z_world_units
				var world_x_coord = vertex_x + coords.x * chunk_size_x
				var world_z_coord = vertex_z + coords.y * chunk_size_z
				
				var raw_continent_noise = noise_continent.get_noise_2d(world_x_coord , world_z_coord)
				var normalized_continent_noise = (raw_continent_noise + 1.0) * 0.5
				var conceptual_base_height = lerp(continent_min_height, continent_max_height, normalized_continent_noise)
				
				var mountain_modulator = clamp((conceptual_base_height - mountain_start_height) / mountain_fade_height, 0.0, 1.0)
				var m_potential = max(0.0, noise_mountain.get_noise_2d(world_x_coord, world_z_coord)) * mountain_scale
				var mountain_contribution = m_potential * mountain_modulator
				
				var valley_carve = 0.0

				if conceptual_base_height < valley_apply_threshold:
					var valley_noise = noise_valley.get_noise_2d(world_x_coord, world_z_coord)
					var negative_valley = min(valley_noise, 0.0)
					var valley_modulator = clamp((valley_apply_threshold - conceptual_base_height) / valley_apply_threshold, 0.0, 1.0)
					valley_carve = negative_valley * valley_carve_scale * valley_modulator

				var erosion_intensity_modulator  = 1.0 - abs(normalized_continent_noise - 0.5) * 2.0
				var erosion_bump_effect  = noise_erosion.get_noise_2d(world_x_coord, world_z_coord) * erosion_scale * erosion_intensity_modulator 

				var continent_slope_contribution = raw_continent_noise * continent_slope_scale
				var final_vertex_height = continent_slope_contribution + mountain_contribution + valley_carve + erosion_bump_effect 

				var vertex = Vector3(vertex_x, final_vertex_height, vertex_z)
				var uv_coordinate  = Vector2(x / float(vertices_x - 1), z / float(vertices_z - 1))
				
				surface_tool.set_uv(uv_coordinate)
				surface_tool.add_vertex(vertex)
		
		# Generate indices for triangles
		for z_quad_index in range(vertices_z - 1):
			for x_quad_index in range(vertices_x - 1):
				var top_left_index = z_quad_index * vertices_x + x_quad_index
				var top_right_index = top_left_index + 1
				var bottom_left_index  = (z_quad_index + 1) * vertices_x + x_quad_index
				var bottom_right_index  = bottom_left_index + 1
				
				# First triangle of the quad
				surface_tool.add_index(top_left_index)
				surface_tool.add_index(top_right_index)
				surface_tool.add_index(bottom_left_index)
				
				# Second triangle of the quad
				surface_tool.add_index(top_right_index)
				surface_tool.add_index(bottom_right_index)
				surface_tool.add_index(bottom_left_index)
				
		surface_tool.generate_normals()
		surface_tool.generate_tangents()
		
		chunk_mesh_instance.mesh = surface_tool.commit()
		generate_collisions(chunk_mesh_instance)
		call_thread_safe("add_child", chunk_mesh_instance)
		
		chunk_mesh_instance.scale = Vector3.ONE * word_scale


func generate_collisions(terrain_mesh: MeshInstance3D) -> void:
	if collision_type == TerrainyCore.CollisionType.Trimesh:
		terrain_mesh.call_thread_safe("create_trimesh_collision")
	elif collision_type == TerrainyCore.CollisionType.ConcavePolygon:
		var static_body: StaticBody3D = StaticBody3D.new()
		static_body.name = "TerrainStaticBody"
		
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.name = "TerrainCollisionShape"
		
		var concave_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		concave_shape.set_faces(terrain_mesh.mesh.get_faces())
		
		collision_shape.shape = concave_shape
		
		static_body.call_thread_safe("add_child", collision_shape)
		terrain_mesh.call_thread_safe("add_child", static_body)
