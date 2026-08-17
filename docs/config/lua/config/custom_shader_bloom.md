---
tags:
  - appearance
---
# `custom_shader_bloom = false`

*Unreleased fork feature*

When `true`, wezterm renders a quarter-resolution, gaussian-blurred copy
of the terminal each frame for use by [custom_shaders](custom_shaders.md).
Shaders sample it via `bloom_texture` to implement true bloom (soft
phosphor glow around bright content) without paying for a large blur
kernel at full resolution.

```lua
config.custom_shader_bloom = true
```

A typical shader use:

```wgsl
let bloom = textureSample(bloom_texture, screen_sampler, uv);
color += clamp(bloom.rgb * strength, vec3<f32>(0.0), vec3<f32>(0.5));
```
