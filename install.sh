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
for dir in hypr DankMaterialShell fastfetch ghostty gtk-3.0 gtk-4.0 quickshell; do
    if [ -d "$CONFIG_DIR/$dir" ]; then
        echo "  Backing up $dir..."
        cp -r "$CONFIG_DIR/$dir" "$BACKUP_DIR/" 2>/dev/null || true
    fi
done

echo ""
echo "📋 Installing dotfiles..."

# Copy configs
for dir in hypr DankMaterialShell fastfetch ghostty gtk-3.0 gtk-4.0 quickshell; do
    if [ -d "$DOTFILES_DIR/.config/$dir" ]; then
        echo "  Installing $dir..."
        mkdir -p "$CONFIG_DIR"
        cp -r "$DOTFILES_DIR/.config/$dir" "$CONFIG_DIR/"
    fi
done

# Sync special files
if [ -f "$DOTFILES_DIR/.bashrc" ]; then
    echo "  Installing .bashrc..."
    cp "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
fi

# Make scripts executable
echo ""
echo "🔧 Making scripts executable..."
find "$CONFIG_DIR/hypr" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

# Install packages
echo ""
echo "📦 Installing required packages..."
if command -v pacman >/dev/null; then
    # Check if packages are installed, if not install them
    PKGS="hyprland fastfetch ghostty imagemagick jq playerctl wl-clipboard"
    MISSING_PKGS=""
    for pkg in $PKGS; do
        if ! pacman -Qi $pkg >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done
    
    if [ -n "$MISSING_PKGS" ]; then
        echo "  Installing missing packages: $MISSING_PKGS"
        sudo pacman -S --noconfirm $MISSING_PKGS || echo "  ⚠️ Failed to install packages. Please install manually."
    else
        echo "  ✓ Base packages already installed"
    fi

    # DMS and related AUR packages
    if command -v yay >/dev/null; then
        echo "  Checking AUR packages..."
        yay -S --needed --noconfirm quickshell matugen || echo "  ⚠️ Failed to install AUR packages."
    elif command -v paru >/dev/null; then
        paru -S --needed --noconfirm quickshell matugen || echo "  ⚠️ Failed to install AUR packages."
    else
        echo "  ⚠️ AUR helper (yay/paru) not found. Skipping AUR packages."
        echo "     Please install: quickshell matugen"
    fi
else
    echo "  ⚠️ Not an Arch system (pacman not found). Skipping package installation."
fi

# Set default applications
echo ""
echo "🎨 Setting default applications..."
if command -v xdg-mime >/dev/null; then
    # File Manager -> thunar (preferred by USER in metadata)
    if pacman -Qi thunar >/dev/null 2>&1; then
        echo "  Setting Thunar as default file manager..."
        xdg-mime default thunar.desktop inode/directory
    fi
    
    echo "  ✓ Defaults set"
else
    echo "  ⚠️ xdg-mime not found. Skipping default applications."
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Update monitor configuration in ~/.config/hypr/hyprland.conf"
echo "  2. Ensure Dank Material Shell (DMS) is properly set up"
echo "  3. Reload Hyprland: hyprctl reload"
echo ""
echo "💾 Your old configs are backed up to: $BACKUP_DIR"
echo ""
