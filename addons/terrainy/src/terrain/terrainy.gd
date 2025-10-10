@tool
class_name Terrainy extends Node

signal terrain_surfaces_finished(finished_surfaces: Dictionary[Terrain, SurfaceTool])
signal terrain_generation_finished(finished_terrains: Array[Terrain])

@export var button_Generate_Terrain: String
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var terrains: Array[Terrain] = []
@export_category("Grid")
@export var button_Generate_Terrain_Grid: String
@export var grid_spawn_node: Node3D
## For better results make sure all the terrain configurations have the same depth, width and mesh resolution
@export var grid_size: int = 8:
	set(value):
		grid_size = maxi(value, 2)
@export var grid_directions: Array[Vector3] = [
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3.RIGHT,
	Vector3.LEFT
]
## A set of terrain configurations to appear in the grid, you can configure the weight for
## each of them to set the probability.
@export var grid_terrain_configurations: Dictionary[TerrainConfiguration, float] = {}
@export_category("Navigation region")
@export var nav_source_group_name: StringName = &"terrain_navigation_source"
## This navigation needs to set the value Source Geometry -> Group Explicit
@export var navigation_region: NavigationRegion3D
## This will create a NavigationRegion3D automatically with the correct parameters
@export var create_navigation_region_in_runtime: bool = false
@export var bake_navigation_region_in_runtime: bool = false

var thread: Thread
var pending_terrain_surfaces: Dictionary[Terrain, SurfaceTool] = {}


func generate_terrains(selected_terrains: Array[Terrain] = []) -> void:
	selected_terrains = selected_terrains.filter(func(terrain: Terrain): return terrain != null)
	
	if selected_terrains.is_empty():
		push_warning("Terrainy->generate_terrains: This node needs at least one Terrain to start the generation, aborting...")
		return
		
	if not terrain_surfaces_finished.is_connected(on_terrain_surfaces_finished):
		terrain_surfaces_finished.connect(on_terrain_surfaces_finished)
		
	pending_terrain_surfaces.clear()
	
	print("Terrainy->generate_terrains: Generating a total of %d terrains..." % selected_terrains.size())
	
	var terrain_task_id: int = WorkerThreadPool.add_group_task(process_terrain_generation.bind(selected_terrains), selected_terrains.size())
	WorkerThreadPool.wait_for_group_task_completion(terrain_task_id)


func generate_terrain_grid(terrain_grid_size: int = grid_size) -> void:
	terrain_grid_size = maxi(terrain_grid_size, 2)
	
	if grid_terrain_configurations.is_empty():
		push_warning("Terrainy->generate_terrain_grid: No terrain configurations detected to generate the grid, aborting...")
		return
		
	if grid_spawn_node == null:
		push_warning("Terrainy->generate_terrain_grid: No grid spawn node detected to create the terrains, aborting...")
		return
		
	var grid_terrains: Array[Terrain] = []
	
	for index: int in terrain_grid_size:
		var selected_configuration: TerrainConfiguration = _pick_weighted_grid_terrain_configuration(grid_terrain_configurations)
		var new_terrain: Terrain
		
		if selected_configuration is TerrainNoiseConfiguration:
			new_terrain = TerrainNoise.new()
		elif selected_configuration is TerrainNoiseTextureConfiguration:
			new_terrain = TerrainNoiseTexture.new()
		elif selected_configuration is TerrainHeightmapConfiguration:
			new_terrain = TerrainHeightmap.new()
		
		new_terrain.configuration = selected_configuration
			
		grid_terrains.append(new_terrain)
		grid_spawn_node.add_child(new_terrain)
		new_terrain.position = Vector3.ZERO
		new_terrain.name = "GridTerrain%d" % index
	
	call_deferred("generate_terrains", grid_terrains)
	
	terrain_generation_finished.connect(
		func(terrains: Array[Terrain]): 
			if terrains.is_empty():
				push_warning("Terrainy->generate_terrain_grid: No terrains generated for grid allocation.")
				return
			
			var to_expand: Array[Terrain] = [terrains.front()]
			var placed_terrains: Array[Terrain] = [terrains.front()]
			var available_terrains: Array[Terrain] = terrains.filter(func(terrain: Terrain): return terrain != to_expand.front())

			var count: int = 1
			
			while not to_expand.is_empty() and count < terrain_grid_size and available_terrains.size() > 0:
				var current_terrain: Terrain = to_expand.pop_front()
				
				for direction: Vector3 in grid_directions:
					if current_terrain.neighbours[direction] != null:
						continue  
					
					if available_terrains.is_empty():
						break
					
					var next_terrain: Terrain = available_terrains.pop_front()
					var result: bool = current_terrain.assign_neighbour(next_terrain, direction)
					
					if result:
						count += 1
						call_deferred("generate_side_terrain", current_terrain, next_terrain, direction)
						
						to_expand.append(next_terrain)
						placed_terrains.append(next_terrain)
						
						if count >= terrain_grid_size:
							break
				
				if count >= terrain_grid_size:
					break
				
			, CONNECT_ONE_SHOT)


func process_terrain_generation(index: int, terrains: Array[Terrain]) -> void:
	generate_terrain(terrains[index])
	

func generate_terrain(terrain: Terrain) -> void:
	if terrain == null or not is_instance_valid(terrain):
		push_warning("Terrainy->generate_terrain: This node needs a valid Terrain to create the terrain, aborting...")
		return
		
	elif terrain is TerrainNoise and not terrain.validate():
		push_warning("Terrainy->generate_terrain: The TerrainNoise needs a valid FastNoiseLite assigned in the configuration.")
		return
	
	elif terrain is TerrainNoiseTexture and not terrain.validate():
		push_warning("Terrainy->generate_terrain: The TerrainNoiseTexture needs a valid noise Texture2D assigned in the configuration.")
		return
	elif terrain is TerrainHeightmap and not terrain.validate():
		push_warning("Terrainy->generate_terrain: The TerrainHeightmap needs a valid heightmap Texture2D assigned in the configuration.")
		return
	
	call_thread_safe("_set_owner_to_edited_scene_root", terrain)
	call_thread_safe("_free_children", terrain)
	
	var plane_mesh = PlaneMesh.new()
	call_thread_safe("set_terrain_size_on_plane_mesh", terrain.configuration, plane_mesh)
	terrain.set_deferred_thread_group("mesh", plane_mesh)

	call_thread_safe("create_surface", terrain)
	

func create_surface(terrain: Terrain) -> void:
	pending_terrain_surfaces[terrain] = terrain.generate_surface()
	
	if pending_terrain_surfaces.keys().size() == terrains.size():
		call_deferred_thread_group("emit_signal", "terrain_surfaces_finished", pending_terrain_surfaces)


func set_terrain_size_on_plane_mesh(configuration: TerrainConfiguration, plane_mesh: PlaneMesh) -> void:
	plane_mesh.size = Vector2(configuration.size_width, configuration.size_depth)
	plane_mesh.subdivide_depth = configuration.mesh_resolution
	plane_mesh.subdivide_width = configuration.mesh_resolution
	
	if configuration.terrain_material:
		plane_mesh.material = configuration.terrain_material
	else:
		plane_mesh.material = TerrainyCore.DefaultTerrainMaterial
	

func generate_collisions(collision_type: TerrainyCore.CollisionType, terrain_mesh: MeshInstance3D) -> void:
	if collision_type == TerrainyCore.CollisionType.Trimesh:
		terrain_mesh.create_trimesh_collision()
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
		call_thread_safe("_set_owner_to_edited_scene_root", static_body)
		call_thread_safe("_set_owner_to_edited_scene_root", collision_shape)


func create_navigation_region(selected_navigation_region: NavigationRegion3D = navigation_region) -> void:
	if selected_navigation_region == null and create_navigation_region_in_runtime:
		selected_navigation_region = NavigationRegion3D.new()
		selected_navigation_region.navigation_mesh = NavigationMesh.new()
		call_thread_safe("add_child", selected_navigation_region)
		call_thread_safe("_set_owner_to_edited_scene_root", selected_navigation_region)
	
	if selected_navigation_region:
		selected_navigation_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_BOTH
		selected_navigation_region.navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
		selected_navigation_region.navigation_mesh.geometry_source_group_name = nav_source_group_name
		
		if bake_navigation_region_in_runtime:
			selected_navigation_region.navigation_mesh.clear()
			selected_navigation_region.bake_navigation_mesh()
			await selected_navigation_region.bake_finished
	
	navigation_region = selected_navigation_region


func generate_side_terrain(origin_terrain: Terrain, new_terrain: Terrain, direction: Vector3) -> void:
	if origin_terrain == null or origin_terrain.mesh == null:
		push_error("Terrainy->generate_side_terrain: origin_terrain is invalid or has no mesh.")
		return
	if new_terrain == null or new_terrain.mesh == null:
		push_error("Terrainy->generate_side_terrain: new_terrain is invalid or has no mesh.")
		return
	if origin_terrain.mesh.get_surface_count() == 0 or new_terrain.mesh.get_surface_count() == 0:
		push_error("Terrainy->generate_side_terrain: One of the meshes has no surfaces.")
		return

	if origin_terrain.configuration == null or new_terrain.configuration == null:
		push_error("Terrainy->generate_side_terrain: Missing TerrainConfiguration for one of the terrains.")
		return
		
	var width: int = origin_terrain.configuration.size_width
	var depth: int = origin_terrain.configuration.size_depth
	var resolution: int = origin_terrain.configuration.mesh_resolution
	
	if not new_terrain.grid_positioned:
		new_terrain.grid_positioned = true
		
		var offset_local: Vector3 = Vector3.ZERO
		
		if abs(direction.x) > abs(direction.z):
			offset_local.x = sign(direction.x) * width
			
		elif abs(direction.z) > abs(direction.x):
			offset_local.z = sign(direction.z) * depth
		
		var offset_global: Vector3 = origin_terrain.global_transform.basis * offset_local
		new_terrain.global_position = origin_terrain.global_position + offset_global

	var origin_st: SurfaceTool = SurfaceTool.new()
	origin_st.create_from(origin_terrain.mesh, 0)
	var origin_mesh: ArrayMesh = origin_st.commit()
	var origin_mdt: MeshDataTool = MeshDataTool.new()
	origin_mdt.create_from_surface(origin_mesh, 0)

	var new_st: SurfaceTool= SurfaceTool.new()
	new_st.create_from(new_terrain.mesh, 0)
	var new_mesh: ArrayMesh = new_st.commit()
	var new_mdt: MeshDataTool = MeshDataTool.new()
	new_mdt.create_from_surface(new_mesh, 0)

	var match_axis: Vector2 = Vector2.ZERO
	var origin_edge = []
	var new_edge = []

	if abs(direction.x) > abs(direction.z):
		match_axis = Vector2(1, 0)
		
		if direction.x > 0:
			origin_edge = _get_edge_vertices(origin_mdt, width * 0.5, "x", true)
			new_edge = _get_edge_vertices(new_mdt, -width * 0.5, "x", false)
		else:
			origin_edge = _get_edge_vertices(origin_mdt, -width * 0.5, "x", true)
			new_edge = _get_edge_vertices(new_mdt, width * 0.5, "x", false)
	else:
		match_axis = Vector2(0, 1)
		
		if direction.z > 0:
			origin_edge = _get_edge_vertices(origin_mdt, depth * 0.5, "z", true)
			new_edge = _get_edge_vertices(new_mdt, -depth * 0.5, "z", false)
		else:
			origin_edge = _get_edge_vertices(origin_mdt, -depth * 0.5, "z", true)
			new_edge = _get_edge_vertices(new_mdt, depth * 0.5, "z", false)
	
	if origin_edge.size() == new_edge.size():
		for i in range(origin_edge.size()):
			var origin_v = origin_edge[i]
			var new_idx = new_edge[i]
			var new_v: Vector3 = new_mdt.get_vertex(new_idx)
			new_v.y = origin_v.y
			new_mdt.set_vertex(new_idx, new_v)
			
	var blend_width: int = 3  
	var blend_axis: String = ""
	var sign_dir: float = 1.0

	if abs(direction.x) > abs(direction.z):
		blend_axis = "x"
		sign_dir = sign(direction.x)
	else:
		blend_axis = "z"
		sign_dir = sign(direction.z)

	for i in range(new_mdt.get_vertex_count()):
		var v: Vector3 = new_mdt.get_vertex(i)
		var distance_from_edge: float = 0.0

		if blend_axis == "x":
			var edge_pos: float = (-width * 0.5) if (sign_dir > 0) else (width * 0.5)
			distance_from_edge = abs(v.x - edge_pos) / (width / float(resolution))
		else:
			var edge_pos: float = (-depth * 0.5) if (sign_dir > 0) else (depth * 0.5)
			distance_from_edge = abs(v.z - edge_pos) / (depth / float(resolution))

		if distance_from_edge > 0 and distance_from_edge <= blend_width:
			var t: float = 1.0 - (distance_from_edge / float(blend_width))
			var nearest_edge_height: float = 0.0
			
			if origin_edge.size() > 0:
				var avg_height := 0.0
				
				for e in origin_edge:
					avg_height += e.y
				nearest_edge_height = avg_height / float(origin_edge.size())

			v.y = lerp(v.y, nearest_edge_height, t * 0.5)
			new_mdt.set_vertex(i, v)

	new_mesh.clear_surfaces()
	new_mdt.commit_to_surface(new_mesh)

	var st_final: SurfaceTool = SurfaceTool.new()
	st_final.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_final.create_from(new_mesh, 0)
	st_final.generate_normals()
	st_final.generate_tangents()
	new_terrain.mesh = st_final.commit()


func on_terrain_surfaces_finished(terrain_surfaces: Dictionary[Terrain, SurfaceTool]) -> void:
	print("Terrainy: Generation of %d terrain surfaces is finished! " % terrain_surfaces.size())
	
	for terrain: Terrain in terrain_surfaces:
		terrain.mesh = terrain_surfaces[terrain].commit() 
		terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain.add_to_group(nav_source_group_name)
		
		if terrain.configuration.generate_mirror:
			var mirror_terrain: Terrain = TerrainyCore.create_mirrored_terrain(terrain)
			terrain.call_thread_safe("add_mirror_terrain", mirror_terrain)
			
			if mirror_terrain:
				terrain.call_thread_safe("add_child", mirror_terrain)
				call_thread_safe("_set_owner_to_edited_scene_root", mirror_terrain)
				terrain.mirror.global_transform = terrain.global_transform
				
				generate_collisions(terrain.configuration.mirror_collision_type, mirror_terrain)
				
		generate_collisions(terrain.configuration.collision_type, terrain)
		
	create_navigation_region(navigation_region)
	
	terrain_generation_finished.emit(terrain_surfaces.keys())
		

#region Helpers
func _set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root


func _free_children(node: Node) -> void:
	if node.get_child_count() == 0:
		return

	var childrens = node.get_children()
	childrens.reverse()
	
	for child in childrens.filter(func(_node: Node): return is_instance_valid(node)):
		child.free()


func _on_tool_button_pressed(text: String) -> void:
	match text:
		"Generate Terrain":
			generate_terrains(terrains)
		"Generate Terrain Grid":
			generate_terrain_grid(grid_size)


func _pick_weighted_grid_terrain_configuration(configurations: Dictionary[TerrainConfiguration, float] = grid_terrain_configurations) -> TerrainConfiguration:
	if configurations.is_empty():
		return null
		
	if configurations.size() == 1:
		return configurations.keys().front()
	
	var total_weight: float = 0.0
	
	for weight: float in configurations.values():
		total_weight += weight

	var random: float = randf() * total_weight
	var accumulative: float = 0.0
	
	for config: TerrainConfiguration in configurations.keys():
		accumulative += configurations[config]
		
		if random <= accumulative:
			return config
	
	# Fallback (por si acaso)
	return configurations.keys()[0]


func _get_edge_vertices(mdt: MeshDataTool, edge_value: float, axis: String, return_vertices: bool = false) -> Array[Variant]:
	var verts: Array[Variant] = []
	
	for i: int in range(mdt.get_vertex_count()):
		var vertex: Vector3 = mdt.get_vertex(i)
		
		if axis == "x":
			if is_equal_approx(vertex.x, edge_value):
				if return_vertices:
					verts.append(vertex)
				else:
					verts.append(i)
		elif axis == "z":
			if is_equal_approx(vertex.z, edge_value):
				if return_vertices:
					verts.append(vertex)
				else:
					verts.append(i)
					
	return verts
#endregion
