# Wez's Terminal — CRT edition

> **This is [wezterm](https://github.com/wezterm/wezterm) with
> [cool-retro-term](https://github.com/Swordfish90/cool-retro-term)'s
> CRT visual effects**: screen curvature, scanlines, phosphor glow
> (bloom), burn-in trails, static noise, jitter, glowing scan line,
> flicker, horizontal sync distortion, RGB shift, and a bezel frame —
> implemented as WebGPU post-processing shaders with Lua-configurable
> presets for every cool-retro-term profile.
>
> **Setup and presets:** see [`assets/shaders/README.md`](assets/shaders/README.md).
> **Build packages:** run a `*_continuous` workflow from the Actions tab
> (e.g. `macos_continuous`, `ubuntu24.04_continuous`,
> `windows_continuous`) via **Run workflow**; installers are attached as
> run artifacts.

<img height="128" alt="WezTerm Icon" src="https://raw.githubusercontent.com/wezterm/wezterm/main/assets/icon/wezterm-icon.svg" align="left"> *A GPU-accelerated cross-platform terminal emulator and multiplexer written by <a href="https://github.com/wez">@wez</a> and implemented in <a href="https://www.rust-lang.org/">Rust</a>*

User facing docs and guide at: https://wezterm.org/

![Screenshot](docs/screenshots/two.png)

*Screenshot of wezterm on macOS, running vim*

## Installation

https://wezterm.org/installation

## Upstream

This repo tracks [wezterm/wezterm](https://github.com/wezterm/wezterm)
by Wez Furlong. For issues with wezterm itself (rather than the CRT
effects), see the upstream [issue
tracker](https://github.com/wezterm/wezterm/issues) and
[documentation](https://wezterm.org/).
