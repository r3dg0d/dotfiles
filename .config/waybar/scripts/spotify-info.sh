#!/usr/bin/env bash

# Script to get Spotify track info (title, artist) for waybar custom module

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
ARTIST=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g")
TITLE=$(playerctl -p "$PLAYER" metadata title 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g")
ALBUM=$(playerctl -p "$PLAYER" metadata album 2>/dev/null | sed 's/&/&amp;/g' | sed 's/"/\\"/g' | sed "s/'/\\'/g")
LOOP_STATUS=$(playerctl -p "$PLAYER" loop 2>/dev/null || echo "None")

# Set icon based on status
if [ "$STATUS" = "Playing" ]; then
    ICON="󰏤"  # Pause icon
else
    ICON="󰐊"  # Play icon
fi

# Create display text (truncate if too long)
# Loop icon is now shown as a separate button, not in the text
TEXT="${ARTIST} - ${TITLE}"
if [ ${#TEXT} -gt 40 ]; then
    TEXT="${TEXT:0:37}..."
fi

# Create JSON output for waybar
echo "{\"text\":\"${ICON} ${TEXT}\",\"tooltip\":\"${ARTIST} - ${TITLE}\\nAlbum: ${ALBUM}\\nStatus: ${STATUS}\\nLoop: ${LOOP_STATUS}\\n\\nClick: Play/Pause\\nRight-click: Next\\nMiddle-click: Previous\\nScroll: Skip\\nBackward-click: Toggle Loop\",\"class\":\"custom-spotify-info\"}"

