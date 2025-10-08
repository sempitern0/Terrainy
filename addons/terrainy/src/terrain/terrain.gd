@tool
class_name Terrain extends MeshInstance3D

const GroupName: StringName = &"terrains"
const GridGroupName: StringName = &"grid_terrains"


@export var configuration: TerrainConfiguration

var mirror: Terrain
var neighbours: Dictionary[Vector3, Terrain] = {
	Vector3.FORWARD: null,
	Vector3.BACK: null,
	Vector3.RIGHT: null,
	Vector3.LEFT: null,
}

var valid_neighbour_directions: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]
var opposite_directions: Dictionary = {
	Vector3.RIGHT: Vector3.LEFT, 
	Vector3.LEFT: Vector3.RIGHT, 
	Vector3.FORWARD: Vector3.BACK, 
	Vector3.BACK: Vector3.FORWARD
}


func _enter_tree() -> void:
	add_to_group(GroupName)


func add_mirror_terrain(mirror_terrain: Terrain) -> void:
	if mirror and mirror.is_inside_tree():
		mirror.queue_free()
		
	mirror = mirror_terrain


func assign_neighbour(neighbour_terrain: Terrain, direction: Vector3) -> bool:
	if direction in valid_neighbour_directions \
		and neighbours[direction] == null \
		and neighbour_terrain.neighbours[opposite_directions[direction]] == null:
			
			neighbours[direction] = neighbour_terrain
			neighbour_terrain[opposite_directions[direction]] = self
			
			if not self.is_in_group(GridGroupName):
				self.add_to_group(GridGroupName)
				
			if not neighbour_terrain.is_in_group(GridGroupName):
				neighbour_terrain.add_to_group(GridGroupName)
		
			return true
		
	return false
	
	
func neighbours_available() -> Array[Vector3]:
	return neighbours.keys().filter(func(direction: Vector3): return neighbours[direction] != null)


func has_noise_available() -> bool:
	return configuration and \
		configuration.noise != null or configuration.noise_texture != null
