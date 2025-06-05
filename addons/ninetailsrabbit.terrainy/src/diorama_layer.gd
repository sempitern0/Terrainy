@tool
class_name DioramaLayer extends Resource

enum HeightDirection {
	Top,
	Bottom
}

@export var dimensions: Vector3 = Vector3.ONE
@export var generate_collisions: bool = true;
@export_range(2, 2048, 2) var mesh_resolution: int = 32
@export var amplitude: float = 0.0
@export var randomize_noise_seed: bool = true
@export var noise: FastNoiseLite
@export var height_direction: HeightDirection = HeightDirection.Top


func is_top_height_direction() -> bool:
	return height_direction == HeightDirection.Top
	

func is_bottom_height_direction() -> bool:
	return height_direction == HeightDirection.Bottom
