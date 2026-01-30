#!/bin/bash
# Wallpaper setup script for hyprpaper

WALLPAPER_DIR="$HOME/.config/hypr/wallpapers"
CONFIG_FILE="$HOME/.config/hypr/hyprpaper.conf"
DEFAULT_WALLPAPER="$HOME/.config/hypr/wallpaper.jpg"

# Create wallpaper directory if it doesn't exist
mkdir -p "$WALLPAPER_DIR"

# If a wallpaper is provided as argument, use it
if [ -n "$1" ]; then
    WALLPAPER="$1"
    # If it's a relative path, make it absolute
    if [[ ! "$WALLPAPER" =~ ^/ ]]; then
        WALLPAPER="$(realpath "$WALLPAPER")"
    fi
else
    # Try to find an existing wallpaper
    if [ -f "$DEFAULT_WALLPAPER" ]; then
        WALLPAPER="$DEFAULT_WALLPAPER"
    elif [ -n "$(ls -A "$WALLPAPER_DIR"/*.{jpg,png,jpeg} 2>/dev/null | head -1)" ]; then
        WALLPAPER="$(ls -t "$WALLPAPER_DIR"/*.{jpg,png,jpeg} 2>/dev/null | head -1)"
    else
        echo "No wallpaper found. Please provide a wallpaper path:"
        echo "  $0 /path/to/wallpaper.jpg"
        echo ""
        echo "Or place wallpapers in: $WALLPAPER_DIR"
        exit 1
    fi
fi

# Copy wallpaper to default location if it's not already there
if [ "$WALLPAPER" != "$DEFAULT_WALLPAPER" ]; then
    cp "$WALLPAPER" "$DEFAULT_WALLPAPER"
    echo "Copied wallpaper to $DEFAULT_WALLPAPER"
fi

# Update hyprpaper config
cat > "$CONFIG_FILE" << EOC
preload = $DEFAULT_WALLPAPER
wallpaper = ,$DEFAULT_WALLPAPER
splash = false
EOC

echo "Wallpaper set to: $DEFAULT_WALLPAPER"
echo "Config updated: $CONFIG_FILE"

# Reload hyprpaper if it's running
if pgrep -x hyprpaper > /dev/null; then
    killall hyprpaper
    hyprpaper &
    disown
    echo "Hyprpaper reloaded"
else
    echo "Start hyprpaper with: hyprpaper &"
fi
