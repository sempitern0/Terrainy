@tool
extends EditorPlugin

var inspector_plugin


func _enter_tree() -> void:
	inspector_plugin = preload("settings/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	
	add_custom_type("Terrainy", "Node", preload("src/terrain/terrainy.gd"), preload("assets/icons/terrainy.svg"))
	add_custom_type("TerrainBrush", "Node3D", preload("src/terrain/brush/terrain_brush.gd"), preload("assets/icons/brush.svg"))


func _exit_tree() -> void:
	remove_custom_type("TerrainBrush")
	remove_custom_type("Terrainy")
	
	remove_inspector_plugin(inspector_plugin)
