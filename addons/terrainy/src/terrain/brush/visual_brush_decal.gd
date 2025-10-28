## Recommended to modulate the alpha to 70 to reduce the brightness when painting
class_name VisualBrushDecal extends Decal


func display(new_position: Vector3, normal: Vector3, brush_radius: float) -> void:
	global_position = new_position
	size = Vector3.ONE * brush_radius * 2.0
	adjust_to_normal(normal)


func assign_texture(brush_texture: Texture2D) -> void:
	texture_albedo = brush_texture


func adjust_to_normal(normal: Vector3) -> void:
	if not normal.is_equal_approx(Vector3.UP) and not normal.is_equal_approx(Vector3.DOWN):
		look_at(global_position + normal, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, PI / 2)
