@tool
class_name Dioramy extends Node3D

@export var button_Generate_Diorama: String
@export var output_node: Node3D
@export_category("Diorama")
@export var layers: Array[DioramaLayer] = []


func generate_diorama() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "DioramaRoot%d" % output_node.get_child_count()
	output_node.add_child(root_node)
	TerrainyCore.set_owner_to_edited_scene_root(root_node)
	
	for layer in generate_diorama_layers():
		root_node.add_child(layer)
		TerrainyCore.set_owner_to_edited_scene_root(layer)


func generate_diorama_layers() -> Array[MeshInstance3D]:
	if layers.is_empty():
		return []
	
	var layers_created: Array[MeshInstance3D] = []
	var last_diorama_height: float = 0.0
	var layer: int = 0
	
	for diorama_layer: DioramaLayer in layers:
		layer += 1
		
		var diorama_mesh: MeshInstance3D  = _create_layer_mesh(layer, diorama_layer)
		var surface = SurfaceTool.new()
		var mesh_data_tool = MeshDataTool.new()
		
		surface.create_from(diorama_mesh.mesh, 0)
		
		var array_mesh = surface.commit()
		mesh_data_tool.create_from_surface(array_mesh, 0)
		
		if diorama_layer.noise:
			var top_y_threshold = diorama_layer.dimensions.y / 2.0
			var bottom_y_threshold = -top_y_threshold
				
			if diorama_layer.randomize_noise_seed:
				diorama_layer.noise.seed = randi()
	
				for vertex_idx in range(mesh_data_tool.get_vertex_count()):
					var vertex = mesh_data_tool.get_vertex(vertex_idx)
					
					if diorama_layer.is_top_height_direction():
				
						if is_equal_approx(vertex.y, top_y_threshold):
							var noise_value = TerrainyCore.get_noise_y_normalized(diorama_layer.noise, vertex)
							vertex.y = top_y_threshold + noise_value * (diorama_layer.amplitude if diorama_layer.amplitude > 0.0 else 1.0)
							mesh_data_tool.set_vertex(vertex_idx, vertex)
							
					elif diorama_layer.is_bottom_height_direction():
						
						if is_equal_approx(vertex.y, bottom_y_threshold):
							var noise_value = TerrainyCore.get_noise_y_normalized(diorama_layer.noise, vertex)
							vertex.y = bottom_y_threshold - noise_value * (diorama_layer.amplitude if diorama_layer.amplitude > 0.0 else 1.0)
							mesh_data_tool.set_vertex(vertex_idx, vertex)
					
			array_mesh.clear_surfaces()
			
		mesh_data_tool.commit_to_surface(array_mesh)
		
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.create_from(array_mesh, 0)
		surface.generate_normals()
		surface.generate_tangents()

		diorama_mesh.mesh = surface.commit()
		
		if diorama_layer.generate_collisions:
			diorama_mesh.create_trimesh_collision()
		
		diorama_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		if layer > 1:
			diorama_mesh.position.y = Vector3.DOWN.y * (last_diorama_height / 2.0 + diorama_layer.dimensions.y / 2.0)
			
		last_diorama_height = diorama_layer.dimensions.y
		
		layers_created.append(diorama_mesh)
		
	return layers_created


func _create_layer_mesh(layer: int, diorama_layer: DioramaLayer):
	var diorama_mesh: MeshInstance3D  = MeshInstance3D.new()
	diorama_mesh = TerrainyCore.prepare_mesh_for_diorama(diorama_mesh, diorama_layer.dimensions, diorama_layer.mesh_resolution)
	diorama_mesh.name = "DioramaLayer%d" % layer
	
	return diorama_mesh


func _on_tool_button_pressed(text: String) -> void:
	match text:
		"Generate Diorama":
			generate_diorama()
