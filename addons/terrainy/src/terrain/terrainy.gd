@tool
class_name Terrainy extends Node

signal terrain_generation_finished

@export var button_Generate_Terrain: String
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var terrains: Array[Terrain] = []
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
	if terrains.is_empty():
		push_warning("Terrainy->generate_terrains: This node needs at least one Terrain to start the generation, aborting...")
		return
	
	if not terrain_generation_finished.is_connected(on_terrain_generation_finished):
		terrain_generation_finished.connect(on_terrain_generation_finished)
		
	pending_terrain_surfaces.clear()
	
	print("Terrainy: Generating a total of %d terrains..." % terrains.size())
	
	var terrain_task_id: int = WorkerThreadPool.add_group_task(process_terrain_generation, terrains.size())
	WorkerThreadPool.wait_for_group_task_completion(terrain_task_id)


func process_terrain_generation(index: int) -> void:
	generate_terrain(terrains[index])
	

func generate_terrain(terrain: Terrain) -> void:
	if terrain == null or not is_instance_valid(terrain):
		push_warning("Terrainy->generate_terrain: This node needs a valid Terrain to create the terrain, aborting...")
		return
	
	
	if not terrain.has_noise_available():
		push_warning("Terrainy->generate_terrain: This node needs a noise value or noise texture to create the terrain, aborting generation...")
		return
		
	call_thread_safe("_set_owner_to_edited_scene_root", terrain)
	call_thread_safe("_free_children", terrain)
	
	var plane_mesh = PlaneMesh.new()
	call_thread_safe("set_terrain_size_on_plane_mesh", terrain.configuration, plane_mesh)
	terrain.set_deferred_thread_group("mesh", plane_mesh)

	call_thread_safe("create_surface", terrain)
	

func create_surface(terrain: Terrain) -> void:
	var surface = SurfaceTool.new()
	var mesh_data_tool = MeshDataTool.new()
	
	surface.create_from(terrain.mesh, 0)
#
	var array_mesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	if terrain.configuration.noise:
		if terrain.configuration.randomize_noise_seed:
			terrain.configuration.noise.seed = randi()
			
		call_thread_safe("generate_heightmap_with_noise", terrain.configuration, mesh_data_tool)
	elif terrain.configuration.noise_texture:
		call_thread_safe("generate_heightmap_with_noise_texture", terrain.configuration, mesh_data_tool)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	pending_terrain_surfaces.append(surface)
	
	if pending_terrain_surfaces.size() == terrains.size():
		call_deferred_thread_group("emit_signal", "terrain_generation_finished")


func generate_heightmap_with_noise(configuration: TerrainConfiguration, mesh_data_tool: MeshDataTool) -> void:
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## Convert to a range of 0 ~ 1 instead of -1 ~ 1
		var noise_y: float = TerrainyCore.get_noise_y_normalized(configuration.noise, vertex)
		noise_y = apply_elevation_curve (configuration, noise_y)
		var falloff = calculate_falloff(configuration, vertex)
		
		vertex.y = noise_y * configuration.max_terrain_height * falloff
		
		if configuration.radial_shape:
			var radius_x: float = configuration.size_width * 0.5
			var radius_z: float = configuration.size_depth * 0.5
			var dist: float = Vector2(vertex.x / radius_x, vertex.z / radius_z).length()
			var radial_mask: float = clampf(1.0 - pow(dist, configuration.radial_falloff_power), 0.0, 1.0)
			
			vertex.y *= radial_mask

		mesh_data_tool.set_vertex(vertex_idx, vertex)

	
func generate_heightmap_with_noise_texture(configuration: TerrainConfiguration, mesh_data_tool: MeshDataTool) -> void:
	var noise_image: Image = configuration.noise_texture.get_image()
	var width: int = noise_image.get_width()
	var height: int = noise_image.get_height()
	
	## To avoid the error "cannot get_pixel on compressed image"
	if noise_image.is_compressed():
		noise_image.decompress()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		var falloff = calculate_falloff(configuration, vertex)
		vertex.y = apply_elevation_curve(configuration, noise_image.get_pixel(x, z).r)
		vertex.y *= configuration.max_terrain_height * falloff

		if configuration.radial_shape:
			var radius_x: float = configuration.size_width * 0.5
			var radius_z: float = configuration.size_depth * 0.5
			var dist: float = Vector2(vertex.x / radius_x, vertex.z / radius_z).length()
			# falloff radial 0..1, 1 centro, 0 borde
			var radial_mask: float = clampf(1.0 - pow(dist, configuration.radial_falloff_power), 0.0, 1.0)
			vertex.y *= radial_mask
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func calculate_falloff(configuration: TerrainConfiguration, vertex: Vector3) -> float:
	var falloff: float = 1.0
	
	if configuration.falloff_texture:
		var falloff_image: Image = configuration.falloff_texture.get_image()
		
		## To avoid the error "cannot get_pixel on compressed image"
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


#func generate_side_terrain(origin_terrain: MeshInstance3D, new_terrain: MeshInstance3D, direction: Vector3) -> void:
	## --- Validaciones ---
	#if origin_terrain == null or origin_terrain.mesh == null:
		#push_error("generate_side_terrain: origin_terrain is invalid or has no mesh.")
		#return
	#if new_terrain == null or new_terrain.mesh == null:
		#push_error("generate_side_terrain: new_terrain is invalid or has no mesh.")
		#return
	#if origin_terrain.mesh.get_surface_count() == 0 or new_terrain.mesh.get_surface_count() == 0:
		#push_error("generate_side_terrain: One of the meshes has no surfaces.")
		#return
#
	## --- Obtener configuración base ---
	#var origin_conf: TerrainConfiguration = terrain_meshes.get(origin_terrain, null)
	#var new_conf: TerrainConfiguration = terrain_meshes.get(new_terrain, null)
	#if origin_conf == null or new_conf == null:
		#push_error("generate_side_terrain: Missing TerrainConfiguration for one of the terrains.")
		#return
#
	#var width := origin_conf.size_width
	#var depth := origin_conf.size_depth
	#var resolution := origin_conf.mesh_resolution
#
	## --- Calcular offset del nuevo terreno según la dirección ---
	#var offset_local := Vector3.ZERO
	#if abs(direction.x) > abs(direction.z):
		## movimiento en eje X (derecha/izquierda)
		#offset_local.x = sign(direction.x) * width
	#elif abs(direction.z) > abs(direction.x):
		## movimiento en eje Z (frontal/trasero)
		#offset_local.z = sign(direction.z) * depth
#
	#var offset_global := origin_terrain.global_transform.basis * offset_local
	#new_terrain.global_position = origin_terrain.global_position + offset_global
#
	## --- Crear MeshDataTools seguros ---
	#var origin_st := SurfaceTool.new()
	#origin_st.create_from(origin_terrain.mesh, 0)
	#var origin_mesh := origin_st.commit()
	#var origin_mdt := MeshDataTool.new()
	#origin_mdt.create_from_surface(origin_mesh, 0)
#
	#var new_st := SurfaceTool.new()
	#new_st.create_from(new_terrain.mesh, 0)
	#var new_mesh := new_st.commit()
	#var new_mdt := MeshDataTool.new()
	#new_mdt.create_from_surface(new_mesh, 0)
#
	## --- Determinar los bordes a encajar ---
	#var match_axis := Vector2.ZERO
	#var origin_edge := []
	#var new_edge := []
#
	#if abs(direction.x) > abs(direction.z):
		## Encajar bordes izquierdo/derecho
		#match_axis = Vector2(1, 0)
		#if direction.x > 0:
			## Nuevo terreno a la derecha -> usar borde +X del original y borde -X del nuevo
			#origin_edge = _get_edge_vertices(origin_mdt, width * 0.5, "x", true)
			#new_edge = _get_edge_vertices(new_mdt, -width * 0.5, "x", false)
		#else:
			## Nuevo terreno a la izquierda -> usar borde -X del original y borde +X del nuevo
			#origin_edge = _get_edge_vertices(origin_mdt, -width * 0.5, "x", true)
			#new_edge = _get_edge_vertices(new_mdt, width * 0.5, "x", false)
	#else:
		## Encajar bordes frontal/trasero
		#match_axis = Vector2(0, 1)
		#if direction.z > 0:
			## Nuevo al fondo -> borde +Z del original y borde -Z del nuevo
			#origin_edge = _get_edge_vertices(origin_mdt, depth * 0.5, "z", true)
			#new_edge = _get_edge_vertices(new_mdt, -depth * 0.5, "z", false)
		#else:
			## Nuevo al frente -> borde -Z del original y borde +Z del nuevo
			#origin_edge = _get_edge_vertices(origin_mdt, -depth * 0.5, "z", true)
			#new_edge = _get_edge_vertices(new_mdt, depth * 0.5, "z", false)
#
	## --- Aplicar alturas del borde del original sobre el nuevo ---
	#if origin_edge.size() == new_edge.size():
		#for i in range(origin_edge.size()):
			#var origin_v = origin_edge[i]
			#var new_idx = new_edge[i]
			#var new_v := new_mdt.get_vertex(new_idx)
			#new_v.y = origin_v.y
			#new_mdt.set_vertex(new_idx, new_v)
			#
	#var blend_width := 3  
	#var blend_axis := ""
	#var sign_dir := 1.0
#
	#if abs(direction.x) > abs(direction.z):
		#blend_axis = "x"
		#sign_dir = sign(direction.x)
	#else:
		#blend_axis = "z"
		#sign_dir = sign(direction.z)
#
	#for i in range(new_mdt.get_vertex_count()):
		#var v := new_mdt.get_vertex(i)
		#var distance_from_edge := 0.0
#
		#if blend_axis == "x":
			## distancia desde el borde de encaje en coordenadas locales
			#var edge_pos = (-width * 0.5) if (sign_dir > 0) else (width * 0.5)
			#distance_from_edge = abs(v.x - edge_pos) / (width / float(resolution))
		#else:
			#var edge_pos = (-depth * 0.5) if (sign_dir > 0) else (depth * 0.5)
			#distance_from_edge = abs(v.z - edge_pos) / (depth / float(resolution))
#
		## dentro del rango de mezcla
		#if distance_from_edge > 0 and distance_from_edge <= blend_width:
			#var t := 1.0 - (distance_from_edge / float(blend_width))
			## tomar el vértice del borde más cercano
			#var nearest_edge_height := 0.0
			#if origin_edge.size() > 0:
				## usamos el primer vértice del borde para referencia media
				#var avg_height := 0.0
				#for e in origin_edge:
					#avg_height += e.y
				#nearest_edge_height = avg_height / float(origin_edge.size())
#
			## mezclar altura con el borde
			#v.y = lerp(v.y, nearest_edge_height, t * 0.5)
			#new_mdt.set_vertex(i, v)
#
	## --- Commit final ---
	#new_mesh.clear_surfaces()
	#new_mdt.commit_to_surface(new_mesh)
#
	#var st_final := SurfaceTool.new()
	#st_final.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st_final.create_from(new_mesh, 0)
	#st_final.generate_normals()
	#st_final.generate_tangents()
	#new_terrain.mesh = st_final.commit()
#
	#print("Side terrain generated successfully and aligned with direction ", direction)
	#
#

func on_terrain_generation_finished() -> void:
	print("Terrainy: Generation of %d terrain meshes is finished! " % terrains.size())
	
	for i in pending_terrain_surfaces.size():
		var terrain: Terrain = terrains[i]
	
		terrain.mesh = pending_terrain_surfaces[i].commit() 
		terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain.add_to_group(nav_source_group_name)
		
		if terrain.configuration.generate_mirror:
			var terrain_mirror: Terrain = TerrainyCore.create_mirrored_terrain(terrain)
			
			if terrain_mirror:
				terrain.call_thread_safe("add_child", terrain_mirror)
				call_thread_safe("_set_owner_to_edited_scene_root", terrain_mirror)
				
				generate_collisions(terrain.configuration.mirror_collision_type, terrain_mirror)
				
		generate_collisions(terrain.configuration.collision_type, terrain)
		
	create_navigation_region(navigation_region)


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


func _get_edge_vertices(mdt: MeshDataTool, edge_value: float, axis: String, return_vertices: bool = false) -> Array[Vector3]:
	var verts: Array[Vector3] = []
	
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
