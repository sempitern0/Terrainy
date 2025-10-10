@tool
class_name Terrain extends MeshInstance3D

const GroupName: StringName = &"terrains"
const GridGroupName: StringName = &"grid_terrains"
const ValidNeighboursDirections: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]
const OppositeDirections: Dictionary[Vector3, Vector3] = {
	Vector3.RIGHT: Vector3.LEFT, 
	Vector3.LEFT: Vector3.RIGHT, 
	Vector3.FORWARD: Vector3.BACK, 
	Vector3.BACK: Vector3.FORWARD
}

## To avoid update the position when it's already in a terrain grid.
var grid_positioned: bool = false:
	set(value):
		grid_positioned = value
		
		if is_inside_tree() and not is_in_group(GridGroupName):
			add_to_group(GridGroupName)
			
var mirror: Terrain
var neighbours: Dictionary[Vector3, Terrain] = {
	Vector3.FORWARD: null,
	Vector3.BACK: null,
	Vector3.RIGHT: null,
	Vector3.LEFT: null,
}


func _enter_tree() -> void:
	add_to_group(GroupName)
	
	
#region Overridables
func validate() -> bool:
	return false
	
	
func generate_surface() -> SurfaceTool:
	return null
#endregion


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


func apply_radial_shape_on_vertex(configuration: TerrainConfiguration, vertex: Vector3) -> float:
	if configuration.radial_shape:
		var radius_x: float = configuration.size_width * 0.5
		var radius_z: float = configuration.size_depth * 0.5
		var dist: float = Vector2(vertex.x / radius_x, vertex.z / radius_z).length()
		var radial_mask: float = clampf(1.0 - pow(dist, configuration.radial_falloff_power), 0.0, 1.0)
		
		return radial_mask
		
	return 1.0


func add_mirror_terrain(mirror_terrain: Terrain) -> void:
	if mirror and mirror.is_inside_tree():
		mirror.queue_free()
		
	mirror = mirror_terrain


func assign_neighbour(neighbour_terrain: Terrain, direction: Vector3) -> bool:
	if direction in ValidNeighboursDirections \
		and neighbours[direction] == null \
		and neighbour_terrain.neighbours[OppositeDirections[direction]] == null:
			
			neighbours[direction] = neighbour_terrain
			neighbour_terrain.neighbours[OppositeDirections[direction]] = self
			
			if not self.is_in_group(GridGroupName):
				self.add_to_group(GridGroupName)
				
			if not neighbour_terrain.is_in_group(GridGroupName):
				neighbour_terrain.add_to_group(GridGroupName)
		
			return true
		
	return false


func all_neighbours_available() -> bool:
	return neighbours_available().size() == ValidNeighboursDirections.size()

	
func neighbours_available() -> Array[Vector3]:
	return neighbours.keys().filter(
		func(direction: Vector3): return neighbours[direction] == null
		)
