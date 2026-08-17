---
tags:
  - appearance
---
# `custom_shaders = {}`

*Unreleased fork feature*

Specifies a list of paths to WGSL fragment shaders that are applied, in
order, as post-processing passes over the rendered terminal output.

Only works with `front_end = "WebGpu"`.

```lua
config.front_end = "WebGpu"
config.custom_shaders = {
  wezterm.config_dir .. "/shaders/crt.wgsl",
}
```

Each shader file only needs to define an `fs_postprocess` entry point;
the pipeline automatically prepends the following declarations:

```wgsl
struct PostProcessUniform {
    resolution: vec2<f32>,  // window size in pixels
    time: f32,              // seconds since the window was created
    time_delta: f32,        // seconds since the previous frame
    frame: u32,             // frame counter
    burn_in_time: f32,      // burn-in decay rate; see custom_shader_burn_in
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var screen_texture: texture_2d<f32>;
@group(0) @binding(1) var screen_sampler: sampler;
@group(0) @binding(2) var burnin_texture: texture_2d<f32>;
@group(0) @binding(3) var bloom_texture: texture_2d<f32>;

@group(1) @binding(0) var<uniform> pp: PostProcessUniform;
```

A minimal pass-through shader:

```wgsl
@fragment
fn fs_postprocess(in: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(screen_texture, screen_sampler, in.uv);
}
```

`burnin_texture` and `bloom_texture` are bound to 1x1 black textures
unless enabled via [custom_shader_burn_in](custom_shader_burn_in.md) and
[custom_shader_bloom](custom_shader_bloom.md).

Shader files are watched for changes and hot-reloaded when
[automatically_reload_config](automatically_reload_config.md) is enabled.

See `assets/shaders/crt.wgsl` and `assets/shaders/crt.lua` in the source
tree for a complete cool-retro-term style CRT effect with presets.
