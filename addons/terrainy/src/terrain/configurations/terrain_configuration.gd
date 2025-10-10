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
@export var size_depth: int = 256:
	set(value):
		if value != size_depth:
			size_depth = maxi(1, value)
			
## The width size of the mesh (x) in godot units (meters)
@export var size_width: int = 256:
	set(value):
		if value != size_width:
			size_width = maxi(1, value)
			
## The maximum height of this terrain
@export var max_terrain_height: float = 50.0:
	set(value):
		if value != max_terrain_height:
			max_terrain_height = maxf(0.5, value)
## The terrain material that will be applied on the surface
@export var terrain_material: Material
#@export_group("LODs") ## TODO - Pending until godot provide a solution for LODs on ArrayMesh created from SurfaceTool
#@export var generate_lods: bool = true
### Level of details to generate, more lod count needs more initial memory (more meshes)
#@export var lod_count: int = 2
### Reduction factor on each level, 2 means half of the vertex from the previous lod
#@export var lod_reduction_factor: int = 2.0
### Step distance to camera to apply lod levels
#@export var lod_distance_step: float = 150.0
@export_group("Shape")
## Manage the maximum heights on a curve for this terrain generation
@export var elevation_curve: Curve
## Use an image to smooth the edges on this terrain. Useful if you want to connect other plots of land
@export var falloff_texture: Texture2D
@export_group("Radial")
## Generate the terrain around a circular shape to avoid cubic results
@export var radial_shape: bool = false
@export_range(0.5, 4.0, 0.1) var radial_falloff_power: float = 2.0
@export_group("Mirror Terrain")
## Generate a mirrored terrain below the original terrain mesh
@export var generate_mirror: bool = false
@export var mirror_collision_type: TerrainyCore.CollisionType = TerrainyCore.CollisionType.None
## The mirror offset allows to avoid shadow artifacts when 2 meshes are glue together. 
@export_range(0.01, 100.0, 0.01) var mirror_offset: float = 0.01
## The height to the bottom of the mirror mesh.
@export var mirror_depth: float = 5.0
## Useful if you want to create a variant for the bottom part for a more organic result.
@export var mirror_noise: FastNoiseLite
@export var mirror_material: Material
