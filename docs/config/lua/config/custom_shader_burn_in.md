---
tags:
  - appearance
---
# `custom_shader_burn_in = 0.0`

*Unreleased fork feature*

Enables phosphor-persistence ("burn-in") accumulation for
[custom_shaders](custom_shaders.md), in the range `0.0` (disabled) to
`1.0` (longest trails).

When non-zero, wezterm maintains a persistent accumulation texture:
every frame, the previous accumulation decays toward black and is
`max()`ed with the freshly rendered terminal, replicating
cool-retro-term's burn-in effect. Custom shaders can sample the result
via `burnin_texture`; its alpha channel holds a mask of pixels that are
currently lit.

The decay time ranges from 0.16 seconds (`0.0`) to 1.6 seconds (`1.0`);
the reciprocal decay rate is available to shaders as `pp.burn_in_time`.

```lua
config.custom_shader_burn_in = 0.3
```

A typical shader use:

```wgsl
let burn = textureSample(burnin_texture, screen_sampler, uv);
let decay = clamp(pp.time_delta * pp.burn_in_time, 0.0, 1.0);
let burn_color = 0.65 * (burn.rgb - vec3<f32>(decay)) * (1.0 - burn.a);
color = max(color, burn_color);
```
