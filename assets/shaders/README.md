# wezterm-crt: cool-retro-term visuals for wezterm

This directory contains a full port of
[cool-retro-term](https://github.com/Swordfish90/cool-retro-term)'s CRT
effects to wezterm's WebGPU post-processing pipeline.

**Effects:** screen curvature, scanline/pixel/subpixel rasterization,
bloom, burn-in (phosphor trails), static noise, jitter, glowing scan
line, screen flicker, horizontal sync distortion, RGB shift,
chroma/monochrome phosphor palettes, and a bezel frame with ambient
light and reflections.

## Quick start

Copy `crt.lua` and `crt.wgsl` into your wezterm config directory, then
in `wezterm.lua`:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local crt = dofile(wezterm.config_dir .. '/crt.lua')
crt.apply_to_config(config, { preset = 'monochrome_green' })

return config
```

`apply_to_config` generates a parameterized shader next to `crt.lua`
and sets:

- `front_end = "WebGpu"` (required for custom shaders)
- `custom_shaders` pointing at the generated shader
- `custom_shader_burn_in`, `custom_shader_bloom`, `custom_shader_fps`

## Presets

All of cool-retro-term's built-in profiles are included:

| preset | look |
|---|---|
| `default_amber` | amber phosphor, soft bloom |
| `monochrome_green` | classic green phosphor (default) |
| `deep_blue` | blue-white with strong curvature |
| `commodore_64` | blue-on-blue, scanlines, chunky bezel |
| `commodore_pet` | white phosphor, heavy curvature and flicker |
| `apple_ii` | green phosphor, strong ambient light |
| `atari_400` | blue-cyan, scanlines |
| `ibm_vga` | grey-white DOS look with RGB shift |
| `ibm_3278` | calm green terminal, long burn-in |
| `neon_cyan` | modern cyan glow |
| `ghost_terminal` | subtle grey, low contrast |
| `plasma` | pink-purple glow with RGB shift |
| `boring` | white, minimal artifacts |
| `e_ink` | dark-on-paper, long burn-in |
| `full_color` | keeps your wezterm color scheme, adds CRT hardware look |

Every field below can be overridden per call. Names and 0..1 ranges
match cool-retro-term's Effects / Screen sliders (snake_case instead
of camelCase). CRT's `rbgShift` typo is `rgb_shift` here.

```lua
crt.apply_to_config(config, {
  preset = 'full_color',
  -- any field from the tables below
  screen_curvature = 0.4,
  bloom = 0.6,
  burn_in = 0.4,
})
```

### Effects (cool-retro-term Effects tab)

| option | range | what it does |
|---|---|---|
| `bloom` | 0..1 | phosphor glow / gaussian bloom. `0` disables the bloom pass |
| `burn_in` | 0..1 | phosphor trail length. `0` disables the burn-in pass |
| `static_noise` | 0..1 | analog snow, stronger toward screen center |
| `jitter` | 0..1 | per-pixel image shake |
| `glowing_line` | 0..1 | travelling bright scan line |
| `screen_curvature` | 0..1 | barrel distortion |
| `ambient_light` | 0..1 | room light on the bezel / glass glare (needs `frame_size` > 0) |
| `flickering` | 0..1 | whole-screen brightness flicker |
| `horizontal_sync` | 0..1 | occasional horizontal tearing / displacement |
| `rgb_shift` | 0..1 | RGB gun misconvergence (CRT's `rbgShift`) |
| `frame_shininess` | 0..1 | glossy bezel + screen-edge reflections |

### Phosphor / color (cool-retro-term Screen tab)

| option | range | what it does |
|---|---|---|
| `font_color` | `#rrggbb` | phosphor / foreground tint |
| `background_color` | `#rrggbb` | tube background |
| `chroma_color` | 0..1 | `0` = monochrome phosphor, `1` = keep source hues |
| `saturation_color` | 0..1 | mix phosphor toward white before contrast |
| `contrast` | 0..1 | mix between font and background colors |
| `brightness` | 0..1 | overall gain after flicker (`0.5` is neutral) |
| `rasterization` | see right | `none` \| `scanlines` \| `pixels` \| `subpixels` |

`full_color` is `chroma_color = 1` + white `font_color`: your wezterm
color scheme stays, CRT hardware effects still apply.

### Frame / geometry

| option | range | what it does |
|---|---|---|
| `frame_size` | 0..1 | bezel thickness. `0` hides the frame (CRT `frameMargin`) |
| `frame_color` | `#rrggbb` | bezel color, mixed with ambient light |
| `screen_radius` | 0..1 | rounded tube corners |
| `virtual_pixel_size` | px, default `3` | device pixels per virtual CRT pixel. Scanlines fade out as this approaches `2` |

### `apply_to_config` extras (not from CRT)

| option | default | what it does |
|---|---|---|
| `preset` | `monochrome_green` | starting profile; overrides apply on top |
| `fps` | `60` | shader animation cap (`custom_shader_fps`) |
| `output_path` | `crt-generated-<preset>.wgsl` next to `crt.lua` | where the baked shader is written |
| `template_path` | `crt.wgsl` next to `crt.lua` | shader template |

### Use wezterm for these CRT settings

Not ported on purpose — set them in `wezterm.lua` instead:

| cool-retro-term | wezterm |
|---|---|
| `fontName` / `fontWidth` / `fontScaling` | `config.font`, `config.font_size`, `config.cell_width` |
| `windowOpacity` | `config.window_background_opacity` |
| `margin` | `config.window_padding` |
| `blinkingCursor` | `config.default_cursor_style`, `config.cursor_blink_rate` |
| window `width` / `height` | `config.initial_cols`, `config.initial_rows` |

## Using the shader directly

`crt.wgsl` works standalone with its built-in defaults:

```lua
config.front_end = 'WebGpu'
config.custom_shaders = { wezterm.config_dir .. '/crt.wgsl' }
config.custom_shader_burn_in = 0.3
config.custom_shader_bloom = true
```

Edit the constants in the `CRT PARAMS` block to taste; the file is
hot-reloaded on save when `automatically_reload_config` is enabled.

## How it works

The upstream-pending `custom_shaders` pipeline (PR
[#7649](https://github.com/wezterm/wezterm/pull/7649)) renders the
terminal to an intermediate texture and runs user WGSL passes over it.
This fork extends the pipeline with two built-in stages, both ported
from cool-retro-term:

- **burn-in** (`custom_shader_burn_in`): a pair of persistent textures
  ping-ponged across frames; each frame the previous accumulation is
  decayed and `max()`ed with the new frame, then exposed to user
  shaders as `burnin_texture`
- **bloom** (`custom_shader_bloom`): a quarter-resolution separable
  gaussian blur of the terminal render, exposed as `bloom_texture`

`crt.lua` bakes profile parameters into shader constants, mirroring the
same derived-color math that cool-retro-term applies in QML
(saturation/contrast premixing, ambient-light frame tinting).

## Keeping the fork up to date

This tree carries a short commit series on top of upstream `main`
(commit `9c04f79f`), in this order:

1. the `custom_shaders` pipeline (based on upstream PR #7649)
2. burn-in/bloom/fps pipeline extensions
3. the CRT shader, Lua presets, and docs
4. follow-up fixes (config-reload fingerprinting, unfocused-animation
   repaints) and CI `workflow_dispatch` triggers

To rebase onto latest upstream:

```sh
git remote add upstream https://github.com/wezterm/wezterm.git
git fetch upstream main
git rebase upstream/main
cargo test -p config -p wezterm-gui
```

If upstream merges PR #7649, drop the first commit during the rebase
(`git rebase --onto origin/main <pick-commit>`) and keep the rest.

## Release builds via CI

The fork reuses wezterm's own build workflows. The
`*_continuous` workflows (`gen_<platform>_continuous.yml`) have a
`workflow_dispatch` trigger added, so you can build installable
packages for any branch without waiting for the nightly cron:

1. Go to **Actions**, pick the platform workflow (e.g.
   `ubuntu24.04_continuous`, `macos_continuous`,
   `windows_continuous`), press **Run workflow**, and select the
   branch to build.
2. The build job attaches the packages (`.deb`/`.rpm`/`.AppImage`,
   `.zip` for macOS/Windows) as workflow artifacts, downloadable from
   the run page for 5 days.

The final "upload to nightly release" job is conditioned on running in
the upstream `wezterm/wezterm` repository and is skipped elsewhere;
the artifacts from step 2 are the deliverable. Upstream's tag
workflows (`gen_<platform>_tag.yml`, versioned releases on `20*` tags)
are available in git history if you want that release flow too.

## License note

The shader logic in `crt.wgsl` is derived from cool-retro-term's GLSL
shaders, which are GPL-3.0 licensed; cool-retro-term is by Filippo
Scognamiglio. wezterm itself is MIT licensed; treat `crt.wgsl` and
`crt.lua` as GPL-3.0 derived works if you redistribute them.
