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
for dir in hypr waybar ghostty fastfetch eww; do
    if [ -d "$CONFIG_DIR/$dir" ]; then
        echo "  Backing up $dir..."
        cp -r "$CONFIG_DIR/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done

echo ""
echo "📋 Installing dotfiles..."

# Copy configs
for dir in hypr waybar ghostty fastfetch eww; do
    if [ -d "$DOTFILES_DIR/.config/$dir" ]; then
        echo "  Installing $dir..."
        mkdir -p "$CONFIG_DIR"
        cp -r "$DOTFILES_DIR/.config/$dir" "$CONFIG_DIR/"
    fi
done

# Make scripts executable
echo ""
echo "🔧 Making scripts executable..."
find "$CONFIG_DIR/waybar/scripts" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
find "$CONFIG_DIR/hypr" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Update monitor configuration in ~/.config/hypr/monitors.conf"
echo "  2. Install required packages:"
echo "     sudo pacman -S hyprland waybar ghostty fastfetch playerctl cava jq"
echo "  3. Reload Hyprland: hyprctl reload"
echo ""
echo "💾 Your old configs are backed up to: $BACKUP_DIR"
echo ""

