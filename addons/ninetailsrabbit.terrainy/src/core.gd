class_name TerrainyCore


static func prepare_mesh_for_diorama(mesh_instance: MeshInstance3D, dimensions: Vector3, resolution: float) -> MeshInstance3D:
	if mesh_instance.mesh == null or not mesh_instance.mesh is BoxMesh:
		var cube: BoxMesh = BoxMesh.new()
		mesh_instance.mesh = cube
	
	mesh_instance.mesh.size = dimensions
	mesh_instance.mesh.subdivide_width = resolution
	mesh_instance.mesh.subdivide_height = resolution
	mesh_instance.mesh.subdivide_depth = resolution
	
	return mesh_instance
	

static func get_noise_y(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return selected_noise.get_noise_2d(vertex.x, vertex.z)
	
## It normalizes the noise value from [-1.0, 1.0] to [0.0, 1.0]
static func get_noise_y_normalized(selected_noise: FastNoiseLite, vertex: Vector3) -> float:
	return (selected_noise.get_noise_2d(vertex.x, vertex.z) + 1) / 2
