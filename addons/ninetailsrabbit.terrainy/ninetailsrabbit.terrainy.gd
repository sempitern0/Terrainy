@tool
extends EditorPlugin

var inspector_plugin
var plugin_custom_type: String = "Terrainy"


func _enter_tree() -> void:
	inspector_plugin = preload("src/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	add_custom_type(plugin_custom_type, "Node", preload("src/terrainy.gd"), preload("assets/terrainy.svg"))


func _exit_tree() -> void:
	remove_custom_type(plugin_custom_type)
	remove_inspector_plugin(inspector_plugin)
