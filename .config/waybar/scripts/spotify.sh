#!/usr/bin/env bash

# Get Spotify player status
PLAYER="spotify"

# Check if Spotify is running
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Get status
STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null)
if [ "$STATUS" != "Playing" ] && [ "$STATUS" != "Paused" ]; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi

# Get metadata
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g')
TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g')
ALBUM=$(playerctl -p "$PLAYER" metadata album 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g')

# Set icon based on status
if [ "$STATUS" = "Playing" ]; then
    ICON="󰏤"  # Pause icon
else
    ICON="󰐊"  # Play icon
fi

# Truncate text if too long (max 50 chars)
TEXT="${ARTIST} - ${TITLE}"
if [ ${#TEXT} -gt 50 ]; then
    TEXT="${TEXT:0:47}..."
fi

# Create JSON output for waybar with all fields for tooltip-format
echo "{\"text\":\"${TEXT}\",\"icon\":\"${ICON}\",\"artist\":\"${ARTIST}\",\"title\":\"${TITLE}\",\"album\":\"${ALBUM}\",\"alt\":\"${STATUS}\",\"class\":\"custom-spotify\"}"

