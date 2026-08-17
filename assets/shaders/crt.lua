-- crt.lua: cool-retro-term style CRT effects for wezterm.
--
-- Generates a parameterized variant of crt.wgsl and wires up the
-- post-processing pipeline (WebGpu front end, custom_shaders,
-- burn-in accumulation, bloom).
--
-- Usage in wezterm.lua:
--
--   local crt = dofile(wezterm.config_dir .. "/crt.lua")
--   crt.apply_to_config(config, {
--     preset = "ibm_dos",  -- see crt.presets; default
--     -- any field below can be overridden
--   })
--
-- Presets are ports of cool-retro-term's built-in profiles.
-- The "full_color" preset keeps wezterm's own colors while adding the
-- CRT hardware look (curvature, scanlines, bloom, burn-in, noise).
--
-- All cool-retro-term sliders (snake_case). Ranges are 0..1 unless noted.
-- Full descriptions: assets/shaders/README.md
--
--   Effects tab:
--     bloom, burn_in, static_noise, jitter, glowing_line,
--     screen_curvature, ambient_light, flickering, horizontal_sync,
--     rgb_shift (CRT's rbgShift), frame_shininess
--   Screen / phosphor:
--     font_color "#rrggbb", background_color "#rrggbb",
--     chroma_color, saturation_color, contrast, brightness,
--     rasterization = "none"|"scanlines"|"pixels"|"subpixels"
--   Frame / geometry:
--     frame_size (CRT frameMargin; 0 hides bezel), frame_color "#rrggbb",
--     screen_radius, virtual_pixel_size (device px, default 3)
--   apply_to_config extras:
--     preset, fps (default 30), output_path, template_path
--
-- Not ported (use wezterm.lua): font, opacity, padding, cursor, cols/rows.

local M = {}

local RASTER_MODES = {
  none = 0,
  scanlines = 1,
  pixels = 2,
  subpixels = 3,
}

-- Profile fields mirror cool-retro-term's setting names/ranges (0..1
-- unless noted). Colors are "#rrggbb" strings.
M.presets = {
  default_amber = {
    ambient_light = 0.3, background_color = "#000000", bloom = 0.6,
    brightness = 0.5, burn_in = 0.3, chroma_color = 0.2, contrast = 0.8,
    flickering = 0.1, font_color = "#ff8100", glowing_line = 0.2,
    horizontal_sync = 0.1, jitter = 0.2, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.2, screen_curvature = 0.2,
    screen_radius = 0.1, static_noise = 0.1, frame_size = 0.1,
    frame_color = "#cfcfcf", frame_shininess = 0.3,
  },
  monochrome_green = {
    ambient_light = 0.3, background_color = "#000000", bloom = 0.5,
    brightness = 0.5, burn_in = 0.3, chroma_color = 0.0, contrast = 0.8,
    flickering = 0.1, font_color = "#0ccc68", glowing_line = 0.2,
    horizontal_sync = 0.1, jitter = 0.2, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.0, screen_curvature = 0.3,
    screen_radius = 0.2, static_noise = 0.1, frame_size = 0.1,
    frame_color = "#d4d4d4", frame_shininess = 0.1,
  },
  deep_blue = {
    ambient_light = 0.0, background_color = "#000000", bloom = 0.6,
    brightness = 0.5, burn_in = 0.3, chroma_color = 1.0, contrast = 0.8,
    flickering = 0.1, font_color = "#7fb4ff", glowing_line = 0.2,
    horizontal_sync = 0.1, jitter = 0.2, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.2, screen_curvature = 0.4,
    screen_radius = 0.1, static_noise = 0.1, frame_size = 0.1,
    frame_color = "#ffffff", frame_shininess = 0.9,
  },
  commodore_64 = {
    ambient_light = 0.4, background_color = "#3b3b8f", bloom = 0.4,
    brightness = 0.6, burn_in = 0.1, chroma_color = 0.0, contrast = 0.7,
    flickering = 0.1, font_color = "#a9a7ff", glowing_line = 0.1,
    horizontal_sync = 0.0, jitter = 0.0, rasterization = "scanlines",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0.5,
    screen_radius = 0.1, static_noise = 0.1, frame_size = 0.5,
    frame_color = "#999999", frame_shininess = 0.0,
  },
  commodore_pet = {
    ambient_light = 0.0, background_color = "#000000", bloom = 0.4,
    brightness = 0.5, burn_in = 0.4, chroma_color = 0, contrast = 0.8,
    flickering = 0.2, font_color = "#ffffff", glowing_line = 0.3,
    horizontal_sync = 0.2, jitter = 0.15, rasterization = "scanlines",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0.7,
    screen_radius = 0.3, static_noise = 0.2, frame_size = 0.5,
    frame_color = "#000000", frame_shininess = 0.6,
  },
  apple_ii = {
    ambient_light = 1.0, background_color = "#001100", bloom = 0.3,
    brightness = 0.5, burn_in = 0.3, chroma_color = 0, contrast = 0.8,
    flickering = 0.2, font_color = "#4dff6b", glowing_line = 0.3,
    horizontal_sync = 0.2, jitter = 0.2, rasterization = "scanlines",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0.5,
    screen_radius = 0.3, static_noise = 0.2, frame_size = 0.2,
    frame_color = "#ffffff", frame_shininess = 0.8,
  },
  atari_400 = {
    ambient_light = 0.1, background_color = "#0f1f5a", bloom = 0.1,
    brightness = 0.6, burn_in = 0.2, chroma_color = 0, contrast = 0.9,
    flickering = 0.1, font_color = "#8ed6ff", glowing_line = 0.1,
    horizontal_sync = 0.0, jitter = 0.0, rasterization = "scanlines",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0.4,
    screen_radius = 0.2, static_noise = 0.1, frame_size = 0.4,
    frame_color = "#cccccc", frame_shininess = 0.3,
  },
  ibm_vga = {
    ambient_light = 0.2, background_color = "#000000", bloom = 0.2,
    brightness = 0.6, burn_in = 0.1, chroma_color = 0.5, contrast = 1.0,
    flickering = 0.1, font_color = "#c0c0c0", glowing_line = 0.1,
    horizontal_sync = 0.0, jitter = 0.0, rasterization = "scanlines",
    rgb_shift = 0.1, saturation_color = 0, screen_curvature = 0.3,
    screen_radius = 0.1, static_noise = 0.0, frame_size = 0.1,
    frame_color = "#ffffff", frame_shininess = 0.3,
  },
  -- cool-retro-term "IBM Dos" with the tuned Effects / Screen / Performance
  -- sliders used as wezterm-crt stock defaults: full-color phosphor, no
  -- bezel, bloom + RGB shift + flicker, 30 FPS.
  ibm_dos = {
    ambient_light = 0.0, background_color = "#000000", bloom = 0.36,
    brightness = 0.56, burn_in = 0.0, chroma_color = 1.0, contrast = 0.95,
    flickering = 0.19, font_color = "#ffffff", glowing_line = 0.0,
    horizontal_sync = 0.0, jitter = 0.20, rasterization = "none",
    rgb_shift = 0.30, saturation_color = 0.0, screen_curvature = 0.0,
    screen_radius = 0.0, static_noise = 0.0, frame_size = 0.0,
    frame_color = "#ffffff", frame_shininess = 0.2,
    fps = 30,
  },
  ibm_3278 = {
    ambient_light = 0.2, background_color = "#000000", bloom = 0.2,
    brightness = 0.5, burn_in = 0.5, chroma_color = 0, contrast = 0.8,
    flickering = 0, font_color = "#3cff7a", glowing_line = 0.0,
    horizontal_sync = 0, jitter = 0, rasterization = "none",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.0, frame_size = 0,
    frame_color = "#ffffff", frame_shininess = 0.2,
  },
  neon_cyan = {
    ambient_light = 0.1, background_color = "#001018", bloom = 0.6,
    brightness = 0.6, burn_in = 0.1, chroma_color = 1, contrast = 0.9,
    flickering = 0.1, font_color = "#52f7ff", glowing_line = 0.2,
    horizontal_sync = 0.0, jitter = 0.1, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.6, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.1, frame_size = 0,
    frame_color = "#c3c3c3", frame_shininess = 0.2,
  },
  ghost_terminal = {
    ambient_light = 0.3, background_color = "#0b1014", bloom = 0.3,
    brightness = 0.6, burn_in = 0.2, chroma_color = 0, contrast = 0.5,
    flickering = 0.0, font_color = "#a6b3c0", glowing_line = 0.1,
    horizontal_sync = 0.0, jitter = 0.0, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.0, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.1, frame_size = 0,
    frame_color = "#a7a7a7", frame_shininess = 0.2,
  },
  plasma = {
    ambient_light = 0.1, background_color = "#070014", bloom = 0.7,
    brightness = 0.6, burn_in = 0.1, chroma_color = 1, contrast = 0.8,
    flickering = 0.1, font_color = "#ff9bd6", glowing_line = 0.2,
    horizontal_sync = 0.0, jitter = 0.1, rasterization = "none",
    rgb_shift = 0.1, saturation_color = 0.8, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.1, frame_size = 0,
    frame_color = "#d0d0d0", frame_shininess = 0.2,
  },
  boring = {
    ambient_light = 0.1, background_color = "#000000", bloom = 0.5,
    brightness = 0.5, burn_in = 0.05, chroma_color = 1, contrast = 0.8,
    flickering = 0.0, font_color = "#ffffff", glowing_line = 0.1,
    horizontal_sync = 0, jitter = 0.0, rasterization = "none",
    rgb_shift = 0, saturation_color = 0.0, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.0, frame_size = 0,
    frame_color = "#c0c0c0", frame_shininess = 0.2,
  },
  e_ink = {
    ambient_light = 0.6, background_color = "#f2f2ec", bloom = 0.0,
    brightness = 1.0, burn_in = 0.6, chroma_color = 0, contrast = 0.5,
    flickering = 0.0, font_color = "#101010", glowing_line = 0.0,
    horizontal_sync = 0.0, jitter = 0.0, rasterization = "none",
    rgb_shift = 0, saturation_color = 0, screen_curvature = 0,
    screen_radius = 0.0, static_noise = 0.0, frame_size = 0,
    frame_color = "#cdcdcd", frame_shininess = 0.2,
  },
  -- Not from cool-retro-term: keeps wezterm's own color scheme
  -- (chroma = 1 with a white phosphor preserves source hues) while
  -- layering on the CRT hardware look.
  full_color = {
    ambient_light = 0.2, background_color = "#000000", bloom = 0.4,
    brightness = 0.5, burn_in = 0.25, chroma_color = 1.0, contrast = 0.9,
    flickering = 0.07, font_color = "#ffffff", glowing_line = 0.1,
    horizontal_sync = 0.05, jitter = 0.08, rasterization = "scanlines",
    rgb_shift = 0.05, saturation_color = 1.0, screen_curvature = 0.2,
    screen_radius = 0.1, static_noise = 0.05, frame_size = 0.1,
    frame_color = "#888888", frame_shininess = 0.3,
  },
}

M.default_preset = "ibm_dos"

-- ---------------------------------------------------------------------
-- color helpers
-- ---------------------------------------------------------------------

local function parse_color(hex)
  local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
  assert(r, "invalid color: " .. tostring(hex))
  return {
    tonumber(r, 16) / 255,
    tonumber(g, 16) / 255,
    tonumber(b, 16) / 255,
  }
end

local function mix(a, b, x)
  return {
    a[1] + (b[1] - a[1]) * x,
    a[2] + (b[2] - a[2]) * x,
    a[3] + (b[3] - a[3]) * x,
  }
end

local function scale(c, f)
  return { c[1] * f, c[2] * f, c[3] * f }
end

local function add(c, v)
  return {
    math.min(c[1] + v, 1.0),
    math.min(c[2] + v, 1.0),
    math.min(c[3] + v, 1.0),
  }
end

local function vec3(c)
  return string.format("vec3<f32>(%.4f, %.4f, %.4f)", c[1], c[2], c[3])
end

local function num(v)
  return string.format("%.4f", v)
end

-- ---------------------------------------------------------------------
-- shader generation
-- ---------------------------------------------------------------------

-- Compute the shader parameter block from a profile, applying the same
-- derived-color math as cool-retro-term's ApplicationSettings.qml and
-- TerminalFrame.qml.
function M.compute_params(p)
  local white = { 1, 1, 1 }
  local font = parse_color(p.font_color)
  local bg = parse_color(p.background_color)

  local saturated = mix(font, white, (p.saturation_color or 0) * 0.5)
  local contrast_mix = 0.7 + (p.contrast or 0.8) * 0.3
  local font_final = mix(bg, saturated, contrast_mix)
  local bg_final = mix(saturated, bg, contrast_mix)

  local light = mix(font_final, bg_final, 0.2)
  local static_frame = add(parse_color(p.frame_color or "#cfcfcf"), 0.1)
  local frame_final = mix(
    scale(light, 0.2),
    static_frame,
    0.125 + 0.75 * (p.ambient_light or 0)
  )

  local raster = p.rasterization or "none"
  if type(raster) == "string" then
    raster = RASTER_MODES[raster]
      or error("invalid rasterization: " .. tostring(p.rasterization))
  end

  return {
    AMBIENT_LIGHT = num(p.ambient_light or 0),
    BLOOM = num(p.bloom or 0),
    BRIGHTNESS = num(p.brightness or 0.5),
    CHROMA_COLOR = num(p.chroma_color or 0),
    FLICKERING = num(p.flickering or 0),
    FONT_COLOR = vec3(font_final),
    BACKGROUND_COLOR = vec3(bg_final),
    FRAME_COLOR = vec3(frame_final),
    FRAME_SHININESS = num(p.frame_shininess or 0),
    FRAME_SIZE = num((p.frame_size or 0) * 0.05),
    GLOWING_LINE = num(p.glowing_line or 0),
    HORIZONTAL_SYNC = num(p.horizontal_sync or 0),
    JITTER = num(p.jitter or 0),
    RASTERIZATION = tostring(raster),
    RGB_SHIFT = num((p.rgb_shift or 0) * 2.5),
    SCREEN_CURVATURE = num((p.screen_curvature or 0) * 0.4),
    SCREEN_RADIUS = num(p.screen_radius or 0),
    STATIC_NOISE = num(p.static_noise or 0),
    VIRTUAL_PIXEL_SIZE = num(p.virtual_pixel_size or 3.0),
  }
end

local PARAM_TYPES = {
  FONT_COLOR = "vec3<f32>",
  BACKGROUND_COLOR = "vec3<f32>",
  FRAME_COLOR = "vec3<f32>",
  RASTERIZATION = "i32",
}

-- Splice computed parameter values into the template's params block.
function M.generate_shader(template, params)
  local begin_marker = "// %-%- BEGIN CRT PARAMS %-%- *\n"
  local end_marker = "\n// %-%- END CRT PARAMS %-%-"

  local head_start = template:find(begin_marker)
  local _, block_end = template:find(end_marker)
  assert(head_start and block_end, "crt.wgsl template is missing the CRT PARAMS markers")

  local lines = { "// -- BEGIN CRT PARAMS --" }
  local names = {}
  for name in pairs(params) do
    table.insert(names, name)
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local ty = PARAM_TYPES[name] or "f32"
    table.insert(lines, string.format("const %s: %s = %s;", name, ty, params[name]))
  end
  table.insert(lines, "// -- END CRT PARAMS --")

  return template:sub(1, head_start - 1)
    .. table.concat(lines, "\n")
    .. template:sub(block_end + 1)
end

-- wezterm's Lua sandbox does not expose the `debug` library, so fall
-- back to the wezterm config directory when we can't introspect our
-- own path.
local function script_dir()
  if type(debug) == "table" and debug.getinfo then
    local source = debug.getinfo(1, "S").source
    local path = source:match("^@(.*)$") or source
    local dir = path:match("^(.*)[/\\]")
    if dir then
      return dir
    end
  end
  local ok, wezterm = pcall(require, "wezterm")
  if ok and wezterm.config_dir then
    return wezterm.config_dir
  end
  return "."
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- ---------------------------------------------------------------------
-- public entry point
-- ---------------------------------------------------------------------

-- opts:
--   preset: name from M.presets (default "ibm_dos")
--   output_path: where to write the generated shader
--     (default: alongside this file, named crt-generated-<preset>.wgsl)
--   template_path: the crt.wgsl template
--     (default: crt.wgsl alongside this file)
--   fps: repaint rate cap for the animation (default 30)
--   any profile field (screen_curvature, bloom, font_color, ...) to
--   override the preset value.
function M.apply_to_config(config, opts)
  opts = opts or {}
  local preset_name = opts.preset or M.default_preset
  local preset = M.presets[preset_name]
  if not preset then
    error("unknown CRT preset: " .. tostring(preset_name))
  end

  local profile = {}
  for k, v in pairs(preset) do
    profile[k] = v
  end
  for k, v in pairs(opts) do
    if k ~= "preset" and k ~= "output_path" and k ~= "template_path" and k ~= "fps" then
      profile[k] = v
    end
  end

  local dir = script_dir()
  local template_path = opts.template_path or (dir .. "/crt.wgsl")
  local template = read_file(template_path)
  if not template then
    error("cannot read CRT shader template at " .. template_path)
  end

  local shader = M.generate_shader(template, M.compute_params(profile))

  local output_path = opts.output_path
    or (dir .. "/crt-generated-" .. preset_name .. ".wgsl")

  -- Only rewrite when the content changed, so that wezterm's config
  -- file watcher doesn't loop on our own writes.
  if read_file(output_path) ~= shader then
    local f, err = io.open(output_path, "wb")
    if not f then
      error("cannot write generated CRT shader to " .. output_path .. ": " .. tostring(err))
    end
    f:write(shader)
    f:close()
  end

  config.front_end = "WebGpu"
  config.custom_shaders = { output_path }
  config.custom_shader_burn_in = profile.burn_in or 0
  config.custom_shader_bloom = (profile.bloom or 0) > 0
  config.custom_shader_fps = opts.fps or profile.fps or 30

  return config
end

return M
