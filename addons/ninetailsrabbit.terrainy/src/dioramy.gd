@tool
class_name Dioramy extends Node3D

@export var button_Generate_Diorama: String
@export_category("Diorama")
@export var layers: Array[Vector3] = []
## More resolution means more detail (more dense vertex) in the diorama generation, this increases the mesh subdivisions it could reduce the performance in low-spec pcs
@export_range(2, 2048, 2) var mesh_resolution: int = 32
@export var amplitude: float = 0.0
@export var randomize_noise_seed: bool = true
@export var noise: FastNoiseLite


func generate_diorama() -> void:
	_free_children(self)
	
	var last_diorama_height: float = 0.0
	var layer: int = 0
	
	for layer_dimensions: Vector3 in layers:
		layer += 1
		
		var diorama_mesh: MeshInstance3D  = _create_layer_mesh(layer, layer_dimensions, mesh_resolution)
		
		var surface = SurfaceTool.new()
		var mesh_data_tool = MeshDataTool.new()
		
		surface.create_from(diorama_mesh.mesh, 0)
		
		var array_mesh = surface.commit()
		mesh_data_tool.create_from_surface(array_mesh, 0)
		
		if noise and layer == 1:
			var top_y_threshold = layer_dimensions.y / 2.0
			var bottom_y_threshold = -top_y_threshold
			
			if randomize_noise_seed:
				noise.seed = randi()
				
			for vertex_idx in range(mesh_data_tool.get_vertex_count()):
				var vertex = mesh_data_tool.get_vertex(vertex_idx)

				if is_equal_approx(vertex.y, top_y_threshold):
					var noise_value = TerrainyCore.get_noise_y_normalized(noise, vertex)
					vertex.y = top_y_threshold + noise_value * (amplitude if amplitude > 0.0 else 1.0)
					mesh_data_tool.set_vertex(vertex_idx, vertex)
		
			array_mesh.clear_surfaces()
			
		mesh_data_tool.commit_to_surface(array_mesh)
		
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.create_from(array_mesh, 0)
		surface.generate_normals()
		
		diorama_mesh.mesh = surface.commit()
		
		if layer == 1:
			diorama_mesh.create_trimesh_collision()
			
		diorama_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		if layer > 1:
			diorama_mesh.position.y = Vector3.DOWN.y * (last_diorama_height / 2.0 + layer_dimensions.y / 2.0)
			
		last_diorama_height = layer_dimensions.y
	

func _create_layer_mesh(layer: int, dimensions: Vector3, resolution: float = mesh_resolution) -> MeshInstance3D:
	var diorama_mesh: MeshInstance3D  = MeshInstance3D.new()
	diorama_mesh = TerrainyCore.prepare_mesh_for_diorama(diorama_mesh, dimensions, resolution)
	diorama_mesh.name = "DioramaLayer%d" % layer
	add_child(diorama_mesh)
	_set_owner_to_edited_scene_root(diorama_mesh)
	
	return diorama_mesh


func _on_tool_button_pressed(text: String) -> void:
	match text:
		"Generate Diorama":
			generate_diorama()
			
			
func _free_children(node: Node) -> void:
	if node.get_child_count() == 0:
		return

	var childrens = node.get_children()
	childrens.reverse()
	
	for child in childrens.filter(func(_node: Node): return is_instance_valid(node)):
		child.free()


func _set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root
