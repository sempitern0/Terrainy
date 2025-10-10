@tool
class_name TerrainHeightmap extends Terrain

@export var configuration: TerrainHeightmapConfiguration


func validate() -> bool:
	return configuration.heightmap_image != null


func generate_surface() -> SurfaceTool:
	var surface: SurfaceTool = SurfaceTool.new()
	var mesh_data_tool: MeshDataTool = MeshDataTool.new()
	
	surface.create_from(mesh, 0)
#
	var array_mesh: ArrayMesh = surface.commit()
	mesh_data_tool.create_from_surface(array_mesh, 0)

	var heightmap_image: Image = configuration.heightmap_image.get_image()
	
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
		var x: int = clampi(int(width * (vertex.x / configuration.size_width + 0.5)), 0, width - 1)
		var z: int = clampi(int(height * (vertex.z / configuration.size_depth + 0.5)), 0, height - 1)

		var value: float = TerrainyCore.get_bilinear_height(heightmap_image, x, z)
		
		## To apply a more precise height from this heightmap image
		if configuration.auto_scale_heightmap_image:
			value = (value - min_v) / range_v
		else:
			value = clampf(value, 0.0, 1.0)
			
		var falloff: float = calculate_falloff(configuration, vertex)
		
		## Smooth the mountain peaks to not appear so pointed and artificial
		var smoothed_value: float = value - pow(value, 3.0) * 0.2
		
		if smoothed_value > 0.8:
			var soften_factor = 1.0 - (smoothed_value - 0.8) * 2.0
			vertex.y *= clampf(soften_factor, 0.7, 1.0)

		vertex.y = apply_elevation_curve(configuration, smoothed_value)
		vertex.y *= apply_radial_shape_on_vertex(configuration, vertex)
		vertex.y *= configuration.max_terrain_height * falloff

		mesh_data_tool.set_vertex(vertex_idx, vertex)

	array_mesh.clear_surfaces()
	mesh_data_tool.commit_to_surface(array_mesh)
	
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.create_from(array_mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	
	return surface
