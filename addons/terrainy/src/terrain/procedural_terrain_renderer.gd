class_name InfiniteTerrainRenderer extends Node3D

@export var terrainy: Terrainy
@export var tracked_node: Node3D
@export var procedural_shared_noise: TerrainNoiseConfiguration
@export var initial_grid_size: Vector2i = Vector2i.ONE * 3
@export var max_chunks_per_tick: int = 5
@export var generation_distance: float = 100.0
@export var unload_distance: float = 200.0
@export var update_tick_time: float = 1.0:
	set(value):
		if value != update_tick_time:
			update_tick_time = value
			if update_tick_timer and update_tick_timer.is_inside_tree():
				update_tick_timer.start(maxf(0.01, update_tick_time))

var generated_chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var pending_chunks: Array[Vector2i] = []

var _last_player_chunk: Vector2i = Vector2i(-9999, -9999)

var update_tick_timer: Timer
var _processing_chunks: bool = false


func _ready() -> void:
	assert(terrainy != null, "InfiniteTerrainRenderer: This node needs a Terrainy node assigned to generate the terrain chunks, aborting...")
	assert(procedural_shared_noise != null, "InfiniteTerrainRenderer: This node needs a TerrainConfiguration to geenrate the terrain chunks, aborting...")
	_prepare_tick_timer(update_tick_time)
	
	if initial_grid_size == Vector2i.ZERO:
		terrainy.terrain_generation_finished.connect(on_terrain_chunk_generation_finished, CONNECT_DEFERRED)
	else:
		terrainy.generate_procedural_grid(initial_grid_size, procedural_shared_noise, self)
		terrainy.terrain_generation_finished.connect(
			func(terrains: Dictionary[MeshInstance3D, TerrainConfiguration]):
				for terrain: MeshInstance3D in terrains:
					generated_chunks[terrain.get_meta(&"grid_position")] = terrain
				
				terrainy.terrain_generation_finished.connect(on_terrain_chunk_generation_finished, CONNECT_DEFERRED)
				
				update_tick_timer.start()
				, CONNECT_ONE_SHOT)
	

func get_current_chunk_position() -> Vector2i:
	if not tracked_node:
		return _last_player_chunk
		
	var pos: Vector3 = tracked_node.global_position
	
	return Vector2i(
		floor(pos.x / procedural_shared_noise.size_width),
		floor(pos.z / procedural_shared_noise.size_depth)
	)


func stream_chunks_around_tracked_node(current_world_position: Vector3) -> void:
	_processing_chunks = true

		
	var chunks_to_generate: Array[Vector2i] = []
	var chunks_to_unload: Array[Vector2i] = []
	var range_x: int = ceili(generation_distance / procedural_shared_noise.size_width)
	var range_z: int = ceili(generation_distance / procedural_shared_noise.size_depth)
	
	for z in range(-range_z, range_z + 1): 
		for x in range(-range_x, range_x + 1):
			
			var check_chunk: Vector2i = _last_player_chunk + Vector2i(x, z)
			var chunk_origin: Vector3 = Vector3(
				check_chunk.x * procedural_shared_noise.size_width,
				0,
				check_chunk.y * procedural_shared_noise.size_depth
			)

			var dist: float = current_world_position.distance_to(chunk_origin)
			
			if dist <= generation_distance:
				if generated_chunks.has(check_chunk):
					generated_chunks[check_chunk].process_mode = Node.PROCESS_MODE_INHERIT
					pending_chunks.erase(check_chunk)
				else:
					if not pending_chunks.has(check_chunk):
						chunks_to_generate.append(check_chunk)
		
		for grid_pos: Vector2i in generated_chunks.keys():
			var chunk_origin: Vector3 = Vector3(
				grid_pos.x * procedural_shared_noise.size_width,
				0,
				grid_pos.y * procedural_shared_noise.size_depth
			)
			
			var dist: float = current_world_position.distance_to(chunk_origin)
			
			if dist > unload_distance:
				chunks_to_unload.append(grid_pos)
		
	for grid_pos: Vector2i in chunks_to_unload:
		var chunk: MeshInstance3D = generated_chunks[grid_pos]
		
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
			chunk.process_mode = Node.PROCESS_MODE_DISABLED
	
	if chunks_to_generate.size():
		pending_chunks.append_array(chunks_to_generate)
			
		var new_terrains: Dictionary[MeshInstance3D, TerrainConfiguration] = {}
		var chunk_positions_to_delete: Array[Vector2i] = []
		
		for chunk_index: int in mini(pending_chunks.size(), max_chunks_per_tick):
			var chunk_position: Vector2i = pending_chunks[chunk_index]
			var configuration: TerrainNoiseConfiguration = procedural_shared_noise.duplicate()
			var terrain: MeshInstance3D = terrainy.prepare_procedural_terrain(chunk_position, configuration, self)
			new_terrains[terrain] = configuration
			generated_chunks[chunk_position] = terrain
			chunk_positions_to_delete.append(chunk_position)
		
		for chunk_position_to_delete: Vector2i in chunk_positions_to_delete:
			pending_chunks.erase(chunk_position_to_delete)
		
		terrainy.call_deferred("generate_terrains", new_terrains, self, true)


func update_terrain_stream() -> void:
	if _processing_chunks:
		return
	
	var current_chunk: Vector2i = get_current_chunk_position()
	
	if current_chunk == _last_player_chunk:
		_processing_chunks = false
		return
	
	_last_player_chunk = current_chunk
	
	stream_chunks_around_tracked_node(tracked_node.global_position)


func _prepare_tick_timer(wait_time: float) -> void:
	if update_tick_timer == null:
		update_tick_timer = Timer.new()
		update_tick_timer.name = "ProceduralWorldTickTimer"
		update_tick_timer.wait_time = wait_time
		update_tick_timer.autostart = false
		update_tick_timer.one_shot = false
		update_tick_timer.ignore_time_scale = true
		update_tick_timer.timeout.connect(update_terrain_stream)
		
		add_child(update_tick_timer)


func on_terrain_chunk_generation_finished(_terrains: Dictionary[MeshInstance3D, TerrainConfiguration]):
	_processing_chunks = false
