extends EditorInspectorPlugin

var InspectorToolButton = preload("tool_button.gd")


func _can_handle(object) -> bool:
	return true


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags, wide: bool):
	if name.begins_with("button_"):
		var action = str(name.split("button_")[1])
		action = action.replace("_", " ")

		add_custom_control(InspectorToolButton.new(object, action))
		return true #Returning true removes the built-in editor for this property

	return false # else leave it
