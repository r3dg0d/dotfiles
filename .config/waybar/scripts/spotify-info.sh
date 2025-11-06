#!/usr/bin/env bash

# Script to get Spotify track info (title, artist) for waybar custom module

PLAYER="spotify"

# Function to escape JSON strings properly
json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes, then control characters
    str=$(printf '%s' "$str" | sed 's/\\/\\\\/g')
    str=$(printf '%s' "$str" | sed 's/"/\\"/g')
    str=$(printf '%s' "$str" | sed 's/\n/\\n/g')
    str=$(printf '%s' "$str" | sed 's/\r/\\r/g')
    str=$(printf '%s' "$str" | sed 's/\t/\\t/g')
    printf '%s' "$str"
}

# Check if Spotify process is running (more reliable than playerctl after restart)
# This helps detect Spotify even if playerctl hasn't registered it yet
SPOTIFY_RUNNING=false
if pgrep -x "spotify" > /dev/null 2>&1 || pgrep -f "spotify" > /dev/null 2>&1; then
    SPOTIFY_RUNNING=true
fi

# Check if playerctl sees Spotify
PLAYERCTL_SEES_SPOTIFY=false
if playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    PLAYERCTL_SEES_SPOTIFY=true
fi

# If neither Spotify nor playerctl sees it, exit early
if [ "$SPOTIFY_RUNNING" = false ] && [ "$PLAYERCTL_SEES_SPOTIFY" = false ]; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Get metadata first - this is more reliable than status check
# After restart, metadata might not be available immediately, so retry more aggressively
ARTIST_RAW=""
TITLE_RAW=""
ALBUM_RAW=""

# Try to get metadata - retry up to 5 times with increasing delays (handles restart scenarios)
# Try both short and full metadata field names for better compatibility
for i in {1..5}; do
    # Try short form first (artist, title, album)
    ARTIST_RAW=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null || echo "")
    TITLE_RAW=$(playerctl -p "$PLAYER" metadata title 2>/dev/null || echo "")
    ALBUM_RAW=$(playerctl -p "$PLAYER" metadata album 2>/dev/null || echo "")
    
    # If short form didn't work, try full xesam keys
    if [ -z "$ARTIST_RAW" ]; then
        ARTIST_RAW=$(playerctl -p "$PLAYER" metadata xesam:artist 2>/dev/null || echo "")
    fi
    if [ -z "$TITLE_RAW" ]; then
        TITLE_RAW=$(playerctl -p "$PLAYER" metadata xesam:title 2>/dev/null || echo "")
    fi
    if [ -z "$ALBUM_RAW" ]; then
        ALBUM_RAW=$(playerctl -p "$PLAYER" metadata xesam:album 2>/dev/null || echo "")
    fi
    
    # If we got metadata, break early
    if [ -n "$ARTIST_RAW" ] || [ -n "$TITLE_RAW" ]; then
        break
    fi
    
    # Progressive delay: 0.1s, 0.2s, 0.3s, 0.4s (last attempt has no delay)
    if [ $i -lt 5 ]; then
        case $i in
            1) sleep 0.1 ;;
            2) sleep 0.2 ;;
            3) sleep 0.3 ;;
            4) sleep 0.4 ;;
        esac
    fi
done

# Get status - but don't exit early based on it if we have metadata
STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null || echo "Unknown")
LOOP_STATUS=$(playerctl -p "$PLAYER" loop 2>/dev/null || echo "None")

# Check if we have valid metadata - if we do, show it regardless of status
# This handles the case where Spotify is detected but not actively playing
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ]; then
    # No metadata available yet
    # If Spotify process is running but playerctl hasn't detected it yet (common after restart),
    # return empty to let waybar keep polling - metadata will appear once playerctl catches up
    if [ "$SPOTIFY_RUNNING" = true ] && [ "$PLAYERCTL_SEES_SPOTIFY" = false ]; then
        echo '{"text":"","tooltip":""}'
        exit 0
    fi
    
    # If playerctl sees Spotify but status is invalid, exit
    if [ "$STATUS" != "Playing" ] && [ "$STATUS" != "Paused" ] && [ "$STATUS" != "Stopped" ] && [ "$STATUS" != "Unknown" ]; then
        echo '{"text":"","tooltip":""}'
        exit 0
    fi
    
    # If status is valid but we still don't have metadata, return empty
    # This will allow waybar to keep polling and eventually get metadata when it's available
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Escape for JSON
ARTIST=$(json_escape "$ARTIST_RAW")
TITLE=$(json_escape "$TITLE_RAW")
ALBUM=$(json_escape "$ALBUM_RAW")

# Set icon based on status
if [ "$STATUS" = "Playing" ]; then
    ICON="󰏤"  # Pause icon
else
    ICON="󰐊"  # Play icon
fi

# Create display text (truncate if too long)
# Loop icon is now shown as a separate button, not in the text
if [ -n "$ARTIST" ] && [ -n "$TITLE" ]; then
    TEXT="${ARTIST} - ${TITLE}"
elif [ -n "$TITLE" ]; then
    TEXT="${TITLE}"
elif [ -n "$ARTIST" ]; then
    TEXT="${ARTIST}"
else
    TEXT=""
fi

# Truncate if too long
TEXT_DISPLAY="$TEXT"
if [ ${#TEXT_DISPLAY} -gt 40 ]; then
    TEXT_DISPLAY="${TEXT_DISPLAY:0:37}..."
fi

# Build tooltip
TOOLTIP="${ARTIST} - ${TITLE}\\nAlbum: ${ALBUM}\\nStatus: ${STATUS}\\nLoop: ${LOOP_STATUS}\\n\\nClick: Play/Pause\\nRight-click: Next\\nMiddle-click: Previous\\nScroll: Skip\\nBackward-click: Toggle Loop"

# Create JSON output for waybar
if [ -n "$TEXT_DISPLAY" ]; then
    echo "{\"text\":\"${ICON} ${TEXT_DISPLAY}\",\"tooltip\":\"${TOOLTIP}\",\"class\":\"custom-spotify-info\"}"
else
    echo "{\"text\":\"\",\"tooltip\":\"\"}"
fi

