class_name ChunkRenderer extends Node

@export var viewer_node: Node3D
@export var render_distance: int = 4
@export var update_interval: float = 1.0:
	set(value):
		if value != update_interval:
			update_interval = maxf(0.05, value)
			
			if update_timer and update_timer.is_inside_tree():
				if update_timer.is_stopped():
					update_timer.wait_time = update_interval
				else:
					update_timer.stop()
					update_timer.wait_time = update_interval
					update_timer.start()

@export_category("Chunk")
@export var chunk_scene: PackedScene
@export var chunk_size_x: int = 32 
@export var chunk_size_z: int = 32 
@export var vertices_x: int = 33
@export var vertices_z: int = 33
@export var overall_world_scale: float = 10.0
@export var randomize_seed: bool = false
@export_category("Material")
@export var terrain_material: Material

var update_timer: Timer

var effective_chunk_size_x: float:
	set(value):
		effective_chunk_size_x = maxf(1.0, value)
var effective_chunk_size_z: float:
	set(value):
		effective_chunk_size_z = maxf(1.0, value)

var current_viewer_chunk_coords: Vector2i = Vector2i(9999, 9999)
var active_chunks: Dictionary[Vector2i, ChunkTerrain] = {}
var pending_chunks: Dictionary[Vector2i, ChunkTerrain] = {}

var chunk_thread: Thread
var chunk_mutex: Mutex
var exit_thread: bool = false
var chunk_semaphore: Semaphore
var chunks_on_queue: Array[ChunkTerrain] = []
var _seed: int = 0


func _enter_tree() -> void:
	_create_update_timer()
	chunk_mutex = Mutex.new()
	chunk_semaphore = Semaphore.new()
	chunk_thread = Thread.new()


func _exit_tree() -> void:
	stop()


func _ready() -> void:
	assert(chunk_scene != null, "ChunkRenderer: This renderer needs a base chunk terrain scene to render the chunks in the 3D world.")
	
	effective_chunk_size_x = chunk_size_x * overall_world_scale
	effective_chunk_size_z = chunk_size_z * overall_world_scale
	
	if randomize_seed:
		_seed = randi()
		
	start()

func start() -> void:
	chunk_thread.start(_thread_queue_chunks)
	
	_request_new_chunks()
	await get_tree().create_timer(update_interval).timeout
	
	if update_timer:
		update_timer.start(update_interval)


func stop() -> void:
	exit_thread = true
	chunk_semaphore.post() 
	update_timer.stop()
	chunk_thread.wait_to_finish()


func chunk_coords_from_viewer_position(viewer: Node3D = viewer_node) -> Vector2i:
	if viewer_node:
		return Vector2i(
			floori(viewer_node.global_position.x / effective_chunk_size_x), 
			floori(viewer_node.global_position.z / effective_chunk_size_z)
			)

	return Vector2i(9999, 9999)


func process_queued_chunks() -> void:
	for coord: Vector2i in pending_chunks:
		if pending_chunks[coord].generated and not pending_chunks[coord].is_inside_tree():
			add_child(pending_chunks[coord])
			active_chunks[coord] = pending_chunks[coord]
			active_chunks[coord].global_position.x = coord.x * chunk_size_x * overall_world_scale
			active_chunks[coord].global_position.z = coord.y * chunk_size_z * overall_world_scale
			

func update_pending_chunks() -> void:
	var new_coords: Vector2i = chunk_coords_from_viewer_position()

	if new_coords != current_viewer_chunk_coords:
		current_viewer_chunk_coords = new_coords
	
		var required: Dictionary[Vector2i, bool] = {}
		
		for x in range(current_viewer_chunk_coords.x - render_distance, current_viewer_chunk_coords.x + render_distance + 1):
			for z in range(current_viewer_chunk_coords.y - render_distance, current_viewer_chunk_coords.y + render_distance + 1):
				required[Vector2i(x, z)] = true
				
		for coord: Vector2i in required:
			if not active_chunks.has(coord) and not pending_chunks.has(coord):
				var chunk: ChunkTerrain = chunk_scene.instantiate() as ChunkTerrain
				
				if randomize_seed:
					chunk.noise_continent.seed = _seed
					chunk.noise_mountain.seed = _seed
					chunk.noise_valley.seed = _seed
					chunk.noise_erosion.seed = _seed
					
				pending_chunks[coord] = chunk


func _thread_queue_chunks() -> void:
	while not exit_thread:
		chunk_semaphore.wait()

		if exit_thread:
			break
		
		chunk_mutex.lock()
		
		for coord: Vector2i in pending_chunks:
			pending_chunks[coord].set_size(chunk_size_x, chunk_size_z, vertices_x, vertices_z)\
				.generate(coord, overall_world_scale)
			
			if terrain_material:
				pending_chunks[coord].terrain_mesh_instance.set_surface_override_material(0, terrain_material)
			
		chunk_mutex.unlock()


func _create_update_timer() -> void:
	if update_timer == null:
		update_timer = Timer.new()
		update_timer.name = "ChunkRendererUpdateTimer"
		update_timer.process_callback = Timer.TIMER_PROCESS_IDLE
		update_timer.wait_time = update_interval
		update_timer.autostart = false
		update_timer.one_shot = false
		
	if is_instance_valid(update_timer) and not update_timer.is_inside_tree():
		add_child(update_timer)
		update_timer.timeout.connect(on_update_timer_timeout)


func _request_new_chunks() -> void:
	update_pending_chunks()
	call_deferred("process_queued_chunks")
	chunk_semaphore.post()


func on_update_timer_timeout() -> void:
	_request_new_chunks()
