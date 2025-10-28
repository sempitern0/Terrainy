class_name TerrainBuilder

const DefaultTerrainMaterial: StandardMaterial3D = preload("uid://dnlh6yw1dkew1")
const DefaultMirrorTerrainMaterial: StandardMaterial3D = preload("uid://8ku0pjn8b0p3")
const DefaultMirrorNoise: FastNoiseLite = preload("uid://d0fdf4fw86ijk")

const GroupName: StringName = &"terrains"
const MirrorGroupName: StringName = &"mirror_terrains"
const GridGroupName: StringName = &"grid_terrains"


static func add_to_group(terrain_mesh: MeshInstance3D) -> void:
	if not terrain_mesh.is_in_group(GroupName):
		terrain_mesh.add_to_group(GroupName)
	
	
static func add_to_mirror_group(terrain_mesh: MeshInstance3D) -> void:
	if not terrain_mesh.is_in_group(MirrorGroupName):
		terrain_mesh.add_to_group(MirrorGroupName)
	
	
static func add_to_grid_group(terrain_mesh: MeshInstance3D) -> void:
	if not terrain_mesh.is_in_group(GridGroupName):
		terrain_mesh.add_to_group(GridGroupName)
	
	
static func generate_surface(target_mesh: MeshInstance3D, terrain_configuration: TerrainConfiguration) -> SurfaceTool:
	if not is_instance_valid(target_mesh):
		printerr("TerrainBuilder->generate_surface: The target mesh %s is not valid" % target_mesh.name)
		return null
		
	if terrain_configuration == null:
		printerr("TerrainBuilder->generate_surface: The terrain configuration is null for the mesh %s " % target_mesh.name)
		return null
	
	if terrain_configuration is TerrainNoiseConfiguration:
		return generate_noise_surface(target_mesh, terrain_configuration)
	elif terrain_configuration is TerrainNoiseTextureConfiguration:
		return generate_noise_texture_surface(target_mesh, terrain_configuration)
	elif terrain_configuration is TerrainHeightmapConfiguration:
		return generate_heightmap_surface(target_mesh, terrain_configuration)

	return null
	
	
static func generate_noise_surface(target_mesh: MeshInstance3D, terrain_configuration: TerrainNoiseConfiguration) -> SurfaceTool:
	if not is_instance_valid(target_mesh):
		printerr("TerrainBuilder->generate_noise_surface: The target mesh %s is not valid" % target_mesh.name)
		return
		
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh_data_tool: MeshDataTool = MeshDataTool.new()
	
	surface.create_from(create_plane_mesh(terrain_configuration), 0)
#
	var array_mesh: ArrayMesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	if terrain_configuration.randomize_noise_seed:
		terrain_configuration.noise.seed = randi()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## Convert to a range of 0 ~ 1 instead of -1 ~ 1
		var noise_y: float = get_noise_y_normalized(terrain_configuration.noise, vertex, terrain_configuration.world_offset)
		
		if terrain_configuration.use_elevation_curve and terrain_configuration.elevation_curve:
			if terrain_configuration.allow_negative_elevation_values:
				var uv_height_factor = clampf(((vertex.x + vertex.z) / (terrain_configuration.size_depth * 2.0)) * 0.5 + 0.5, 0.0, 1.0)
				vertex.y = clampf(vertex.y, -terrain_configuration.max_terrain_height, terrain_configuration.max_terrain_height)
				
				noise_y = terrain_configuration.noise.get_noise_2d(vertex.x + terrain_configuration.world_offset.x, vertex.z + terrain_configuration.world_offset.y) \
					* apply_elevation_curve(terrain_configuration, uv_height_factor) \
					* terrain_configuration.max_terrain_height
			else:
				noise_y = apply_elevation_curve(terrain_configuration, noise_y)
			
		var falloff: float = calculate_falloff(terrain_configuration, vertex)
		
		vertex.y = noise_y * terrain_configuration.max_terrain_height * falloff
		vertex.y *= apply_radial_shape_on_vertex(terrain_configuration, vertex)

		mesh_data_tool.set_vertex(vertex_idx, vertex)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()

	return surface


static func generate_noise_texture_surface(target_mesh: MeshInstance3D, terrain_configuration: TerrainNoiseTextureConfiguration) -> SurfaceTool:
	if not is_instance_valid(target_mesh):
		printerr("TerrainBuilder->generate_noise_texture_surface: The target mesh %s is not valid" % target_mesh.name)
		return
		
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh_data_tool: MeshDataTool = MeshDataTool.new()
	
	surface.create_from(create_plane_mesh(terrain_configuration), 0)
#
	var array_mesh: ArrayMesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	var noise_image: Image = terrain_configuration.noise_texture.get_image()
	var width: int = noise_image.get_width()
	var height: int = noise_image.get_height()
	
	## To avoid the error "cannot get_pixel on compressed image"
	if noise_image.is_compressed():
		noise_image.decompress()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x: float = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z: float = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		var falloff: float = calculate_falloff(terrain_configuration, vertex)
		vertex.y = noise_image.get_pixel(x, z).r
		
		if terrain_configuration.use_elevation_curve and terrain_configuration.elevation_curve:
			
			if terrain_configuration.allow_negative_elevation_values:
				var uv_height_factor = clampf(((vertex.x + vertex.z) / (terrain_configuration.size_depth * 2.0)) * 0.5 + 0.5, 0.0, 1.0)
				vertex.y *= apply_elevation_curve(terrain_configuration, uv_height_factor) * terrain_configuration.max_terrain_height
				vertex.y = clampf(vertex.y, -terrain_configuration.max_terrain_height, terrain_configuration.max_terrain_height)
			else:
				vertex.y *= apply_elevation_curve(terrain_configuration, vertex.y)
		
		vertex.y *= terrain_configuration.max_terrain_height * falloff
		vertex.y *= apply_radial_shape_on_vertex(terrain_configuration, vertex)
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)

	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	return surface
	

static func generate_heightmap_surface(target_mesh: MeshInstance3D, terrain_configuration: TerrainHeightmapConfiguration) -> SurfaceTool:
	if not is_instance_valid(target_mesh):
		printerr("TerrainBuilder->generate_heightmap_surface: The target mesh %s is not valid" % target_mesh.name)
		return
		
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh_data_tool: MeshDataTool = MeshDataTool.new()
	
	surface.create_from(create_plane_mesh(terrain_configuration), 0)
#
	var array_mesh: ArrayMesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	var heightmap_image: Image = terrain_configuration.heightmap_image.get_image()
	
	## To avoid the error "cannot get_pixel on compressed image"
	if heightmap_image.is_compressed():
		heightmap_image.decompress()
		
	if heightmap_image.get_format() in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		heightmap_image.convert(Image.FORMAT_RF)
	
	var width: int = heightmap_image.get_width()
	var height: int = heightmap_image.get_height()
	var min_v: float = 1.0
	var max_v: float = 0.0
	
	for y in range(height):
		for x in range(width):
			var v: float = heightmap_image.get_pixel(x, y).r
			
			if v < min_v: min_v = v
			if v > max_v: max_v = v

	var range_v: float = max_v - min_v
	
	if range_v <= 0.0001:
		range_v = 1.0  

	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		var x: int = clampi(int(width * (vertex.x / terrain_configuration.size_width + 0.5)), 0, width - 1)
		var z: int = clampi(int(height * (vertex.z / terrain_configuration.size_depth + 0.5)), 0, height - 1)

		var value: float = get_bilinear_height(heightmap_image, x, z)
		
		## To apply a more precise height from this heightmap image
		if terrain_configuration.auto_scale_heightmap_image:
			value = (value - min_v) / range_v
		else:
			value = clampf(value, 0.0, 1.0)
			
		var falloff: float = calculate_falloff(terrain_configuration, vertex)
		
		## Smooth the mountain peaks to not appear so pointed and artificial
		var smoothed_value: float = value - pow(value, 3.0) * 0.2
		
		if smoothed_value > 0.8:
			var soften_factor = 1.0 - (smoothed_value - 0.8) * 2.0
			vertex.y *= clampf(soften_factor, 0.7, 1.0)

		vertex.y = apply_elevation_curve(terrain_configuration, smoothed_value)
		vertex.y *= apply_radial_shape_on_vertex(terrain_configuration, vertex)
		vertex.y *= terrain_configuration.max_terrain_height * falloff

		mesh_data_tool.set_vertex(vertex_idx, vertex)

	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	return surface


static func create_plane_mesh(terrain_configuration: TerrainConfiguration) -> PlaneMesh:
	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(terrain_configuration.size_width, terrain_configuration.size_depth)
	plane_mesh.subdivide_depth = terrain_configuration.mesh_resolution
	plane_mesh.subdivide_width = terrain_configuration.mesh_resolution
	
	if terrain_configuration.terrain_material:
		plane_mesh.material = terrain_configuration.terrain_material
	else:
		plane_mesh.material = TerrainBuilder.DefaultTerrainMaterial
	
	return plane_mesh


static func calculate_falloff(configuration: TerrainConfiguration, vertex: Vector3) -> float:
	var falloff: float = 1.0
	
	if configuration.use_fall_off and configuration.falloff_texture:
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
	

static func apply_elevation_curve(configuration: TerrainConfiguration, noise_y: float) -> float:
	if configuration.elevation_curve:
		noise_y = configuration.elevation_curve.sample(noise_y)
	
	return noise_y


static func apply_radial_shape_on_vertex(configuration: TerrainConfiguration, vertex: Vector3) -> float:
	if configuration.radial_shape:
		var radius_x: float = configuration.size_width * 0.5
		var radius_z: float = configuration.size_depth * 0.5
		var dist: float = Vector2(vertex.x / radius_x, vertex.z / radius_z).length()
		var radial_mask: float = clampf(1.0 - pow(dist, configuration.radial_falloff_power), 0.0, 1.0)
		
		return radial_mask
		
	return 1.0


static func regenerate_terrain_collision(terrain_mesh: MeshInstance3D) -> void:
	for body: StaticBody3D in OmniKitNodeTraversal.find_nodes_of_type(terrain_mesh, StaticBody3D.new()):
		body.queue_free()
		
	terrain_mesh.create_trimesh_collision()


	
static func center_terrain_mesh_to_node_world_position_y(terrain: MeshInstance3D) -> void:
	if terrain == null or terrain.mesh == null:
		return

	var aabb: AABB = terrain.mesh.get_aabb()
	var center_local: Vector3 = aabb.position + aabb.size * 0.5

	var center_world_y: float = terrain.global_transform.origin.y + center_local.y
	var offset_world_y: float = terrain.global_position.y - center_world_y
	var offset_local: Vector3 = terrain.to_local(terrain.global_transform.origin + Vector3(0, offset_world_y, 0)) - terrain.to_local(terrain.global_transform.origin)

	var mdt: MeshDataTool = MeshDataTool.new()
	mdt.create_from_surface(terrain.mesh, 0)
	
	for vertex_index: int in range(mdt.get_vertex_count()):
		var v: Vector3 = mdt.get_vertex(vertex_index)
		v.y += offset_local.y
		mdt.set_vertex(vertex_index, v)

	var out_mesh: ArrayMesh = ArrayMesh.new()
	mdt.commit_to_surface(out_mesh)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from(out_mesh, 0)
	st.generate_normals()
	st.generate_tangents()
	
	terrain.mesh = st.commit()
	
	
static func create_mirrored_terrain(original_terrain: MeshInstance3D, terrain_configuration: TerrainConfiguration) -> MeshInstance3D:
	if not is_instance_valid(original_terrain) or original_terrain.mesh == null:
		printerr("TerrainBuilder->create_mirrored_terrain: The original terrain mesh does not have a valid Mesh assigned, aborting...")
		return null
	
	var source_mesh: Mesh = original_terrain.mesh
	var mirror_array: ArrayMesh = ArrayMesh.new()
	var eps: float = terrain_configuration.mirror_offset
	var depth: float = terrain_configuration.mirror_depth

	var global_center: Vector3 = Vector3.ZERO
	var total_v: int = 0

	for surface in range(source_mesh.get_surface_count()):
		var surface_arrays: Array = source_mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		
		for vertex in verts:
			global_center += vertex
			total_v += 1
		
		if total_v > 0:
			global_center /= total_v

		var indices: PackedInt32Array = surface_arrays[Mesh.ARRAY_INDEX]
		var normals_src = null
		
		if surface_arrays.size() > Mesh.ARRAY_NORMAL and surface_arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			normals_src = surface_arrays[Mesh.ARRAY_NORMAL]
		var uv_src = null
		
		if surface_arrays.size() > Mesh.ARRAY_TEX_UV and surface_arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
			uv_src = surface_arrays[Mesh.ARRAY_TEX_UV]
		
		var top: PackedVector3Array = PackedVector3Array()
		var bottom: PackedVector3Array = PackedVector3Array()

		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			var top_v = Vector3(v.x, v.y - eps, v.z)
			var bottom_v = Vector3(v.x, v.y - depth, v.z)
			top.append(Vector3(v.x, v.y - eps, v.z))
			var n_offset: float
			
			if terrain_configuration.mirror_noise:
				n_offset = terrain_configuration.mirror_noise.get_noise_2d(v.x, v.z) * depth * 0.25
			else:
				var default_mirror_noise: FastNoiseLite = DefaultMirrorNoise.duplicate()
				default_mirror_noise.seed = randi()
				n_offset = default_mirror_noise.get_noise_2d(v.x, v.z) * depth * 0.25
			
			var offset_dir: Vector3 = (normals_src[i] if i < normals_src.size() else Vector3.DOWN).normalized()
			var bottom_pt: Vector3 = v - offset_dir * (depth + n_offset)
		
			bottom.append(bottom_pt)
			
			var t: float = clampf((absf(v.y) / terrain_configuration.max_terrain_height), 0.0, 1.0)
			bottom_v.y = lerpf(top_v.y, bottom_v.y, pow(t, 0.6))
			
		var combined: PackedVector3Array = PackedVector3Array()
		combined.append_array(top)
		combined.append_array(bottom)
		
		var n: int = top.size()
		var combined_uv = null
		
		if uv_src:
			combined_uv = PackedVector2Array()
			combined_uv.append_array(uv_src) 
			combined_uv.append_array(uv_src) 

			var new_indices: PackedInt32Array = PackedInt32Array()
			
			if indices and indices.size() > 0:
				new_indices.append_array(indices)
				
				for i in range(0, indices.size(), 3):
					var a: int = indices[i] + n
					var b: int = indices[i + 1] + n
					var c: int = indices[i + 2] + n
					
					new_indices.append(a)
					new_indices.append(c)
					new_indices.append(b)
			else:
				for i in range(0, verts.size(), 3):
					new_indices.append(i)
					new_indices.append(i + 1)
					new_indices.append(i + 2)
				for i in range(0, verts.size(), 3):
					new_indices.append(i + n)
					new_indices.append(i + 2 + n)
					new_indices.append(i + 1 + n)

			var edge_map: Dictionary = {}
			
			for i in range(0, indices.size(), 3):
				var a: int = indices[i] 
				var b: int = indices[i + 1] 
				var c: int = indices[i + 2]
				
				_add_edge(edge_map, a, b)
				_add_edge(edge_map, b, c)
				_add_edge(edge_map, c, a)

			var local_center: Vector3 = Vector3.ZERO
			
			for v in top:
				local_center += v
			local_center /= float(top.size())

			for key in edge_map.keys():
				var info = edge_map[key]
				
				if info.count == 1:
					var u: int  = info.a
					var v: int  = info.b
					var mid: Vector3 = (top[u] + top[v]) * 0.5
					var to_center: Vector3 = (mid - local_center).normalized()
					var edge_vec: Vector3 = (top[v] - top[u]).normalized()
					var est_normal: Vector3 = edge_vec.cross(Vector3.DOWN).normalized()
					var outward: Vector3 = est_normal
					
					if outward.dot(to_center) < 0:
						outward = -outward

					var a1 := top[v] - top[u]
					var a2 := bottom[u] - top[u]
					var normal_test: Vector3 = a1.cross(a2).normalized()
					var use_order: float = normal_test.dot(outward) > 0

					if use_order:
						new_indices.append(u)
						new_indices.append(v)
						new_indices.append(n + v)

						new_indices.append(u)
						new_indices.append(n + v)
						new_indices.append(n + u)
					else:
						new_indices.append(u)
						new_indices.append(n + v)
						new_indices.append(v)

						new_indices.append(u)
						new_indices.append(n + u)
						new_indices.append(n + v)
	

			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			
			for i in range(0, new_indices.size(), 3):
				for j in range(3):
					var idx := new_indices[i + j]
					if combined_uv:
						st.set_uv(combined_uv[idx])
					if normals_src != null and idx < n:
						st.set_normal(normals_src[idx]) 
					st.add_vertex(combined[idx])
			
			st.generate_normals()
			st.generate_tangents()
			st.commit(mirror_array)

	var mirror_terrain: MeshInstance3D = MeshInstance3D.new()
	mirror_terrain.name = "%sMirror" % original_terrain.name
	mirror_terrain.mesh = mirror_array
	mirror_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	if terrain_configuration.mirror_material:
		terrain_configuration.mirror_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mirror_terrain.mesh.surface_set_material(0, terrain_configuration.mirror_material)
	else:
		mirror_terrain.mesh.surface_set_material(0, DefaultMirrorTerrainMaterial)
			
	return mirror_terrain
	

static func get_noise_y(selected_noise: FastNoiseLite, vertex: Vector3, world_offset: Vector2 = Vector2.ZERO) -> float:
	return selected_noise.get_noise_2d(vertex.x + world_offset.x, vertex.z + world_offset.y)
	

static func get_noise_y_normalized(selected_noise: FastNoiseLite, vertex: Vector3, world_offset: Vector2 = Vector2.ZERO) -> float:
	return (get_noise_y(selected_noise, vertex, world_offset) + 1) / 2

## It takes four neighboring pixels and blends their values based on the vertex’s exact position, 
## creating a smoother transition between each pixel on the map.
## This doesn’t change the overall shape of the terrain, but it softens edges and small height steps.
static func get_bilinear_height(img: Image, x: float, z: float) -> float:
	var ix: int = clampi(int(x), 0, img.get_width() - 2)
	var iz: int = clampi(int(z), 0, img.get_height() - 2)
	var fx: float = _fract(x)
	var fz: float = _fract(z)
	
	var a: float = img.get_pixel(ix, iz).r
	var b: float = img.get_pixel(ix + 1, iz).r
	var c: float = img.get_pixel(ix, iz + 1).r
	var d: float = img.get_pixel(ix + 1, iz + 1).r
	
	var ab: float = lerp(a, b, fx)
	var cd: float = lerp(c, d, fx)
	
	return lerp(ab, cd, fz)


static func _add_edge(edge_map: Dictionary, a: int, b: int) -> void:
	var min_i: int = a if a < b else b
	var max_i: int = b if a < b else a
	
	var key: String = str(min_i) + "_" + str(max_i)
	
	if edge_map.has(key):
		edge_map[key]["count"] += 1
	else:
		edge_map[key] = {"count": 1, "a": a, "b": b}


static func _fract(x: float) -> float:
	return x - floor(x)
