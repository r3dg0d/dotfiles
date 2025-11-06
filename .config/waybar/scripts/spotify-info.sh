#!/usr/bin/env bash

# Script to get Spotify track info using Spotify Web API (via mufetch credentials)
# Falls back to playerctl if API isn't set up yet

PLAYER="spotify"
CONFIG_FILE="$HOME/.config/mufetch/config.yaml"
TOKEN_FILE="$HOME/.config/waybar/spotify_token.json"

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

# Try to get metadata from playerctl (primary method - faster and more reliable)
ARTIST_RAW=""
TITLE_RAW=""
ALBUM_RAW=""
STATUS="Unknown"

# Try playerctl with retries
if playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    for i in {1..5}; do
        ARTIST_RAW=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null || echo "")
        TITLE_RAW=$(playerctl -p "$PLAYER" metadata title 2>/dev/null || echo "")
        ALBUM_RAW=$(playerctl -p "$PLAYER" metadata album 2>/dev/null || echo "")
        STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null || echo "Unknown")
        
        # Try xesam keys if short form didn't work
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
        
        # Wait before retrying (waybar polls every second, so we don't need long waits)
        if [ $i -lt 5 ]; then
            sleep 0.15
        fi
    done
fi

# If playerctl didn't work, try Spotify Web API as fallback
# This requires OAuth setup - see spotify-api-auth.sh for setup instructions
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ] && [ -f "$CONFIG_FILE" ] && [ -f "$TOKEN_FILE" ]; then
    # Get access token
    ACCESS_TOKEN=$("$HOME/.config/waybar/scripts/spotify-api-auth.sh" 2>/dev/null)
    
    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        # Get currently playing track from Spotify API
        API_RESPONSE=$(curl -s -X GET "https://api.spotify.com/v1/me/player/currently-playing" \
            -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null)
        
        if [ -n "$API_RESPONSE" ] && echo "$API_RESPONSE" | jq -e '.item' >/dev/null 2>&1; then
            TITLE_RAW=$(echo "$API_RESPONSE" | jq -r '.item.name // empty' 2>/dev/null)
            ARTIST_RAW=$(echo "$API_RESPONSE" | jq -r '.item.artists[0].name // empty' 2>/dev/null)
            ALBUM_RAW=$(echo "$API_RESPONSE" | jq -r '.item.album.name // empty' 2>/dev/null)
            IS_PLAYING=$(echo "$API_RESPONSE" | jq -r '.is_playing // false' 2>/dev/null)
            
            if [ "$IS_PLAYING" = "true" ]; then
                STATUS="Playing"
            else
                STATUS="Paused"
            fi
        fi
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
    echo '{"text":"","tooltip":""}'
fi
