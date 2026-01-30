# Font Troubleshooting for hyprbars

## Current Configuration
- Font: `ProggyTinyTT`
- Font is installed and recognized by fontconfig and Pango
- Config is set correctly

## If Font Still Doesn't Appear

### 1. Close and Reopen Windows
Existing windows may have cached the old font. Close all windows and open new ones.

### 2. Restart Hyprland Completely
A full restart (not just reload) may be needed:
- Log out and log back in
- Or: `killall Hyprland` (then restart your display manager)

### 3. Verify Font is Available
```bash
fc-list | grep -i proggy
fc-match "ProggyTinyTT"
```

### 4. Try Alternative Font Names
If ProggyTinyTT doesn't work, try:
- `ProggyTinyTT Regular`
- `ProggyTiny`
- Or install Terminus: `sudo pacman -S terminus-font` and use `Terminus`

### 5. Check hyprbars Config
```bash
hyprctl getoption plugin:hyprbars:bar_text_font
```

### 6. Check for Errors
```bash
journalctl -u Hyprland --since "5 minutes ago" | grep -i font
```

## Alternative: Install Terminus Font
If ProggyTinyTT continues to have issues, Terminus is a reliable bitmap font:
```bash
sudo pacman -S terminus-font
```
Then change config to: `bar_text_font = Terminus`

