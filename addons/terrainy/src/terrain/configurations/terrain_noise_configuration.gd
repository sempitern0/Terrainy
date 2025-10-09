class_name TerrainNoiseConfiguration extends TerrainConfiguration

## It only applies when FastNoiseLite is used to generate the terrain
@export var randomize_noise_seed: bool = false
## Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.
## Rocky: +Octaves -Period, Hills: -Octaves +Period
@export var noise: FastNoiseLite
