@tool
class_name Terrainy extends Node

signal terrain_generation_finished

@export var button_Generate_Terrain: String
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var terrain_meshes: Dictionary[MeshInstance3D, TerrainConfiguration]
@export_category("Navigation region")
@export var nav_source_group_name: StringName = &"terrain_navigation_source"
## This navigation needs to set the value Source Geometry -> Group Explicit
@export var navigation_region: NavigationRegion3D
## This will create a NavigationRegion3D automatically with the correct parameters
@export var create_navigation_region_in_runtime: bool = false
@export var bake_navigation_region_in_runtime: bool = false

var thread: Thread
var pending_terrain_surfaces: Array[SurfaceTool] = []


func generate_terrains() -> void:
	if terrain_meshes.is_empty():
		push_warning("Terrainy: This node needs at least one mesh to create the terrain, aborting generation...")
		return
	
	if not terrain_generation_finished.is_connected(on_terrain_generation_finished):
		terrain_generation_finished.connect(on_terrain_generation_finished)
		
	pending_terrain_surfaces.clear()
	
	print("Terrainy: Generating terrains...")
	
	var terrain_task_id: int = WorkerThreadPool.add_group_task(process_terrain_generation, terrain_meshes.size())
	WorkerThreadPool.wait_for_group_task_completion(terrain_task_id)


func process_terrain_generation(index: int) -> void:
	var terrain_mesh: MeshInstance3D = terrain_meshes.keys()[index]
	generate_terrain(terrain_mesh)
	

func generate_terrain(selected_mesh: MeshInstance3D) -> void:
	if selected_mesh == null or not is_instance_valid(selected_mesh):
		push_warning("Terrainy: This node needs a valid MeshInstance3D to create the terrain, aborting generation...")
		return
	
	var configuration: TerrainConfiguration = terrain_meshes[selected_mesh]
	
	if configuration.noise == null and configuration.noise_texture == null:
		push_warning("Terrainy: This node needs a noise value or noise texture to create the terrain, aborting generation...")
		return
		
	call_thread_safe("_set_owner_to_edited_scene_root", selected_mesh)
	call_thread_safe("_free_children", selected_mesh)
	
	var plane_mesh = PlaneMesh.new()
	call_thread_safe("set_terrain_size_on_plane_mesh", configuration, plane_mesh)
	selected_mesh.set_deferred_thread_group("mesh", plane_mesh)

	call_thread_safe("create_surface", selected_mesh)


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


func create_surface(mesh_instance: MeshInstance3D) -> void:
	var surface = SurfaceTool.new()
	var mesh_data_tool = MeshDataTool.new()
	
	surface.create_from(mesh_instance.mesh, 0)
#
	var array_mesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	var configuration: TerrainConfiguration = terrain_meshes[mesh_instance]

	if configuration.noise is FastNoiseLite and configuration.noise_texture == null:
		if configuration.randomize_noise_seed:
			configuration.noise.seed = randi()
			
		call_thread_safe("generate_heightmap_with_noise", configuration, mesh_data_tool)
	elif configuration.noise == null and configuration.noise_texture is CompressedTexture2D:
		call_thread_safe("generate_heightmap_with_noise_texture", configuration, mesh_data_tool)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	pending_terrain_surfaces.append(surface)
	
	if pending_terrain_surfaces.size() == terrain_meshes.size():
		call_deferred_thread_group("emit_signal", "terrain_generation_finished")


func generate_heightmap_with_noise(configuration: TerrainConfiguration, mesh_data_tool: MeshDataTool) -> void:
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## Convert to a range of 0 ~ 1 instead of -1 ~ 1
		var noise_y: float = TerrainyCore.get_noise_y_normalized(configuration.noise, vertex)
		noise_y = apply_elevation_curve (configuration, noise_y)
		var falloff = calculate_falloff(configuration, vertex)
		
		vertex.y = noise_y * configuration.max_terrain_height * falloff
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)

	
func generate_heightmap_with_noise_texture(configuration: TerrainConfiguration, mesh_data_tool: MeshDataTool) -> void:
	var noise_image: Image = configuration.noise_texture.get_image()
	var width: int = noise_image.get_width()
	var height: int = noise_image.get_height()
	
	## To avoid the error cannot get_pixel on compressed image
	if noise_image.is_compressed():
		noise_image.decompress()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		
		vertex.y = apply_elevation_curve(configuration, noise_image.get_pixel(x, z).r)
		vertex.y *= configuration.max_terrain_height * calculate_falloff(configuration, vertex)
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func calculate_falloff(configuration: TerrainConfiguration, vertex: Vector3) -> float:
	var falloff: float = 1.0
	
	if configuration.falloff_texture:
		var falloff_image: Image = configuration.falloff_texture.get_image()
		
		if falloff_image.is_compressed():
			falloff_image.decompress()
			
		var x_percent: float = clampf(((vertex.x + (configuration.size_width / 2)) / configuration.size_width), 0.0, 1.0)
		var z_percent: float = clampf(((vertex.z + (configuration.size_depth / 2)) / configuration.size_depth), 0.0, 1.0)
		
		var x_pixel: int = int(x_percent * (falloff_image.get_width() - 1))
		var y_pixel: int = int(z_percent * (falloff_image.get_height() - 1))
		
		# In this case we can go for any channel (r,g b) as the colors are the same
		falloff = falloff_image.get_pixel(x_pixel, y_pixel).r
		
	return falloff
	

func apply_elevation_curve(configuration: TerrainConfiguration, noise_y: float) -> float:
	if configuration.elevation_curve:
		noise_y = configuration.elevation_curve.sample(noise_y)
	
	return noise_y


func set_terrain_size_on_plane_mesh(configuration: TerrainConfiguration, plane_mesh: PlaneMesh) -> void:
	plane_mesh.size = Vector2(configuration.size_width, configuration.size_depth)
	plane_mesh.subdivide_depth = configuration.mesh_resolution
	plane_mesh.subdivide_width = configuration.mesh_resolution
	plane_mesh.material = configuration.terrain_material


func generate_collisions(configuration: TerrainConfiguration, terrain_mesh: MeshInstance3D) -> void:
	if configuration.collision_type == TerrainyCore.CollisionType.Trimesh:
		terrain_mesh.create_trimesh_collision()
	elif configuration.collision_type == TerrainyCore.CollisionType.ConcavePolygon:
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
			generate_terrains()


func on_terrain_generation_finished() -> void:
	print("Terrainy: Generation of %d terrain meshes is finished! " % terrain_meshes.size())
	
	for i in pending_terrain_surfaces.size():
		var terrain_mesh: MeshInstance3D = terrain_meshes.keys()[i]
		terrain_mesh.mesh = pending_terrain_surfaces[i].commit() 
	
		generate_collisions(terrain_meshes[terrain_mesh], terrain_mesh)
		
		terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_mesh.add_to_group(nav_source_group_name)
		
		if terrain_meshes[terrain_mesh].generate_mirror:
			var mirror_instance: MeshInstance3D = TerrainyCore.create_mirrored_terrain(terrain_mesh, terrain_meshes[terrain_mesh])
			
			if mirror_instance:
				terrain_mesh.call_thread_safe("add_child", mirror_instance)
				call_thread_safe("_set_owner_to_edited_scene_root", mirror_instance)
				
	create_navigation_region(navigation_region)

#endregion
