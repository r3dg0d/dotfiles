#!/usr/bin/env bash

# Script to get Spotify track info - keeps retrying until Spotify is available
# Uses direct DBus queries which are more reliable than playerctl

PLAYER="spotify"
DBUS_DEST="org.mpris.MediaPlayer2.spotify"

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

# Function to get metadata via direct DBus query
get_dbus_metadata() {
    # Check if DBus service exists
    if ! dbus-send --print-reply --dest="$DBUS_DEST" \
        /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:'org.mpris.MediaPlayer2.Player' \
        string:'Metadata' >/dev/null 2>&1; then
        return 1
    fi
    
    local metadata=$(dbus-send --print-reply --dest="$DBUS_DEST" \
        /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:'org.mpris.MediaPlayer2.Player' \
        string:'Metadata' 2>/dev/null)
    
    if [ -z "$metadata" ]; then
        return 1
    fi
    
    # Extract title (value comes after "xesam:title" on next line with "variant string")
    local title=$(echo "$metadata" | grep -A 2 "xesam:title" | grep "variant" | grep "string" | sed 's/.*string "\(.*\)".*/\1/' | head -1)
    
    # Extract artist (first artist from array - comes after "xesam:artist" and "variant array")
    local artist=$(echo "$metadata" | grep -A 5 "xesam:artist" | grep -A 3 "variant.*array" | grep "string" | sed 's/.*string "\(.*\)".*/\1/' | head -1)
    
    # Extract album (value comes after "xesam:album" on next line with "variant string")
    local album=$(echo "$metadata" | grep -A 2 "xesam:album" | grep "variant" | grep "string" | sed 's/.*string "\(.*\)".*/\1/' | head -1)
    
    # Get playback status
    local status=$(dbus-send --print-reply --dest="$DBUS_DEST" \
        /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:'org.mpris.MediaPlayer2.Player' \
        string:'PlaybackStatus' 2>/dev/null | grep "variant" | grep "string" | sed 's/.*string "\(.*\)".*/\1/')
    
    if [ -n "$title" ] || [ -n "$artist" ]; then
        echo "$title|$artist|$album|$status"
        return 0
    fi
    
    return 1
}

ARTIST_RAW=""
TITLE_RAW=""
ALBUM_RAW=""
STATUS="Unknown"

# Try DBus query (most reliable method)
DBUS_RESULT=$(get_dbus_metadata 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$DBUS_RESULT" ]; then
    TITLE_RAW=$(echo "$DBUS_RESULT" | cut -d'|' -f1)
    ARTIST_RAW=$(echo "$DBUS_RESULT" | cut -d'|' -f2)
    ALBUM_RAW=$(echo "$DBUS_RESULT" | cut -d'|' -f3)
    STATUS_RAW=$(echo "$DBUS_RESULT" | cut -d'|' -f4)
    
    if [ "$STATUS_RAW" = "Playing" ]; then
        STATUS="Playing"
    elif [ "$STATUS_RAW" = "Paused" ]; then
        STATUS="Paused"
    else
        STATUS="Unknown"
    fi
fi

# Fallback to playerctl if DBus didn't work
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ]; then
    if playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
        for i in {1..3}; do
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
            
            if [ -n "$ARTIST_RAW" ] || [ -n "$TITLE_RAW" ]; then
                break
            fi
            
            if [ $i -lt 3 ]; then
                sleep 0.1
            fi
        done
    fi
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

# Always output valid JSON - return empty text if no metadata yet
# Waybar will keep polling and eventually get the data when Spotify is ready
echo "{\"text\":\"${ICON} ${TEXT_DISPLAY}\",\"tooltip\":\"${TOOLTIP}\",\"class\":\"custom-spotify-info\"}"
