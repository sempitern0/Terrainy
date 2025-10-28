## Brush to modify the terrain on runtime
class_name TerrainBrush extends Node3D


@export var origin_camera: Camera3D:
	set(new_camera):
		origin_camera = new_camera
		
		if is_node_ready():
			set_process(origin_camera != null)
			set_process_unhandled_input(origin_camera != null)

## The area of influence for the brush
@export_range(0.1, 100.0, 0.1) var brush_radius: float = 15.0
## The speed to apply the modifier on the terrain
@export_range(0.1, 10, 0.1) var brush_strength: float = 1.5
## Smooth the painting using the falloff
@export var use_falloff: bool = true
@export var brush_texture: Texture2D:
	set(new_texture):
		brush_texture = new_texture
		_cache_brush_texture(brush_texture)
		
		if visual_brush_decal and is_node_ready():
			visual_brush_decal.assign_texture(brush_texture)
			
@export var visual_brush_decal: VisualBrushDecal

var cached_brush_textures: Dictionary[Texture2D, Dictionary] = {}

enum Modes {
	Waiting,
	RaiseTerrain,
	LowerTerrain,
	VertexPaint
}

var painting: bool = false:
	set(value):
		if painting != value:
			painting = value
			
			if not painting and last_terrain:
				last_terrain.regenerate_collision()
				last_terrain = null
				
var current_mode: Modes = Modes.RaiseTerrain
var last_terrain: MeshInstance3D
var current_paint_color_channel: Color = Color.RED


func _unhandled_input(_event: InputEvent) -> void:
	painting = InputMap.has_action(&"paint_terrain") and Input.is_action_pressed(&"paint_terrain")
	
	#if OmniKitInputHelper.action_just_pressed_and_exists(InputControls.Aim):
		#if current_mode == Modes.RaiseTerrain:
			#change_mode_to_lower_terrain()
		#else:
			#change_mode_to_raise_terrain()
	#

func _ready() -> void:
	set_process(origin_camera != null)
	set_process_unhandled_input(origin_camera != null)
	
	_cache_brush_texture(brush_texture)
		
	if visual_brush_decal:
		visual_brush_decal.assign_texture(brush_texture)
		visual_brush_decal.show()


func _process(_delta: float) -> void:
		var result: TerrainRaycastResult = project_raycast_to_mouse(origin_camera, 200.0)
		
		if result.position and result.collider:
			if visual_brush_decal:
				visual_brush_decal.display(result.position, result.normal, brush_radius)
				
			if painting:
				match current_mode:
					Modes.VertexPaint:
						paint_terrain_vertex_color(
							result.collider.get_parent(), 
							result.position, 
							brush_radius, 
							brush_strength,
							current_paint_color_channel
						)
						
					Modes.RaiseTerrain:
						deform_terrain(
							result.collider.get_parent(), 
							result.position, 
							brush_radius, 
							brush_strength ## Positive strength raise the terrain
						)
							
					Modes.LowerTerrain:
						deform_terrain(
							result.collider.get_parent(), 
							result.position, 
							brush_radius, 
							brush_strength * -1.0 ## Negative strength lower the terrain
						)
		
func deform_terrain(terrain: MeshInstance3D, point: Vector3, radius: float = brush_radius, strength: float = brush_strength) -> void:
	if terrain.mesh == null:
		return
	
	last_terrain = terrain
	
	var mdt: MeshDataTool = MeshDataTool.new()
	mdt.create_from_surface(terrain.mesh, 0)
	
	var local_point: Vector3 = terrain.to_local(point)
	var radius_sq: float = radius * radius  

	for vertex_index: int in mdt.get_vertex_count():
		var vertex: Vector3 = mdt.get_vertex(vertex_index)
		var dist_sq: float = vertex.distance_squared_to(local_point)
		
		var offset: Vector3 = vertex - local_point

		if dist_sq < radius_sq:
			var texture_factor: float = 1.0
			var falloff: float  = 1.0
			
			if brush_texture:
				var brush_image: Image = cached_brush_textures[brush_texture].image
				
				var uv: Vector2 = Vector2(offset.x, offset.z) / brush_radius * 0.5 + Vector2(0.5, 0.5)
				uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

				texture_factor = brush_image.get_pixelv(uv * cached_brush_textures[brush_texture].size).r
			
			if use_falloff:
				falloff = 1.0 - (dist_sq / radius_sq)
				falloff = falloff * falloff ## More faster than pow()
				
			vertex.y += strength * falloff * texture_factor

			mdt.set_vertex(vertex_index, vertex)
	
	var array_mesh: ArrayMesh = ArrayMesh.new()
	mdt.commit_to_surface(array_mesh)
	terrain.mesh = array_mesh


func paint_terrain_vertex_color(terrain: MeshInstance3D, point: Vector3, radius: float, strength: float, color: Color) -> void:
	if terrain.mesh == null:
		return
	
	last_terrain = terrain
	
	var mdt: MeshDataTool = MeshDataTool.new()
	mdt.create_from_surface(terrain.mesh, 0)
	
	var local_point: Vector3 = terrain.to_local(point)
	var radius_sq: float = radius * radius  

	for vertex_index: int in mdt.get_vertex_count():
		var vertex: Vector3 = mdt.get_vertex(vertex_index)
		var dist_sq: float = vertex.distance_squared_to(local_point)
		
		var offset: Vector3 = vertex - local_point

		if dist_sq < radius_sq:
			var texture_factor: float = 1.0
			var falloff: float  = 1.0
			
			if brush_texture:
				var brush_image: Image = cached_brush_textures[brush_texture].image
				
				var uv: Vector2 = Vector2(offset.x, offset.z) / brush_radius * 0.5 + Vector2(0.5, 0.5)
				uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

				texture_factor = brush_image.get_pixelv(uv * cached_brush_textures[brush_texture].size).r
			
			if use_falloff:
				falloff = 1.0 - (dist_sq / radius_sq)
				falloff = falloff * falloff ## More faster than pow()
				
			var vertex_color: Color = mdt.get_vertex_color(vertex_index)
			vertex_color = vertex_color.lerp(color, strength * falloff * texture_factor)
			
			var total = vertex_color.r + vertex_color.g + vertex_color.b
			if total > 1.0:
				vertex_color /= total
			
			mdt.set_vertex_color(vertex_index, vertex_color)

	var array_mesh: ArrayMesh = ArrayMesh.new()
	mdt.commit_to_surface(array_mesh)
	terrain.mesh = array_mesh
	
	

func _cache_brush_texture(texture: Texture2D) -> void:
	if texture:
		var image: Image = texture.get_image()
		
		if image.is_compressed():
			image.decompress()
			
		cached_brush_textures[texture] = {
			"image": image,
			"width": image.get_width(),
			"height": image.get_height(),
			"size": texture.get_size()
		}
		
		
func change_mode_to(new_mode: Modes) -> void:
	current_mode = new_mode


func change_mode_to_waiting() -> void:
	change_mode_to(Modes.Waiting)
	
	
func change_mode_to_raise_terrain() -> void:
	change_mode_to(Modes.RaiseTerrain)


func change_mode_to_lower_terrain() -> void:
	change_mode_to(Modes.LowerTerrain)


func project_raycast(
	viewport: Viewport,
	from: Vector3,
	to: Vector3,
	collide_with_bodies: bool = true,
	collide_with_areas: bool = false,
	collision_mask: int = 1
) -> TerrainRaycastResult:
	
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, 
		to,
		collision_mask
	)
	
	ray_query.collide_with_bodies = collide_with_bodies
	ray_query.collide_with_areas = collide_with_areas

	var result: Dictionary = (viewport.get_camera_3d().get_world_3d() if viewport is SubViewport else viewport.get_world_3d()).direct_space_state.intersect_ray(ray_query)

	return TerrainRaycastResult.new(result)

	
func project_raycast_to_mouse(
	camera: Camera3D,
	distance: float = 1000.0,
	collide_with_bodies: bool = true,
	collide_with_areas: bool = false,
	collision_mask: int = 1
) -> TerrainRaycastResult:
	
	var viewport: Viewport = camera.get_viewport()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	
	var world_space: PhysicsDirectSpaceState3D = (camera.get_world_3d() if viewport is SubViewport else viewport.get_world_3d()).direct_space_state
	var from: Vector3 = camera.project_ray_origin(mouse_position)
	var to: Vector3 = camera.project_position(mouse_position, distance)
	
	return project_raycast(viewport, from, to, collide_with_bodies, collide_with_areas, collision_mask)
