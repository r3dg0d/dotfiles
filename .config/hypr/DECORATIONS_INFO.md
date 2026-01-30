# Window Decorations Setup

## What I've Configured

I've updated your Hyprland configuration with improved window decorations:

1. **Better border colors**: More subtle, clean borders
2. **Improved shadows**: Softer, more visible shadows
3. **Window rules**: 
   - Floating windows have no borders (cleaner look)
   - Specific rounding for image viewers and terminals
   - Fullscreen windows have no decorations

## Important Note About Title Bars

**Hyprland does not natively support title bars with maximize/exit buttons** like traditional X11 window managers (dwm, bspwm, i3, etc.). Hyprland uses border-based decorations instead.

The screenshot you showed might be from:
- A different window manager (dwm, bspwm, openbox, etc.)
- XWayland applications that draw their own decorations
- A decoration plugin (though none are widely available for Hyprland)

### Options for Title Bars:

1. **Use XWayland apps**: Some X11 applications draw their own title bars
2. **Switch to a different WM**: If you need title bars with buttons, consider:
   - dwm (with patches for custom decorations)
   - bspwm (with external decoration scripts)
   - openbox (traditional title bars)
3. **Accept border decorations**: Hyprland's border-based system is modern and efficient

## nsxiv vs imv

**nsxiv** (Neo Simple X Image Viewer):
- ✅ Fork of sxiv, actively maintained
- ✅ Very lightweight (~98KB installed)
- ✅ Simple, keyboard-driven interface
- ✅ Great for quick image viewing
- ✅ Minimal dependencies
- ✅ Works well in tiling window managers

**imv**:
- ✅ Also lightweight and minimal
- ✅ More scriptable
- ✅ Better Wayland support (native Wayland app)
- ✅ More features (overlay text, etc.)

**Recommendation**: Since you're using Hyprland (Wayland), **imv** might be slightly better due to native Wayland support. However, **nsxiv** works fine via XWayland and is more traditional/lightweight. Both are excellent choices - try both and see which you prefer!

## Current Configuration

Your decorations are now configured with:
- Subtle borders (gray gradient)
- Rounded corners (8px)
- Soft shadows
- Blur effects
- Clean floating window appearance

To apply changes, reload Hyprland: `hyprctl reload` or restart Hyprland.

