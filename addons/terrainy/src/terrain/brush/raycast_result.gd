class_name BrushRaycastResult extends RefCounted

var collider: Node
var collider_id: int
var normal: Vector3
var position: Vector3
var face_index: int
var shape: int
var rid: RID

var property_keys: Array[String] = [
	"collider",
	"collider_id",
	"normal",
	"position",
	"face_index",
	"shape",
	"rid"
]

func _init(result: Dictionary) -> void:
	for key: String in property_keys:
		if result.has(key):
			self[key] = result[key]


func collided() -> bool:
	return collider != null
	

func projection(origin: Vector3, to: Vector3 = position, distance: float = 100.0) -> Vector3:
	if normal.is_zero_approx():
		return origin.direction_to(to) * distance
	
	return origin * normal * distance
	
	
func as_dict() -> Dictionary:
	return {
		"collider": collider,
		"collider_id": collider_id,
		"normal": normal,
		"position": position,
		"face_index": face_index,
		"shape": shape,
		"rid": rid,
	}
