class_name TerrainyCore

const DefaultTerrainMaterial: StandardMaterial3D = preload("uid://dnlh6yw1dkew1")
const DefaultMirrorTerrainMaterial: StandardMaterial3D = preload("uid://8ku0pjn8b0p3")
const DefaultMirrorNoise: FastNoiseLite = preload("uid://d0fdf4fw86ijk")


enum CollisionType {
	None,
	Trimesh,
	ConcavePolygon
}


static func get_noise_y(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return selected_noise.get_noise_2d(vertex.x, vertex.z)
	

static func get_noise_y_normalized(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return (selected_noise.get_noise_2d(vertex.x, vertex.z) + 1) / 2

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


static func create_mirrored_terrain(original_terrain: Terrain) -> Terrain:
	if not is_instance_valid(original_terrain) or original_terrain.mesh == null:
		push_error("TerrainyCore->create_mirrored_terrain: The original terrain mesh does not have a valid Mesh assigned, aborting...")
		return null
	
	var source_mesh: Mesh = original_terrain.mesh
	var mirror_array: ArrayMesh = ArrayMesh.new()
	var eps: float = original_terrain.configuration.mirror_offset
	var depth: float = original_terrain.configuration.mirror_depth

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
			
			if original_terrain.configuration.mirror_noise:
				n_offset = original_terrain.configuration.mirror_noise.get_noise_2d(v.x, v.z) * depth * 0.25
			else:
				var default_mirror_noise: FastNoiseLite = DefaultMirrorNoise.duplicate()
				default_mirror_noise.seed = randi()
				n_offset = default_mirror_noise.get_noise_2d(v.x, v.z) * depth * 0.25
			
			var offset_dir: Vector3 = (normals_src[i] if i < normals_src.size() else Vector3.DOWN).normalized()
			var bottom_pt: Vector3 = v - offset_dir * (depth + n_offset)
		
			bottom.append(bottom_pt)
			
			var t: float = clampf((absf(v.y) / original_terrain.configuration.max_terrain_height), 0.0, 1.0)
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
					var normal_test := a1.cross(a2).normalized()
					var use_order := normal_test.dot(outward) > 0

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

	var mirror_terrain: Terrain = original_terrain.duplicate()
	mirror_terrain.configuration = original_terrain.configuration
	mirror_terrain.name = "%sMirror" % original_terrain.name
	mirror_terrain.mesh = mirror_array
	mirror_terrain.transform = original_terrain.transform
	mirror_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	
	if original_terrain.configuration.mirror_material:
		original_terrain.configuration.mirror_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mirror_terrain.mesh.surface_set_material(0, original_terrain.configuration.mirror_material)
	else:
		mirror_terrain.mesh.surface_set_material(0, TerrainyCore.DefaultMirrorTerrainMaterial)
	
	original_terrain.add_mirror_terrain(mirror_terrain)
	
	return mirror_terrain


static func _add_edge(edge_map: Dictionary, a: int, b: int) -> void:
	# almacena clave undirected pero conserva la orientación 'a->b' la primera vez
	var min_i: int = a if a < b else b
	var max_i: int = b if a < b else a
	
	var key: String = str(min_i) + "_" + str(max_i)
	
	if edge_map.has(key):
		edge_map[key]["count"] += 1
	else:
		edge_map[key] = {"count": 1, "a": a, "b": b}


static func _fract(x: float) -> float:
	return x - floor(x)
	
	
