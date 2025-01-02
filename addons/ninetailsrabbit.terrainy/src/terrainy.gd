@tool
extends Node

signal terrain_generation_finished

@export var button_Generate_Terrain: String
@export_category("Terrain")
## When enabled, the trimesh collision is generated for the terrain
@export var generate_collisions: bool = true
## More resolution means more detail (more dense vertex) in the terrain generation, this increases the mesh subdivisions it could reduce the performance in low-spec pcs
@export_range(1, 16, 1) var mesh_resolution: int = 1:
	set(value):
		if value != mesh_resolution:
			mesh_resolution = value
			
## The depth size of the mesh (z) in godot units (meters)
@export var size_depth: int = 100:
	set(value):
		if value != size_depth:
			size_depth = max(1, value)
			
			
## The width size of the mesh (x) in godot units (meters)
@export var size_width: int = 100:
	set(value):
		if value != size_width:
			size_width = max(1, value)
			
## The maximum height this terrain can have
@export var max_terrain_height: float = 50.0:
	set(value):
		if value != max_terrain_height:
			max_terrain_height = maxf(0.5, value)
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var terrain_meshes: Array[MeshInstance3D]:
	set(value):
		if value != terrain_meshes:
			terrain_meshes = value
			update_configuration_warnings()
## The terrain material that will be applied on the surface
@export var terrain_material: Material
@export_category("Noise")
@export var randomize_noise_seed: bool = false
## Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.
## Rocky: +Octaves -Period, Hills: -Octaves +Period
@export var noise: FastNoiseLite:
	set(value):
		if value != noise:
			noise = value
			update_configuration_warnings()
## Use a texture as noise to generate the terrain. If a noise is defined, this texture will be ignored.
@export var noise_texture: CompressedTexture2D:
	set(value):
		if value != noise_texture:
			noise_texture = value
			update_configuration_warnings()
@export var elevation_curve: Curve
## Use an image to smooth the edges on this terrain. Useful if you want to connect other plots of land
@export var falloff_texture: CompressedTexture2D = preload("res://addons/ninetailsrabbit.terrainy/assets/falloff_images/TerrainFalloff.png"):
	set(new_texture):
		if new_texture != falloff_texture:
			falloff_texture = new_texture
			
			if falloff_texture:
				falloff_image = falloff_texture.get_image()
			else:
				falloff_image = null
				
@export_category("Navigation region")
@export var nav_source_group_name: StringName = &"terrain_navigation_source"
## This navigation needs to set the value Source Geometry -> Group Explicit
@export var navigation_region: NavigationRegion3D
## This will create a NavigationRegion3D automatically with the correct parameters
@export var create_navigation_region_in_runtime: bool = false
@export var bake_navigation_region_in_runtime: bool = false


var falloff_image: Image
var thread: Thread
var pending_terrain_surfaces: Array[SurfaceTool] = []


func _get_configuration_warnings():
	var warnings: PackedStringArray = []
	
	if terrain_meshes.is_empty():
		warnings.append("Terrainy: No target mesh found. Expected at least one MeshInstance3D")
	
	if noise == null and noise_texture == null:
		warnings.append("Terrainy: No noise found. Expected a FastNoiseLite or a Texture2D that represents a grayscale noise")
		
	return warnings
	

func _ready() -> void:
	if falloff_texture:
		falloff_image = falloff_texture.get_image()
	
	if not Engine.is_editor_hint():
		generate_terrains()
		

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
	generate_terrain(terrain_meshes[index])
	

func generate_terrain(selected_mesh: MeshInstance3D) -> void:
	if selected_mesh == null:
		push_warning("Terrainy: This node needs a selected_mesh to create the terrain, aborting generation...")
		return
	
	if noise == null and noise_texture == null:
		push_warning("Terrainy: This node needs a noise value or noise texture to create the terrain, aborting generation...")
		return
		
	call_thread_safe("_set_owner_to_edited_scene_root", selected_mesh)
	call_thread_safe("_free_children", selected_mesh)
	
	var plane_mesh = PlaneMesh.new()
	call_thread_safe("set_terrain_size_on_plane_mesh", plane_mesh)
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
#
	if noise is FastNoiseLite and noise_texture == null:
		if randomize_noise_seed:
			noise.seed = randi()
			
		call_thread_safe("generate_heightmap_with_noise", noise, mesh_data_tool)
	elif noise == null and noise_texture is CompressedTexture2D:
		call_thread_safe("generate_heightmap_with_noise_texture", noise_texture, mesh_data_tool)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	
	pending_terrain_surfaces.append(surface)
	
	if pending_terrain_surfaces.size() == terrain_meshes.size():
		call_deferred_thread_group("emit_signal", "terrain_generation_finished")


func generate_heightmap_with_noise(selected_noise: FastNoiseLite, mesh_data_tool: MeshDataTool) -> void:
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## Convert to a range of 0 ~ 1 instead of -1 ~ 1
		var noise_y: float = get_noise_y(selected_noise, vertex)
		noise_y = apply_elevation_curve (noise_y)
		var falloff = calculate_falloff(vertex)
		
		vertex.y = noise_y * max_terrain_height * falloff
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func get_noise_y(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return (selected_noise.get_noise_2d(vertex.x, vertex.z) + 1) / 2
	
	
func generate_heightmap_with_noise_texture(selected_texture: CompressedTexture2D, mesh_data_tool: MeshDataTool) -> void:
	var noise_image: Image = selected_texture.get_image()
	var width: int = noise_image.get_width()
	var height: int = noise_image.get_height()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		
		vertex.y = noise_image.get_pixel(x, z).r
		vertex.y = call_thread_safe("apply_elevation_curve", vertex.y)
		
		var falloff = call_thread_safe("calculate_falloff", vertex)
		
		vertex.y *= max_terrain_height * falloff
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func calculate_falloff(vertex: Vector3) -> float:
	var falloff: float = 1.0
	
	if falloff_image:
		var x_percent: float = clampf(((vertex.x + (size_width / 2)) / size_width), 0.0, 1.0)
		var z_percent: float = clampf(((vertex.z + (size_depth / 2)) / size_depth), 0.0, 1.0)
		
		var x_pixel: int = int(x_percent * (falloff_image.get_width() - 1))
		var y_pixel: int = int(z_percent * (falloff_image.get_height() - 1))
		
		# In this case we can go for any channel (r,g b) as the colors are the same
		falloff = falloff_image.get_pixel(x_pixel, y_pixel).r
		
	return falloff
	

func apply_elevation_curve(noise_y: float) -> float:
	if elevation_curve:
		noise_y = elevation_curve.sample(noise_y)
		
	return noise_y


func set_terrain_size_on_plane_mesh(plane_mesh: PlaneMesh) -> void:
	plane_mesh.size = Vector2(size_width, size_depth)
	plane_mesh.subdivide_depth = size_depth * mesh_resolution
	plane_mesh.subdivide_width = size_width * mesh_resolution
	plane_mesh.material = terrain_material


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
		var terrain_mesh: MeshInstance3D = terrain_meshes[i]
		terrain_mesh.mesh = pending_terrain_surfaces[i].commit() 
	
		if generate_collisions:
			terrain_mesh.create_trimesh_collision()
			
		terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_mesh.add_to_group(nav_source_group_name)
	
	create_navigation_region(navigation_region)
	
#endregion
