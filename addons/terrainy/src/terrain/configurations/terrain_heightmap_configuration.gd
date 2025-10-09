class_name TerrainHeightmapConfiguration extends TerrainConfiguration

## Use a valid heightmap image to generate the terrain mesh.
@export var heightmap_image: Texture2D
## Auto scale the correct height from the heightmap for a more accurate result.
@export var auto_scale_heightmap_image: bool = true
