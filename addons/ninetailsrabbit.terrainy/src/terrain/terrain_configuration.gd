@tool
class_name TerrainConfiguration extends Resource

@export var id: StringName
@export var name: StringName
@export_multiline var description: String
## Collision type generation for the terrain meshes
@export var collision_type: TerrainyCore.CollisionType = TerrainyCore.CollisionType.Trimesh
## More resolution means more detail (more dense vertex) in the terrain generation, this increases the mesh subdivisions it could reduce the performance in low-spec pcs
@export_range(2, 2048, 2) var mesh_resolution: int = 64
## The depth size of the mesh (z) in godot units (meters)
@export var size_depth: int = 100:
	set(value):
		if value != size_depth:
			size_depth = max(1, value)
			
## The width size of the mesh (x) in godot units (meters)
@export var size_width: int = 100:
	set(value):
		if value != size_width:
			size_width = max(1, value)
			
## The maximum height this terrain can have
@export var max_terrain_height: float = 50.0:
	set(value):
		if value != max_terrain_height:
			max_terrain_height = maxf(0.5, value)

## The terrain material that will be applied on the surface
@export var terrain_material: Material
@export_category("Heightmap")
## It only applies when FastNoiseLite is used to generate the terrain
@export var randomize_noise_seed: bool = false
## Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.
## Rocky: +Octaves -Period, Hills: -Octaves +Period
@export var noise: FastNoiseLite
## Use a texture as noise to generate the terrain. If a noise is defined, this texture will be ignored.
@export var noise_texture: CompressedTexture2D
## Manage the maximum heights on a curve for this terrain generation
@export var elevation_curve: Curve
## Use an image to smooth the edges on this terrain. Useful if you want to connect other plots of land
@export var falloff_texture: CompressedTexture2D
