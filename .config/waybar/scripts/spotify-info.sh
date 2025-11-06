#!/usr/bin/env bash

# Script to get Spotify track info using Spotify API
# Uses Spotify API via spotify-api-auth.sh instead of DBus/playerctl

# Redirect stderr to /dev/null to prevent any error messages from interfering
exec 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_SCRIPT="$SCRIPT_DIR/spotify-api-auth.sh"

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

# Function to output JSON (always valid, even on error)
# Match the format used in spotify.sh for consistency
output_json() {
    local text="$1"
    local tooltip="$2"
    local icon="$3"
    local artist="$4"
    local title="$5"
    local album="$6"
    local status="$7"
    local class="${8:-custom-spotify-info}"
    
    # Ensure all fields are set
    text="${text:-}"
    tooltip="${tooltip:-}"
    icon="${icon:-}"
    artist="${artist:-}"
    title="${title:-}"
    album="${album:-}"
    status="${status:-}"
    
    printf "{\"text\":\"%s\",\"tooltip\":\"%s\",\"icon\":\"%s\",\"artist\":\"%s\",\"title\":\"%s\",\"album\":\"%s\",\"alt\":\"%s\",\"class\":\"%s\"}\n" \
        "$(json_escape "$text")" \
        "$(json_escape "$tooltip")" \
        "$(json_escape "$icon")" \
        "$(json_escape "$artist")" \
        "$(json_escape "$title")" \
        "$(json_escape "$album")" \
        "$(json_escape "$status")" \
        "$class"
}

# Trap to ensure we always output valid JSON on exit
trap 'output_json "" "Error getting Spotify info"' EXIT ERR

# Get access token (with retry on first run)
ACCESS_TOKEN=$("$AUTH_SCRIPT" 2>/dev/null)

# If no token and token file doesn't exist, wait a moment and retry (handles boot timing)
if [ -z "$ACCESS_TOKEN" ] && [ ! -f "$HOME/.config/waybar/spotify_token.json" ]; then
    sleep 0.5
    ACCESS_TOKEN=$("$AUTH_SCRIPT" 2>/dev/null)
fi

if [ -z "$ACCESS_TOKEN" ]; then
    # No valid token - return empty but valid JSON
    trap - EXIT ERR  # Clear trap since we're exiting normally
    output_json "" "Waiting for Spotify authentication..." "" "" "" "" "" ""
    exit 0
fi

# Get currently playing track from Spotify API
API_RESPONSE=$(curl -s -X GET "https://api.spotify.com/v1/me/player/currently-playing" \
    -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null)

# Check if we got a valid response
if [ -z "$API_RESPONSE" ] || echo "$API_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    # No track playing or error - return empty but valid JSON
    trap - EXIT ERR
    output_json "" "No track playing" "" "" "" "" "" ""
    exit 0
fi

# Check if response indicates no track playing
if echo "$API_RESPONSE" | jq -e '.item == null' >/dev/null 2>&1; then
    trap - EXIT ERR
    output_json "" "No track playing" "" "" "" "" "" ""
    exit 0
fi

# Extract track information
TITLE_RAW=$(echo "$API_RESPONSE" | jq -r '.item.name // ""' 2>/dev/null)
ARTIST_RAW=$(echo "$API_RESPONSE" | jq -r '.item.artists[0].name // ""' 2>/dev/null)
ALBUM_RAW=$(echo "$API_RESPONSE" | jq -r '.item.album.name // ""' 2>/dev/null)
IS_PLAYING=$(echo "$API_RESPONSE" | jq -r '.is_playing // false' 2>/dev/null)

# Determine status
if [ "$IS_PLAYING" = "true" ]; then
    STATUS="Playing"
    ICON="󰏤"  # Pause icon
else
    STATUS="Paused"
    ICON="󰐊"  # Play icon
fi

# Escape for JSON
ARTIST=$(json_escape "$ARTIST_RAW")
TITLE=$(json_escape "$TITLE_RAW")
ALBUM=$(json_escape "$ALBUM_RAW")

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
if [ -n "$ARTIST" ] || [ -n "$TITLE" ]; then
    TOOLTIP="${ARTIST} - ${TITLE}\\nAlbum: ${ALBUM}\\nStatus: ${STATUS}\\n\\nClick: Play/Pause\\nRight-click: Next\\nMiddle-click: Previous"
else
    TOOLTIP="Waiting for Spotify..."
fi

# Output JSON for waybar (matching spotify.sh format)
trap - EXIT ERR  # Clear trap since we're exiting normally
output_json "${ICON} ${TEXT_DISPLAY}" "$TOOLTIP" "$ICON" "$ARTIST_RAW" "$TITLE_RAW" "$ALBUM_RAW" "$STATUS" "custom-spotify-info"
