// wezterm-crt: a port of cool-retro-term's CRT effects to wezterm's
// post-processing pipeline.
//
// Usage (wezterm.lua):
//   local crt = dofile("/path/to/wezterm/assets/shaders/crt.lua")
//   crt.apply_to_config(config, { preset = "ibm_dos" })
//
// or use this file directly with the built-in default look:
//   config.front_end = "WebGpu"
//   config.custom_shaders = { "/path/to/crt.wgsl" }
//   config.custom_shader_burn_in = 0.0   -- phosphor trails
//   config.custom_shader_bloom = true    -- true gaussian bloom
//
// The struct/binding declarations (screen_texture, burnin_texture,
// bloom_texture, pp uniform) are auto-prepended by wezterm.
//
// Ported from cool-retro-term (GPLv3):
// https://github.com/Swordfish90/cool-retro-term
// Effects: screen curvature, scanline/pixel/subpixel rasterization,
// static noise, jitter, glowing scan line, screen flicker, horizontal
// sync distortion, RGB shift, bloom, burn-in, chroma/mono color
// conversion, bezel frame with ambient light and reflections.

// -- BEGIN CRT PARAMS --
// Values below correspond to the stock "ibm_dos" preset. crt.lua
// rewrites this block from a preset + overrides.
const AMBIENT_LIGHT: f32 = 0.0000;
const BLOOM: f32 = 0.3600;
const BRIGHTNESS: f32 = 0.5600;
const CHROMA_COLOR: f32 = 1.0000;
const FLICKERING: f32 = 0.1900;
const FONT_COLOR: vec3<f32> = vec3<f32>(0.9850, 0.9850, 0.9850);
const BACKGROUND_COLOR: vec3<f32> = vec3<f32>(0.0150, 0.0150, 0.0150);
const FRAME_COLOR: vec3<f32> = vec3<f32>(0.2634, 0.2634, 0.2634);
const FRAME_SHININESS: f32 = 0.2000;
const FRAME_SIZE: f32 = 0.0000;
const GLOWING_LINE: f32 = 0.0000;
const HORIZONTAL_SYNC: f32 = 0.0000;
const JITTER: f32 = 0.2000;
const RASTERIZATION: i32 = 0;
const RGB_SHIFT: f32 = 0.7500;
const SCREEN_CURVATURE: f32 = 0.0000;
const SCREEN_RADIUS: f32 = 0.0000;
const STATIC_NOISE: f32 = 0.0000;
const VIRTUAL_PIXEL_SIZE: f32 = 3.0000;
// -- END CRT PARAMS --

const PI: f32 = 3.141592654;

// ---------------------------------------------------------------
// Hash / procedural noise
// (replaces cool-retro-term's allNoise512.png noise texture)
// ---------------------------------------------------------------

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash42(p: vec2<f32>) -> vec4<f32> {
    var p4 = fract(vec4<f32>(p.xyxy) * vec4<f32>(0.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// Smooth value noise: 4 independent channels.
fn value_noise4(p: vec2<f32>) -> vec4<f32> {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash42(i), hash42(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash42(i + vec2<f32>(0.0, 1.0)), hash42(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y,
    );
}

// ---------------------------------------------------------------
// Helpers ported from cool-retro-term's shader library
// ---------------------------------------------------------------

fn rgb2grey(v: vec3<f32>) -> f32 {
    return dot(v, vec3<f32>(0.21, 0.72, 0.04));
}

// Screen curvature with bezel padding (terminal_dynamic/static.frag).
fn distort_coordinates(coords: vec2<f32>) -> vec2<f32> {
    let padded = coords * (vec2<f32>(1.0) + FRAME_SIZE * 2.0) - vec2<f32>(FRAME_SIZE);
    let cc = padded - vec2<f32>(0.5);
    let dist = dot(cc, cc) * SCREEN_CURVATURE;
    return padded + cc * (1.0 + dist) * dist;
}

// The travelling "glowing line" (terminal_dynamic.frag randomPass).
fn random_pass(coords: vec2<f32>, vres_y: f32, time: f32) -> f32 {
    return fract(smoothstep(-120.0, 0.0, coords.y - (vres_y + 120.0) * fract(time * 0.15)));
}

// Scanline / pixel / subpixel rasterization (terminal_dynamic.frag).
// RASTERIZATION: 0 = none, 1 = scanlines, 2 = pixels, 3 = subpixels.
fn apply_rasterization(
    screen_coords: vec2<f32>,
    texel: vec3<f32>,
    vres: vec2<f32>,
    intensity: f32,
) -> vec3<f32> {
    if (RASTERIZATION <= 0 || RASTERIZATION >= 4 || intensity <= 0.0) {
        return texel;
    }

    let INTENSITY = 0.30;
    let BRIGHTBOOST = 0.30;

    var result = texel;
    if (RASTERIZATION == 3) {
        let SUBPIXELS = 3.0;
        let offsets = vec3<f32>(PI) * vec3<f32>(0.5, 0.5 - 2.0 / 3.0, 0.5 - 4.0 / 3.0);
        let omega = vec2<f32>(PI) * 2.0 * vres;
        let angle = screen_coords * omega;
        let xfactors = (SUBPIXELS + sin(vec3<f32>(angle.x) + offsets)) / (SUBPIXELS + 1.0);
        result = texel * xfactors;
    }

    let pixel_high = ((1.0 + BRIGHTBOOST) - (0.2 * result)) * result;
    let pixel_low = ((1.0 - INTENSITY) + (0.1 * result)) * result;

    var coords = fract(screen_coords * vres) * 2.0 - vec2<f32>(1.0);
    var mask = 0.0;
    if (RASTERIZATION == 2) {
        coords = coords * coords;
        mask = 1.0 - coords.x - coords.y;
    } else {
        mask = 1.0 - abs(coords.y);
    }

    let raster_color = mix(pixel_low, pixel_high, mask);
    return mix(texel, raster_color, intensity);
}

// Convert the rendered terminal to the phosphor palette
// (terminal_dynamic.frag convertWithChroma).
// CHROMA_COLOR = 0 gives pure monochrome; 1 preserves source hues.
fn convert_with_chroma(in_color: vec3<f32>) -> vec3<f32> {
    let grey = rgb2grey(in_color);
    if (CHROMA_COLOR > 0.0) {
        let denom = max(grey, 0.0001);
        let foreground = mix(FONT_COLOR, in_color * FONT_COLOR / denom, CHROMA_COLOR);
        return mix(BACKGROUND_COLOR, foreground, grey);
    }
    return mix(BACKGROUND_COLOR, FONT_COLOR, grey);
}

// Signed distance to a rounded rectangle covering the screen, in pixels
// (terminal_frame.frag roundedRectSdfPixels).
fn rounded_rect_sdf_pixels(p: vec2<f32>, viewport: vec2<f32>, radius_px: f32) -> f32 {
    let center_px = 0.5 * viewport;
    let local_px = p * viewport - center_px;
    let half_size = viewport * 0.5 - vec2<f32>(radius_px);
    let d = abs(local_px) - half_size;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0) - radius_px;
}

// Bezel frame with shadow, ambient light and glass glare
// (port of terminal_frame.frag). Returns color in .rgb, overlay
// opacity in .a.
fn frame_overlay(static_coords: vec2<f32>, curved: vec2<f32>, viewport: vec2<f32>) -> vec4<f32> {
    let radius_px = SCREEN_RADIUS * 0.05 * min(viewport.x, viewport.y);
    let edge_soft_px = 1.0;
    let seam = max(radius_px, 0.5) / min(viewport.x, viewport.y);

    let e = min(
        smoothstep(-seam, seam, curved.x - curved.y),
        smoothstep(-seam, seam, curved.x - (1.0 - curved.y)),
    );
    let s = min(
        smoothstep(-seam, seam, curved.y - curved.x),
        smoothstep(-seam, seam, curved.x - (1.0 - curved.y)),
    );
    let w = min(
        smoothstep(-seam, seam, curved.y - curved.x),
        smoothstep(-seam, seam, (1.0 - curved.x) - curved.y),
    );
    let n = min(
        smoothstep(-seam, seam, curved.x - curved.y),
        smoothstep(-seam, seam, (1.0 - curved.x) - curved.y),
    );

    let dist_px = rounded_rect_sdf_pixels(curved, viewport, radius_px);
    var frame_shadow = e * 0.66 + w * 0.66 + n * 0.33 + s;
    frame_shadow *= smoothstep(0.0, edge_soft_px * 5.0, dist_px);

    let frame_alpha = 1.0 - FRAME_SHININESS * 0.4;
    let in_screen = smoothstep(0.0, edge_soft_px, -dist_px);
    let alpha = mix(frame_alpha, mix(0.0, 0.3, AMBIENT_LIGHT), in_screen);

    let vig = max(curved.x * (1.0 - curved.y) * curved.y * (1.0 - curved.x) * 25.0, 0.0);
    let glass = clamp(AMBIENT_LIGHT * sqrt(vig) * in_screen, 0.0, 1.0);

    var tint = FRAME_COLOR * frame_shadow;
    let noise = hash21(static_coords * viewport) - 0.5;
    tint = clamp(tint + vec3<f32>(noise * 0.04), vec3<f32>(0.0), vec3<f32>(1.0));
    let color = mix(tint, vec3<f32>(glass), in_screen);

    // The frame only exists when a bezel size is configured.
    return vec4<f32>(color, alpha * step(0.0001, FRAME_SIZE));
}

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------

@fragment
fn fs_postprocess(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let time = pp.time;
    let viewport = pp.resolution;
    let vres = viewport / VIRTUAL_PIXEL_SIZE;

    // Per-frame randoms driving flicker and horizontal sync
    // (terminal_dynamic.vert sampled the noise texture once per frame).
    let frame_noise = value_noise4(vec2<f32>(time * 124.0, time * 3.7));
    let brightness_flicker = 1.0 + (frame_noise.g - 0.5) * FLICKERING;
    let hsync_strength = mix(0.05, 0.35, HORIZONTAL_SYNC);
    let hsync_rand = hsync_strength - frame_noise.r;
    let distortion_scale =
        step(0.0, hsync_rand) * hsync_rand * hsync_strength * step(0.0001, HORIZONTAL_SYNC);
    let distortion_freq = mix(4.0, 40.0, frame_noise.g);

    // Screen curvature; masks for the visible screen / reflection areas
    // (terminal_static.frag).
    let curved = distort_coordinates(uv);
    let inside = step(vec2<f32>(0.0), curved) - step(vec2<f32>(1.0), curved);
    let shown = max(inside.x, inside.y);
    let is_screen = min(inside.x, inside.y);
    let is_reflection = shown - is_screen;
    // Mirror coordinates outside the screen so the bezel shows a
    // faint reflection of the picture.
    let mirror = -1.0 + 2.0 * step(vec2<f32>(0.0), curved) - 2.0 * step(vec2<f32>(1.0), curved);
    var txt_coords = curved * mirror;

    // Horizontal sync: sinusoidal horizontal displacement whose
    // amplitude spikes at random moments.
    let dst = sin((txt_coords.y + time) * distortion_freq);
    txt_coords.x += dst * distortion_scale;

    // Per-pixel animated noise; .a drives static noise, .ba drives jitter.
    let noise_texel = hash42(
        floor(uv * viewport / 1.5) + floor(vec2<f32>(time * 19.7, time * 4.9)) * 17.0,
    );
    let jitter_displacement = vec2<f32>(0.007, 0.002) * JITTER;
    txt_coords += (noise_texel.ba - vec2<f32>(0.5)) * jitter_displacement;

    // Additive intensity: static noise (stronger at the middle of the
    // screen) plus the travelling glowing line.
    let dist_center = length(vec2<f32>(0.5) - uv);
    var add_color = 0.0001;
    add_color += noise_texel.a * STATIC_NOISE * (1.0 - dist_center * 1.3);
    add_color += random_pass(txt_coords * vres, vres.y, time) * GLOWING_LINE * 0.2;

    // Sample the terminal with RGB shift (terminal_static.frag):
    // imperfect convergence of the three electron guns.
    let shift = vec2<f32>(RGB_SHIFT * (4.0 / viewport.x), 0.0);
    let center_s = textureSample(screen_texture, screen_sampler, txt_coords);
    let right_s = textureSample(screen_texture, screen_sampler, txt_coords + shift);
    let left_s = textureSample(screen_texture, screen_sampler, txt_coords - shift);
    var txt_color = vec3<f32>(
        left_s.r * 0.10 + right_s.r * 0.30 + center_s.r * 0.60,
        left_s.g * 0.20 + right_s.g * 0.20 + center_s.g * 0.60,
        left_s.b * 0.30 + right_s.b * 0.10 + center_s.b * 0.60,
    );

    // Burn-in: phosphor persistence from the accumulation texture
    // maintained by wezterm (enable with custom_shader_burn_in > 0;
    // samples a black dummy texture, i.e. no-op, when disabled).
    let burn = textureSample(burnin_texture, screen_sampler, txt_coords);
    let blur_decay = clamp(pp.time_delta * pp.burn_in_time, 0.0, 1.0);
    let burn_color = 0.65 * (burn.rgb - vec3<f32>(blur_decay)) * (1.0 - burn.a);
    txt_color = max(txt_color, burn_color);

    // Bloom: blurred copy of the screen provided by wezterm (enable
    // with custom_shader_bloom = true; black dummy when disabled).
    let bloom_s = textureSample(bloom_texture, screen_sampler, txt_coords);
    txt_color += clamp(bloom_s.rgb * (BLOOM * 2.5), vec3<f32>(0.0), vec3<f32>(0.5));

    txt_color += vec3<f32>(add_color);

    // Rasterization: scanlines / pixel grid / subpixel stripes.
    // Progressively disabled when virtual pixels approach physical size.
    let raster_intensity = smoothstep(2.0, 4.0, VIRTUAL_PIXEL_SIZE);
    txt_color = apply_rasterization(curved, txt_color, vres, raster_intensity);

    // Map to the phosphor palette.
    var final_color = convert_with_chroma(txt_color);

    // Flicker and overall brightness.
    final_color *= brightness_flicker;
    final_color *= mix(0.5, 1.5, BRIGHTNESS);

    // Screen edge: black beyond the visible tube; bezel reflections
    // of the blurred image where the frame catches the light.
    let reflection_color =
        mix(bloom_s.rgb * bloom_s.a * 2.0, final_color, FRAME_SHININESS * 0.5);
    final_color = mix(final_color * is_screen, reflection_color, is_reflection);

    // Subtle dithering to avoid banding (terminal_static.frag).
    let dither = hash21(uv * viewport) - 0.5;
    final_color = clamp(final_color + vec3<f32>(dither * 0.025), vec3<f32>(0.0), vec3<f32>(1.0));

    // Bezel frame overlay.
    let frame = frame_overlay(uv, curved, viewport);
    final_color = mix(final_color, frame.rgb, frame.a);

    return vec4<f32>(final_color, 1.0);
}
