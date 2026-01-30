# Custom Window Decorations in Hyprland - The Reality

## Important Limitation

**Hyprland does NOT support title bars with maximize/exit buttons** like traditional X11 window managers (dwm, bspwm, openbox, i3, etc.). 

The screenshot you showed is likely from:
- A different window manager (dwm, bspwm, openbox, etc.)
- XWayland applications that draw their own decorations
- A compositor that's not Hyprland

## What Hyprland DOES Support

Hyprland uses **border-based decorations** instead of title bars:

1. **Window Borders**: Colored borders around windows (what you currently have)
2. **Rounded Corners**: Configurable rounding
3. **Shadows**: Drop shadows around windows
4. **Blur**: Background blur effects
5. **Window Rules**: Per-application customization

## Best Alternatives for Your Needs

### Option 1: Enhanced Borders (Current Setup)
Your current configuration already has:
- Custom border colors
- Rounded corners
- Shadows
- Blur effects

You can improve this further by adjusting the `decoration` and `general` sections in your config.

### Option 2: Waybar for Window Titles
Install Waybar to display window titles in a status bar:

```bash
sudo pacman -S waybar
```

Then configure it to show window titles (I can help set this up).

### Option 3: Switch Window Managers
If you **really need** title bars with maximize/exit buttons, consider:

- **dwm** (Dynamic Window Manager) - Highly customizable, can have title bars
- **bspwm** - Tiling WM with external decoration support
- **openbox** - Traditional floating WM with full title bars
- **i3** - Popular tiling WM (border-based like Hyprland)

## What I Can Do For You

1. ✅ **Improve your current borders** - Make them look better
2. ✅ **Set up Waybar** - Show window titles in a bar
3. ✅ **Configure window rules** - Customize per-application appearance
4. ❌ **Cannot add title bars with buttons** - Not supported by Hyprland

## Recommendation

Since you're already using Hyprland and it's working well, I'd suggest:
1. Keep using Hyprland's border-based decorations
2. Install Waybar to show window titles
3. Use keyboard shortcuts for window management (Super+Q to close, etc.)

If you absolutely need title bars with buttons, switching to dwm or bspwm would be the way to go.

