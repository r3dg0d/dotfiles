# Ghostty Shaders

Custom GLSL shaders for Ghostty terminal.

## Currently Active
- **galaxy.glsl** - Animated galaxy background (currently active)

## Available Shaders

To switch shaders, edit `~/.config/ghostty/config` and change the `custom-shader` path:

```bash
custom-shader = ~/.config/ghostty/shaders/galaxy.glsl
```

### Shaders Available:
- `galaxy.glsl` - Animated galaxy background (currently active)
- `matrix-hallway.glsl` - Matrix-style hallway effect
- `inside-the-matrix.glsl` - Matrix rain effect
- `starfield.glsl` - Starfield animation
- `bloom.glsl` - Bloom/glow effect
- `crt.glsl` - CRT monitor effect

## More Shaders

Clone the full repository for more options:
```bash
git clone --depth 1 https://github.com/0xhckr/ghostty-shaders.git
```

Then copy any `.glsl` file to `~/.config/ghostty/shaders/` and update your config.

## Reload Config

After changing shaders, reload Ghostty config:
- **macOS**: `Command + Shift + ,`
- **Linux/Other**: `Control + Shift + ,`

Or restart Ghostty.

