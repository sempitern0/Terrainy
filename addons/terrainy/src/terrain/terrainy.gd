@tool
class_name Terrainy extends Node

signal terrain_generation_finished(terrains: Dictionary[MeshInstance3D, TerrainConfiguration])

@export var button_Generate_Terrains: String
@export var terrains: Dictionary[MeshInstance3D, TerrainConfiguration]= {}
@export var terrain_spawn_node: Node3D
@export_category("Navigation region")
@export var nav_source_group_name: StringName = &"terrain_navigation_source"
## This navigation needs to set the value Source Geometry -> Group Explicit
@export var navigation_region: NavigationRegion3D
## This will create a NavigationRegion3D automatically with the correct parameters
@export var create_navigation_region_in_runtime: bool = false
@export var bake_navigation_region_in_runtime: bool = false

var thread: Thread
var pending_terrain_surfaces: Dictionary[MeshInstance3D, SurfaceTool] = {}
var pending_terrains: Dictionary[MeshInstance3D, TerrainConfiguration] = {}

var _threads: Array[Thread] = []
var _started_count: int = 0
var _finished_count: int = 0


func generate_procedural_grid(size: Vector2i, config_template: TerrainConfiguration, spawn_node: Node3D = terrain_spawn_node):
	var generated_terrains: Dictionary[MeshInstance3D, TerrainConfiguration] = {}
	
	if spawn_node == null:
		spawn_node = get_parent()
	
	for z: int in size.y:
		for x: int in size.x:
			var configuration: TerrainNoiseConfiguration = config_template.duplicate()
			var terrain_instance: MeshInstance3D = prepare_procedural_terrain(Vector2i(x, z), configuration, spawn_node)
			generated_terrains[terrain_instance] = configuration
	
	generate_terrains(generated_terrains, spawn_node, true)
	

func prepare_procedural_terrain(grid_position: Vector2i,  terrain_configuration: TerrainConfiguration, spawn_node: Node3D) -> MeshInstance3D:
	var terrain_instance: MeshInstance3D = MeshInstance3D.new()
	
	terrain_configuration.world_offset = Vector2(
		grid_position.x * terrain_configuration.size_width, 
		grid_position.y * terrain_configuration.size_depth
		)
	
	terrain_instance.name = "Terrain_%d_%d" % [grid_position.x, grid_position.y]
	terrain_instance.set_meta(&"grid_position", Vector2i(grid_position))
	
	terrain_instance.tree_entered.connect(
		func():
			terrain_instance.global_position = Vector3(
				grid_position.x * terrain_configuration.size_width, 
				0,
				grid_position.y * terrain_configuration.size_depth
			)
			, CONNECT_ONE_SHOT)

	terrain_instance.set_meta(&"procedural", true)
	TerrainBuilder.add_to_grid_group(terrain_instance)
	
	return terrain_instance


func generate_terrains(
	selected_terrains: Dictionary[MeshInstance3D, TerrainConfiguration] = {},
	 spawn_node: Node3D = terrain_spawn_node, 
	procedural: bool = false) -> void:
		
	_threads.clear()
	_started_count = 0
	_finished_count = 0
	
	if selected_terrains.is_empty():
		push_warning("Terrainy->generate_terrains: This node needs at least one TerrainConfiguration to start the generation, aborting...")
		return
	
	for terrain_mesh in selected_terrains:
		if not terrain_mesh.has_meta(&"procedural"):
			terrain_mesh.set_meta(&"procedural", procedural)
		
		var th: Thread = Thread.new()
		_threads.append(th)
		_started_count += 1
		
		var err: Error = th.start(_terrain_worker.bind(terrain_mesh, selected_terrains[terrain_mesh], spawn_node))
		
		if err != OK:
			push_error("Terrainy->generate_terrains: Could not start thread for %s (err %d | )" % [terrain_mesh.name, err, error_string(err)])
			_started_count -= 1
			_threads.pop_back()
		else:
			print("Terrainy: Terrain generation thread started for %s" % [terrain_mesh.name])


func generate_terrain(terrain_mesh: MeshInstance3D, terrain_configuration: TerrainConfiguration, spawn_node: Node3D = terrain_spawn_node) -> void:
	if terrain_mesh == null or not is_instance_valid(terrain_mesh):
		push_warning("Terrainy->generate_terrain: This node needs a valid MeshInstance3D to create the terrain, aborting...")
		return
		
	elif terrain_configuration is TerrainNoiseConfiguration and not terrain_configuration.noise:
		push_warning("Terrainy->generate_terrain: %s, TerrainNoiseConfiguration needs a valid FastNoiseLite assigned." % terrain_mesh.name)
		return
	
	elif terrain_configuration is TerrainNoiseTextureConfiguration and not terrain_configuration.noise_texture:
		push_warning("Terrainy->generate_terrain: %s, TerrainNoiseTextureConfiguration needs a valid noise Texture2D assigned." % terrain_mesh.name)
		return
	elif terrain_configuration is TerrainHeightmapConfiguration and not terrain_configuration.heightmap_image:
		push_warning("Terrainy->generate_terrain:  %s, TerrainHeightmapConfiguration needs a valid heightmap Texture2D assigned." % terrain_mesh.name)
		return
	
	if terrain_mesh.is_inside_tree():
		call_thread_safe("_free_children", terrain_mesh)
	else:
		spawn_node.call_deferred("add_child", terrain_mesh)

	call_deferred_thread_group("_set_owner_to_edited_scene_root", terrain_mesh)
	call_deferred_thread_group("create_surface", terrain_mesh, terrain_configuration)
	call_deferred_thread_group("_terrain_worker_done", terrain_mesh)

	
func create_surface(terrain: MeshInstance3D, terrain_configuration: TerrainConfiguration) -> void:
	var surface: SurfaceTool = TerrainBuilder.generate_surface(terrain, terrain_configuration)
	
	if surface == null:
		printerr("Terrainy->create_surface: The surface created for %s is null, an error happened in the process." % terrain.name)
		return
		
	pending_terrain_surfaces[terrain] = surface
	pending_terrains[terrain] = terrain_configuration
	
	terrain.mesh = surface.commit()


func create_navigation_region(selected_navigation_region: NavigationRegion3D = navigation_region) -> void:
	if selected_navigation_region == null:
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

	
#region Thread related
func _finalize_threads() -> void:
	print("Terrainy: All threads finished, finalizing (%d threads)..." % _threads.size())

	for th in _threads:
		th.wait_to_finish()
		
	_threads.clear()
#	
	for terrain_mesh: MeshInstance3D in pending_terrains:
		var terrain_configuration: TerrainConfiguration = pending_terrains[terrain_mesh]
		
		terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		TerrainBuilder.add_to_group(terrain_mesh)
		
		if not terrain_mesh.get_meta(&"procedural"):
			TerrainBuilder.center_terrain_mesh_to_node_world_position_y(terrain_mesh)
	
		if terrain_configuration.generate_collision:
			TerrainBuilder.regenerate_terrain_collision(terrain_mesh)
		
		if terrain_configuration.generate_mirror:
			var mirror_terrain: MeshInstance3D = TerrainBuilder.create_mirrored_terrain(terrain_mesh, terrain_configuration)
			
			terrain_mesh.call_deferred("add_child", mirror_terrain)
			call_deferred("_set_owner_to_edited_scene_root", mirror_terrain)
			
			mirror_terrain.set_deferred("global_transform", terrain_mesh.global_transform)
			
			if terrain_configuration.generate_mirror_collision:
				TerrainBuilder.regenerate_terrain_collision(mirror_terrain)
				
			TerrainBuilder.add_to_mirror_group(mirror_terrain)
			
			if create_navigation_region_in_runtime:
				create_navigation_region(navigation_region)
				
				
	terrain_generation_finished.emit(pending_terrains)
	pending_terrain_surfaces.clear()
	pending_terrains.clear()
	
	print("Terrainy: Generation complete.")


func _terrain_worker(target_mesh: MeshInstance3D, terrain_configuration: TerrainConfiguration, spawn_node: Node3D = terrain_spawn_node) -> void:
	if target_mesh == null or not is_instance_valid(target_mesh):
		push_warning("Terrainy->_terrain_worker: This node needs a valid MeshInstance3D to create the terrain, aborting...")
		return
		
	call_thread_safe("generate_terrain", target_mesh, terrain_configuration, spawn_node)


func _terrain_worker_done(terrain: MeshInstance3D) -> void:
	_finished_count += 1
	
	if _finished_count >= _started_count:
		_finalize_threads()
		
		
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
		"Generate Terrains":
			generate_terrains(terrains)
#endregion
