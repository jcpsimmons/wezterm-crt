---
tags:
  - appearance
  - tuning
---
# `custom_shader_fps = 60`

*Unreleased fork feature*

Caps the rate at which repaints are scheduled while animated
[custom_shaders](custom_shaders.md) are active.

Lower values reduce GPU usage at the cost of choppier shader animation.
Set it to `0` to disable continuous repaints entirely, which is
appropriate for purely static shaders (for example a plain vignette).

```lua
config.custom_shader_fps = 30
```
