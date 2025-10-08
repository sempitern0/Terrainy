@tool
class_name Terrain extends MeshInstance3D

const GroupName: StringName = &"terrains"

@export var configuration: TerrainConfiguration

var mirror: Terrain
var neighbours: Dictionary[Vector3, Terrain] = {
	Vector3.FORWARD: null,
	Vector3.BACK: null,
	Vector3.RIGHT: null,
	Vector3.LEFT: null,
}


func _enter_tree() -> void:
	add_to_group(GroupName)


func add_mirror_terrain(mirror_terrain: Terrain) -> void:
	if mirror and mirror.is_inside_tree():
		mirror.queue_free()
		
	mirror = mirror_terrain


func neighbours_available() -> Array[Vector3]:
	return neighbours.keys().filter(func(direction: Vector3): return neighbours[direction] != null)


func has_noise_available() -> bool:
	return configuration and \
		configuration.noise != null or configuration.noise_texture != null
