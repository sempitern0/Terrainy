@tool
extends EditorPlugin

var inspector_plugin


func _enter_tree() -> void:
	inspector_plugin = preload("settings/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	
	add_custom_type("Terrainy", "Node", preload("src/terrain/terrainy.gd"), preload("assets/icons/terrainy.svg"))
	add_custom_type("ChunkRenderer", "Node", preload("src/chunk/chunk_renderer.gd"), preload("assets/icons/chunk_renderer.svg"))
	add_custom_type("ChunkTerrain", "Node3D", preload("src/chunk/chunk_terrain.gd"), preload("assets/icons/chunk_terrain.svg"))
	add_custom_type("TerrainNoise", "Node3D", preload("src/chunk/chunk_terrain.gd"), preload("assets/icons/terrain.svg"))
	add_custom_type("TerrainNoiseTexture", "Node3D", preload("src/chunk/chunk_terrain.gd"), preload("assets/icons/terrain.svg"))
	add_custom_type("TerrainHeightmap", "Node3D", preload("src/chunk/chunk_terrain.gd"), preload("assets/icons/terrain.svg"))


func _exit_tree() -> void:
	remove_custom_type("TerrainHeightmap")
	remove_custom_type("TerrainNoiseTexture")
	remove_custom_type("TerrainNoise")
	remove_custom_type("ChunkTerrain")
	remove_custom_type("ChunkRenderer")
	remove_custom_type("Terrainy")
	
	remove_inspector_plugin(inspector_plugin)
