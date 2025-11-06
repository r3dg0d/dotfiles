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

# Check if Spotify is running
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Get metadata first - this is more reliable than status check
# After login, metadata might be available even if status is not Playing/Paused
# Try multiple times with slight delay if metadata isn't immediately available
ARTIST_RAW=""
TITLE_RAW=""
ALBUM_RAW=""

# Try to get metadata - retry up to 3 times if not available (handles race condition after login)
for i in {1..3}; do
    ARTIST_RAW=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null || echo "")
    TITLE_RAW=$(playerctl -p "$PLAYER" metadata title 2>/dev/null || echo "")
    ALBUM_RAW=$(playerctl -p "$PLAYER" metadata album 2>/dev/null || echo "")
    
    # If we got metadata, break early
    if [ -n "$ARTIST_RAW" ] || [ -n "$TITLE_RAW" ]; then
        break
    fi
    
    # Only delay if we haven't found metadata and this isn't the last attempt
    if [ $i -lt 3 ]; then
        sleep 0.05
    fi
done

# Get status - but don't exit early based on it if we have metadata
STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null || echo "Unknown")
LOOP_STATUS=$(playerctl -p "$PLAYER" loop 2>/dev/null || echo "None")

# Check if we have valid metadata - if we do, show it regardless of status
# This handles the case where Spotify is detected but not actively playing
if [ -z "$ARTIST_RAW" ] && [ -z "$TITLE_RAW" ]; then
    # No metadata available - check if status is valid before exiting
    # Allow Stopped status to pass through, as metadata might still be available
    if [ "$STATUS" != "Playing" ] && [ "$STATUS" != "Paused" ] && [ "$STATUS" != "Stopped" ]; then
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

