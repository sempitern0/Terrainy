@tool
extends Node

@export var button_Generate_Terrain: String
## More resolution means more detail (more dense vertex) in the terrain generation, this increases the mesh subdivisions it could reduce the performance in low-spec pcs
@export_range(1, 16, 1) var mesh_resolution: int = 1:
	set(value):
		if value != mesh_resolution:
			mesh_resolution = value
			
			generate_terrain()
## The depth size of the mesh (z) in godot units (meters)
@export var size_depth: int = 100:
	set(value):
		if value != size_depth:
			size_depth = max(1, value)
			
			generate_terrain()
			
## The width size of the mesh (x) in godot units (meters)
@export var size_width: int = 100:
	set(value):
		if value != size_width:
			size_width = max(1, value)
			
			generate_terrain()
## The maximum height this terrain can have
@export var max_terrain_height: float = 50.0:
	set(value):
		if value != max_terrain_height:
			max_terrain_height = maxf(0.5, value)
			generate_terrain()
## The target MeshInstance3D where the mesh will be generated. If no Mesh is defined, a new PlaneMesh is created instead.
@export var target_mesh: MeshInstance3D:
	set(value):
		if value != target_mesh:
			target_mesh = value
			update_configuration_warnings()
			
## The terrain material that will be applied on the surface
@export var terrain_material: Material
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

func _get_configuration_warnings():
	var warnings: PackedStringArray = []
	
	if target_mesh == null:
		warnings.append("No target mesh found. Expected a MeshInstance3D")
	
	if noise == null and noise_texture == null:
		warnings.append("No noise found. Expected a FastNoiseLite or a Texture2D that represents a grayscale noise")
		
	return warnings
	

func _ready() -> void:
	generate_terrain()


func generate_terrain(selected_mesh: MeshInstance3D = target_mesh) -> void:
	if selected_mesh == null:
		push_warning("Terrainy: This node needs a selected_mesh value to create the terrain, aborting generation...")
		return
	
	if noise == null and noise_texture == null:
		push_warning("Terrainy: This node needs a noise value or texture to create the terrain, aborting generation...")
		return
		
	_set_owner_to_edited_scene_root(selected_mesh)
	
	if selected_mesh.mesh is PlaneMesh:
		set_terrain_size_on_plane_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is QuadMesh:
		set_terrain_size_on_plane_mesh(selected_mesh.mesh)
	elif  selected_mesh.mesh is BoxMesh:
		set_terrain_size_on_box_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is PrismMesh:
		set_terrain_size_on_prism_mesh(selected_mesh.mesh)
	elif selected_mesh.mesh is ArrayMesh:
		selected_mesh.mesh = null
	
	if selected_mesh.mesh == null:
		var plane_mesh = PlaneMesh.new()
		set_terrain_size_on_plane_mesh(plane_mesh)
		selected_mesh.mesh = plane_mesh
		
	_free_children(selected_mesh)
	create_surface(selected_mesh)
	

func create_surface(mesh_instance: MeshInstance3D = target_mesh) -> void:
	var surface = SurfaceTool.new()
	var mesh_data_tool = MeshDataTool.new()
	
	surface.create_from(mesh_instance.mesh, 0)

	var array_mesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	if noise is FastNoiseLite and noise_texture == null:
		generate_heightmap_with_noise(noise, mesh_data_tool)
	elif noise == null and noise_texture is CompressedTexture2D:
		generate_heightmap_with_noise_texture(noise_texture, mesh_data_tool)
		
	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()

	mesh_instance.mesh = surface.commit()
	mesh_instance.create_trimesh_collision()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func generate_heightmap_with_noise(selected_noise: FastNoiseLite, mesh_data_tool: MeshDataTool) -> void:
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		vertex.y = selected_noise.get_noise_2d(vertex.x, vertex.z) * max_terrain_height
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func generate_heightmap_with_noise_texture(selected_texture: CompressedTexture2D, mesh_data_tool: MeshDataTool) -> void:
	var noise_image: Image = selected_texture.get_image()
	var width = noise_image.get_width()
	var height = noise_image.get_height()
	
	for vertex_idx: int in mesh_data_tool.get_vertex_count():
		var vertex: Vector3 = mesh_data_tool.get_vertex(vertex_idx)
		## This operation is needed to avoid being generated symmetrically only using positive values and avoid errors when obtaining the pixel from the image
		var x = vertex.x if vertex.x > 0 else width - absf(vertex.x)
		var z = vertex.z if vertex.z > 0 else height - absf(vertex.z)
		
		vertex.y = noise_image.get_pixel(x, z).r * max_terrain_height
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)


func set_terrain_size_on_plane_mesh(plane_mesh: PlaneMesh) -> void:
	plane_mesh.size = Vector2(size_width, size_depth)
	plane_mesh.subdivide_depth = size_depth * mesh_resolution
	plane_mesh.subdivide_width = size_width * mesh_resolution
	plane_mesh.material = terrain_material
	

func set_terrain_size_on_box_mesh(box_mesh: BoxMesh) -> void:
	box_mesh.size = Vector3(size_width, box_mesh.size.y, size_depth)
	box_mesh.subdivide_depth = size_depth * mesh_resolution
	box_mesh.subdivide_width = size_width * mesh_resolution
	box_mesh.material = terrain_material


func set_terrain_size_on_prism_mesh(prism_mesh: PrismMesh) -> void:
	prism_mesh.size = Vector3(size_width, prism_mesh.size.y, size_depth)
	prism_mesh.subdivide_depth = size_depth * mesh_resolution
	prism_mesh.subdivide_width = size_width * mesh_resolution
	prism_mesh.material = terrain_material

#region Helpers
func _set_owner_to_edited_scene_root(node: Node) -> void:
	if Engine.is_editor_hint() and node.get_tree():
		node.owner = node.get_tree().edited_scene_root


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
			generate_terrain()

#endregion
