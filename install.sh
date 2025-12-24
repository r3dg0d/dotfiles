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
for dir in hypr noctalia fastfetch gtk-3.0 gtk-4.0; do
    if [ -d "$DOTFILES_DIR/.config/$dir" ]; then
        echo "  Installing $dir..."
        mkdir -p "$CONFIG_DIR"
        cp -r "$DOTFILES_DIR/.config/$dir" "$CONFIG_DIR/"
    fi
done

# Install nsxiv-smart wrapper script
echo ""
echo "🖼️ Installing nsxiv-smart image viewer wrapper..."
if [ -f "$DOTFILES_DIR/.local/bin/nsxiv-smart" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "$DOTFILES_DIR/.local/bin/nsxiv-smart" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/nsxiv-smart"
    echo "  ✓ Installed nsxiv-smart to ~/.local/bin/"
else
    echo "  ⚠️ nsxiv-smart not found in dotfiles"
fi

# Create nsxiv-smart.desktop entry
echo "  Creating desktop entry..."
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/nsxiv-smart.desktop" << 'EOF'
[Desktop Entry]
Name=nsxiv (Smart Size)
GenericName=Image Viewer
Comment=Neo Simple X Image Viewer with auto-sizing
Exec=$HOME/.local/bin/nsxiv-smart %F
Icon=nsxiv
Terminal=false
Type=Application
Categories=Graphics;Viewer;
MimeType=image/bmp;image/gif;image/jpeg;image/jpg;image/png;image/tiff;image/webp;
EOF
# Fix the $HOME in the desktop file
sed -i "s|\$HOME|$HOME|g" "$HOME/.local/share/applications/nsxiv-smart.desktop"
echo "  ✓ Created nsxiv-smart.desktop"

# Make scripts executable
echo ""
echo "🔧 Making scripts executable..."
find "$CONFIG_DIR/hypr" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

# Install packages
echo ""
echo "📦 Installing required packages..."
if command -v pacman >/dev/null; then
    # Check if packages are installed, if not install them
    PKGS="hyprland fastfetch nsxiv imagemagick jq"
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

    # AUR packages (noctalia-shell, hyprbars)
    if command -v yay >/dev/null; then
        echo "  Checking AUR packages..."
        yay -S --needed --noconfirm noctalia-shell hyprland-plugin-hyprbars || echo "  ⚠️ Failed to install AUR packages."
    elif command -v paru >/dev/null; then
        paru -S --needed --noconfirm noctalia-shell hyprland-plugin-hyprbars || echo "  ⚠️ Failed to install AUR packages."
    else
        echo "  ⚠️ AUR helper (yay/paru) not found. Skipping AUR packages."
        echo "     Please install: noctalia-shell hyprland-plugin-hyprbars"
    fi
else
    echo "  ⚠️ Not an Arch system (pacman not found). Skipping package installation."
fi

# Set default applications
echo ""
echo "🎨 Setting default applications..."
if command -v xdg-mime >/dev/null; then
    # Images -> nsxiv-smart (custom wrapper)
    echo "  Setting nsxiv (smart) as default image viewer..."
    # Ensure wrapper exists (copy from dotfiles if needed, or create)
    # We assume the wrapper script is deployed via dotfiles or created manually
    xdg-mime default nsxiv-smart.desktop image/jpeg image/png image/gif image/webp image/bmp image/tiff
    
    # File Manager -> dolphin (if installed)
    if pacman -Qi dolphin >/dev/null 2>&1; then
        echo "  Setting Dolphin as default file manager..."
        xdg-mime default org.kde.dolphin.desktop inode/directory
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
echo "  2. Install ProggyTiny font (optional, for pixelated title bars):"
echo "     # Download ProggyTiny.woff2 and place in ~/.local/share/fonts/"
echo "     # Then run: fc-cache -fv"
echo "  3. Reload Hyprland: hyprctl reload"
echo ""
echo "💾 Your old configs are backed up to: $BACKUP_DIR"
echo ""

