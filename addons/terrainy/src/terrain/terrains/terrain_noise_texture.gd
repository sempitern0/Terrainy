@tool
class_name TerrainNoiseTexture extends Terrain

@export var configuration: TerrainNoiseTextureConfiguration


func validate() -> bool:
	return configuration.noise_texture != null


func generate_surface() -> SurfaceTool:
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh_data_tool: MeshDataTool = MeshDataTool.new()
	
	surface.create_from(mesh, 0)
#
	var array_mesh: ArrayMesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

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
		vertex.y *= apply_radial_shape_on_vertex(configuration, vertex)
		
		mesh_data_tool.set_vertex(vertex_idx, vertex)

	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	return surface
