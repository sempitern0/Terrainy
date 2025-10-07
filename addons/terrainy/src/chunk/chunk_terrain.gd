class_name ChunkTerrain extends Node3D

@export var collision_type: TerrainyCore.CollisionType = TerrainyCore.CollisionType.Trimesh

@export var continent: ChunkContinent
@export var mountain: ChunkMountain
@export var valley: ChunkValley
@export var erosion: ChunkErosion
@export_category("Water")
@export var water_material: Material
@export var water_height_level: float = -2.0


var chunk_size_x: int = 32
var chunk_size_z: int = 32
var vertices_x: int = 33
var vertices_z: int = 33
var origin_coords: Vector2i = Vector2i.ZERO
var generated: bool = false

var terrain_mesh_instance: MeshInstance3D


func set_size(_chunk_size_x: int, _chunk_size_z: int, _vertices_x: int, _vertices_z: int) -> ChunkTerrain:
	chunk_size_x = _chunk_size_x
	chunk_size_z = _chunk_size_z
	vertices_x = _vertices_x
	vertices_z = _vertices_z
	
	return self


func generate(coords: Vector2i = origin_coords, word_scale: float = 10.0) -> void:
	if not generated:
		generated = true

		terrain_mesh_instance = MeshInstance3D.new()
		terrain_mesh_instance.name = "ChunkTerrain[%d]_[%d]" % [coords.x, coords.y]
		
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
				
				var raw_continent_noise = continent.noise.get_noise_2d(world_x_coord , world_z_coord)
				var normalized_continent_noise = (raw_continent_noise + 1.0) * 0.5
				var conceptual_base_height = lerp(continent.min_height, continent.max_height, normalized_continent_noise)
				
				var mountain_modulator = clamp((conceptual_base_height - mountain.start_height) / mountain.fade_height, 0.0, 1.0)
				var m_potential = max(0.0, mountain.noise.get_noise_2d(world_x_coord, world_z_coord)) * mountain.scale
				var mountain_contribution = m_potential * mountain_modulator
				
				var valley_carve = 0.0

				if conceptual_base_height < valley.apply_threshold:
					var valley_noise = valley.noise.get_noise_2d(world_x_coord, world_z_coord)
					var negative_valley = min(valley_noise, 0.0)
					var valley_modulator = clamp((valley.apply_threshold - conceptual_base_height) / valley.apply_threshold, 0.0, 1.0)
					valley_carve = negative_valley * valley.carve_scale * valley_modulator

				var erosion_intensity_modulator  = 1.0 - abs(normalized_continent_noise - 0.5) * 2.0
				var erosion_bump_effect  = erosion.noise.get_noise_2d(world_x_coord, world_z_coord) * erosion.scale * erosion_intensity_modulator 

				var continent_slope_contribution = raw_continent_noise * continent.slope_scale
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
		
		terrain_mesh_instance.mesh = surface_tool.commit()
		generate_collisions(terrain_mesh_instance)
		call_thread_safe("add_child", terrain_mesh_instance)
		
		terrain_mesh_instance.scale = Vector3.ONE * word_scale
		
		generate_water(terrain_mesh_instance)


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
		
		
func generate_water(terrain_mesh: MeshInstance3D) -> void:
	if water_material:
		var water_plane: MeshInstance3D = MeshInstance3D.new()
		water_plane.name = "Water"
		
		var water_mesh = PlaneMesh.new()
		water_mesh.size = Vector2(chunk_size_x, chunk_size_z)
		
		water_plane.mesh = water_mesh
		water_plane.position = Vector3(chunk_size_x / 2.0, water_height_level, chunk_size_z / 2.0)
		
		water_plane.set_surface_override_material(0, water_material)
		
		terrain_mesh.call_thread_safe("add_child", water_plane)
