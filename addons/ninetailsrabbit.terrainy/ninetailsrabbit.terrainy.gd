@tool
extends EditorPlugin

var inspector_plugin


func _enter_tree() -> void:
	inspector_plugin = preload("src/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	
	add_custom_type("Terrainy", "Node", preload("src/terrainy.gd"), preload("assets/terrainy.svg"))
	add_custom_type("Dioramy", "Node3D", preload("src/dioramy.gd"), preload("assets/terrainy.svg"))


func _exit_tree() -> void:
	remove_custom_type("Dioramy")
	remove_custom_type("Terrainy")
	remove_inspector_plugin(inspector_plugin)
