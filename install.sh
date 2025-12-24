#!/bin/bash
# Dotfiles installation script

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

echo "🚀 Installing dotfiles..."
echo ""

# Create backup directory
echo "📦 Creating backup of existing configs..."
mkdir -p "$BACKUP_DIR"

# Backup existing configs if they exist
for dir in hypr noctalia fastfetch; do
    if [ -d "$CONFIG_DIR/$dir" ]; then
        echo "  Backing up $dir..."
        cp -r "$CONFIG_DIR/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done

echo ""
echo "📋 Installing dotfiles..."

# Copy configs
for dir in hypr noctalia fastfetch; do
    if [ -d "$DOTFILES_DIR/.config/$dir" ]; then
        echo "  Installing $dir..."
        mkdir -p "$CONFIG_DIR"
        cp -r "$DOTFILES_DIR/.config/$dir" "$CONFIG_DIR/"
    fi
done

# Make scripts executable
echo ""
echo "🔧 Making scripts executable..."
find "$CONFIG_DIR/hypr" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Update monitor configuration in ~/.config/hypr/hyprland.conf"
echo "  2. Install required packages:"
echo "     sudo pacman -S hyprland noctalia-shell fastfetch nsxiv"
echo "     # Install AUR packages:"
echo "     yay -S noctalia-shell hyprland-plugin-hyprbars"
echo "  3. Set default image viewer:"
echo "     xdg-mime default nsxiv.desktop image/jpeg image/png image/gif"
echo "  3. Install ProggyTiny font (optional, for pixelated title bars):"
echo "     # Download ProggyTiny.woff2 and place in ~/.local/share/fonts/"
echo "     # Then run: fc-cache -fv"
echo "  4. Reload Hyprland: hyprctl reload"
echo ""
echo "💾 Your old configs are backed up to: $BACKUP_DIR"
echo ""

