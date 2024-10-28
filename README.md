<div align="center">
	<img src="icon.svg" alt="Logo" width="160" height="160">

<h3 align="center">Terrainy</h3>

  <p align="center">
   Quickly create natural-looking terrain with customizable noise parameters
	<br />
	·
	<a href="https://github.com/ninetailsrabbit/terrainy/issues/new?assignees=ninetailsrabbit&labels=%F0%9F%90%9B+bug&projects=&template=bug_report.md&title=">Report Bug</a>
	·
	<a href="https://github.com/ninetailsrabbit/terrainy/issues/new?assignees=ninetailsrabbit&labels=%E2%AD%90+feature&projects=&template=feature_request.md&title=">Request Features</a>
  </p>
</div>

<br>
<br>

- [📦 Installation](#-installation)
  - [](#)
- [Getting started 📝](#getting-started-)
  - [Parameters 🗻](#parameters-)
    - [Mesh resolution](#mesh-resolution)
    - [Size depth](#size-depth)
    - [Size width](#size-width)
    - [Max terrain height](#max-terrain-height)
    - [Target Mesh](#target-mesh)
    - [Terrain Material](#terrain-material)
    - [Noise](#noise)
- [Shader materials 🏞️](#shader-materials-️)
  - [Albedo terrain mix](#albedo-terrain-mix)

# 📦 Installation

1. [Download Latest Release](https://github.com/ninetailsrabbit/terrainy/releases/latest)
2. Unpack the `addons/ninetailsrabbit.terrainy` folder into your `/addons` folder within the Godot project
3. Enable this addon within the Godot settings: `Project > Project Settings > Plugins`

To better understand what branch to choose from for which Godot version, please refer to this table:
|Godot Version|terrainy Branch|terrainy Version|
|---|---|--|
|[![GodotEngine](https://img.shields.io/badge/Godot_4.3.x_stable-blue?logo=godotengine&logoColor=white)](https://godotengine.org/)|`main`|`1.x`|

---

## ![](images/terrainy_showcase.gif)

# Getting started 📝

Creating a new terrain is as easy as adding the `Terrainy` node into your scene.

This node will warn you in the editor that it needs:

- A `target mesh` representing a `MeshInstance3D` from which you want to generate the terrain.
- A `noise` value with an instance of `FastNoiseLite` which is used as a template for generating the terrain surface.

**_If you try to generate a terrain without this values a warning will be pushed to the output window but it does not interrupt the execution of your game._**

## Parameters 🗻

![terrainy_parameters](images/terrainy_parameters.png)

### Mesh resolution

More resolution means more detail _(more dense vertex)_ in the terrain generation, this increases the mesh subdivisions and could reduce the performance in low-spec pcs.

### Size depth

The depth size of the mesh (z) in godot units (meters)

### Size width

The width size of the mesh (x) in godot units (meters)

### Max terrain height

The maximum height (y) at which this terrain can be generated in godot units (meters)

### Target Mesh

The target `MeshInstance3D` where the mesh will be generated. If no `Mesh` for it is defined, a new `PlaneMesh` is created by default.

It only supports `PlaneMesh` `QuadMesh`, `BoxMesh` and `PrismMesh`, otherwise, the `Mesh` will be deleted and a `PlaneMesh` will be assigned for terrain generation.

### Terrain Material

This is the material that will be applied to the Terrain. Take a look on [Shader material](#shader-material) examples to get a detailed terrain surface mixing textures.

### Noise

This is a [FastNoiseLite](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html#fastnoiselite) instance. Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.

Play with the parameters and different types of noise to get the result you want.

# Shader materials 🏞️

When you generate the terrain with a `StandardMaterial3D` the result will be simple and with a single colour unless you use gradients.

This can be useful for some cases where you don't need a lot of detail but if you need something more advanced there are some shaders that can help us.

## Albedo terrain mix

This shader can be found on [https://godotshaders.com/shader/albedo-terrain-mix-shader/](https://godotshaders.com/shader/albedo-terrain-mix-shader/)

I paste it here just for backup purposes in case **GodotShaders** is gone. I modified the `uv_size` to support a higher value range, which will be necessary if you use low-poly textures.

```csharp
shader_type spatial;

uniform sampler2D source_texture_mask : source_color;
uniform sampler2D source_texture_black : source_color;
uniform sampler2D source_texture_red : source_color;
uniform sampler2D source_texture_green : source_color;
uniform sampler2D source_texture_blue : source_color;

uniform float uv_size : hint_range(0.01, 100.0, 0.01) = 1.0;

void fragment() {

vec2 UV_Scaled = UV * uv_size;

// texture_rgbmask UV is not scaled.
vec3 texture_rgbmask = texture(source_texture_mask, UV).rgb;
vec3 texture_black 	= texture(source_texture_black, UV_Scaled).rgb;
vec3 texture_red 	= texture(source_texture_red, UV_Scaled).rgb;
vec3 texture_green 	= texture(source_texture_green, UV_Scaled).rgb;
vec3 texture_blue 	= texture(source_texture_blue, UV_Scaled).rgb;

float summed_texture_channels = (
	texture_rgbmask.r +
	texture_rgbmask.g +
	texture_rgbmask.b);

vec3 mixed_terrain = clamp(
		(	texture_rgbmask.r * texture_red +
			texture_rgbmask.g * texture_green +
			texture_rgbmask.b * texture_blue) /
			summed_texture_channels,
			vec3(0.0), vec3(1.0) // Clamp min, max values.
			);

ALBEDO = mix(mixed_terrain,texture_black,1.0 - summed_texture_channels);

} // Fragment end

```

There is a well explained tutorial of the creator, He uses a terrain already imported from blender, **it works the same with a mesh generated by this plugin.**

[![albedo_mix_youtube_tutorial](http://img.youtube.com/vi/MaVweI30Qo4/0.jpg)](http://www.youtube.com/watch?v=MaVweI30Qo4 "Albedo mix shader tutorial")
