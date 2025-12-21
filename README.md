# My Dotfiles

A collection of my dotfiles for a riced Linux desktop environment using Hyprland, Noctalia Shell, and Fastfetch.

## What's Included

- **Hyprland** - Window manager configuration
- **Noctalia Shell** - Modern shell/bar replacement with panels, widgets, and desktop integration
- **Fastfetch** - System information display with custom OS installation date and age modules

## Installation

### Prerequisites

- Arch Linux
- Hyprland window manager
- Noctalia Shell (from AUR)
- Fastfetch
- Required fonts: Nerd Fonts (for icons)

### Quick Install

1. Clone this repository:
```bash
git clone https://github.com/r3dg0d/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

2. Run the install script:
```bash
chmod +x install.sh
./install.sh
```

3. Install Noctalia Shell (if not already installed):
```bash
yay -S noctalia-shell
# or
paru -S noctalia-shell
```

4. Reload Hyprland:
```bash
hyprctl reload
```

### Manual Installation

If you prefer to install manually:

1. Backup your existing dotfiles:
```bash
mkdir -p ~/.config-backup
cp -r ~/.config/hypr ~/.config-backup/ 2>/dev/null
cp -r ~/.config/noctalia ~/.config-backup/ 2>/dev/null
cp -r ~/.config/fastfetch ~/.config-backup/ 2>/dev/null
```

2. Copy the dotfiles:
```bash
cp -r .config/hypr ~/.config/
cp -r .config/noctalia ~/.config/
cp -r .config/fastfetch ~/.config/
```

3. Install dependencies:
```bash
# Required packages
sudo pacman -S hyprland fastfetch
yay -S noctalia-shell  # or paru -S noctalia-shell
```

4. Reload Hyprland:
```bash
hyprctl reload
```

## Configuration Details

### Hyprland

- **Monitors**: Configured for dual monitor setup
- **Keybindings**: Custom keybindings for applications and window management
- **Input**: Keyboard and mouse configuration
- **Appearance**: Window rules and visual settings

**Important**: Update monitor configuration in `hyprland.conf` to match your monitor setup!

### Noctalia Shell

- **Panels**: Customizable panels with transparency and animations
- **Widgets**: System monitoring, workspace management, media controls
- **Desktop Widgets**: Multi-monitor support with positioning and scaling
- **Plugin System**: Support for git forges and custom plugins
- **Settings**: Comprehensive configuration UI

Noctalia Shell replaces traditional status bars (like Waybar) with a more modern, integrated approach. Configuration is done through the Noctalia settings panel or by editing the config files directly.

### Fastfetch

- **Custom Modules**: 
  - OS Installation Date (from pacman.log)
  - OS Age (calculated from installation date)
- **Hyprland Preset**: Uses the Hyprland preset with custom modifications
- **Display**: Shows system information with consistent styling

The Fastfetch config includes custom command modules that calculate the actual OS installation date from `/var/log/pacman.log` and display the age of the installation.

## Customization

### Monitor Configuration

Edit `~/.config/hypr/hyprland.conf` to match your setup. Look for monitor configuration lines like:

```bash
monitor=DP-1,1920x1080@143.85,0x0,1
monitor=HDMI-A-1,3440x1440@179.99,1920x0,1
```

### Noctalia Shell Configuration

Noctalia Shell can be configured through:
1. **Settings Panel**: Access via the Noctalia settings application
2. **Config Files**: Edit files in `~/.config/noctalia/` directly
3. **Plugins**: Install and configure plugins through the settings panel

### Keybindings

Main keybindings are in `~/.config/hypr/hyprland.conf`. Edit to customize.

## Troubleshooting

### Noctalia Shell not appearing
- Ensure Noctalia Shell is installed: `yay -S noctalia-shell`
- Check if it's running: `ps aux | grep noctalia`
- Restart Hyprland: `hyprctl reload`

### Monitor configuration issues
- Check your monitor names: `hyprctl monitors`
- Update `hyprland.conf` with correct names and resolutions

### Fastfetch not showing correct installation date
- Ensure `/var/log/pacman.log` exists and is readable
- The installation date is calculated from the first entry in pacman.log

## Migration Notes

This setup uses:
- **Arch Linux** (standard installation)
- **Noctalia Shell** (modern shell replacement)

The configuration has been updated to use Noctalia Shell instead of traditional status bars.

## License

This configuration is free to use and modify. Feel free to fork and adapt it to your needs!

## Credits

- Inspired by various ricing communities
- Noctalia Shell: [noctalia-dev/noctalia-shell](https://github.com/noctalia-dev/noctalia-shell)
- Fastfetch: [fastfetch-cli/fastfetch](https://github.com/fastfetch-cli/fastfetch)

## Contributing

Feel free to open issues or submit pull requests if you have improvements!

---

**Note**: Remember to update monitor configurations, keyboard layouts, and any personal paths/commands before using this setup.
