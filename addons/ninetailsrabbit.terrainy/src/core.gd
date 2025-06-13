class_name TerrainyCore

enum CollisionType {
	None,
	Trimesh,
	ConcavePolygon
}

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


static func set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint():
		node.owner = node.get_tree().edited_scene_root


static func free_children(node: Node) -> void:
	if node.get_child_count() == 0:
		return

	var childrens = node.get_children()
	childrens.reverse()
	
	for child in childrens.filter(func(_node: Node): return is_instance_valid(node)):
		child.free()
