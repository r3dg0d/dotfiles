#!/usr/bin/env bash

# Script to get Spotify track info using Spotify Web API (via mufetch credentials)
# This is more reliable than playerctl after system restarts

PLAYER="spotify"
CONFIG_FILE="$HOME/.config/mufetch/config.yaml"

# Function to escape JSON strings properly
json_escape() {
    local str="$1"
    str=$(printf '%s' "$str" | sed 's/\\/\\\\/g')
    str=$(printf '%s' "$str" | sed 's/"/\\"/g')
    str=$(printf '%s' "$str" | sed 's/\n/\\n/g')
    str=$(printf '%s' "$str" | sed 's/\r/\\r/g')
    str=$(printf '%s' "$str" | sed 's/\t/\\t/g')
    printf '%s' "$str"
}

# Check if Spotify process is running
SPOTIFY_RUNNING=false
if pgrep -x "spotify" > /dev/null 2>&1 || pgrep -f "spotify" > /dev/null 2>&1; then
    SPOTIFY_RUNNING=true
fi

# If Spotify isn't running, exit early
if [ "$SPOTIFY_RUNNING" = false ]; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Try to get metadata from playerctl first (faster, no API calls needed)
# Fall back to Spotify API if playerctl metadata isn't available yet
ARTIST_RAW=""
TITLE_RAW=""
ALBUM_RAW=""
STATUS="Unknown"

# Try playerctl first - it's faster and doesn't require API calls
if playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    # Try to get metadata with retries
    for i in {1..3}; do
        ARTIST_RAW=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null || echo "")
        TITLE_RAW=$(playerctl -p "$PLAYER" metadata title 2>/dev/null || echo "")
        ALBUM_RAW=$(playerctl -p "$PLAYER" metadata album 2>/dev/null || echo "")
        STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null || echo "Unknown")
        
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
        
        # If we got metadata, break
        if [ -n "$ARTIST_RAW" ] || [ -n "$TITLE_RAW" ]; then
            break
        fi
        
        if [ $i -lt 3 ]; then
            sleep 0.2
        fi
    done
fi

# If playerctl didn't work, try Spotify Web API as fallback
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ] && [ -f "$CONFIG_FILE" ]; then
    # Read credentials from mufetch config
    CLIENT_ID=$(grep "spotify_client_id:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    CLIENT_SECRET=$(grep "spotify_client_secret:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    
    if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
        # Get access token (using client credentials flow - note: this won't work for user endpoints)
        # For "currently playing", we'd need user authorization, which is complex
        # So we'll stick with playerctl for now, but this structure allows for future API integration
        # For now, just return empty and let waybar keep polling
        echo '{"text":"","tooltip":""}'
        exit 0
    fi
fi

# If we still don't have metadata, return empty
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ]; then
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

# Create display text
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
TOOLTIP="${ARTIST} - ${TITLE}\\nAlbum: ${ALBUM}\\nStatus: ${STATUS}\\n\\nClick: Play/Pause\\nRight-click: Next\\nMiddle-click: Previous"

# Create JSON output for waybar
if [ -n "$TEXT_DISPLAY" ]; then
    echo "{\"text\":\"${ICON} ${TEXT_DISPLAY}\",\"tooltip\":\"${TOOLTIP}\",\"class\":\"custom-spotify-info\"}"
else
    echo "{\"text\":\"\",\"tooltip\":\"\"}"
fi
