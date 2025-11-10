#!/usr/bin/env bash

# Script to fetch and save Spotify album art using Spotify API
# Uses Spotify API via spotify-api-auth.sh instead of DBus/playerctl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_SCRIPT="$SCRIPT_DIR/spotify-api-auth.sh"
ALBUM_ART_PATH="/tmp/spotify_album_art.jpg"

# Get access token
ACCESS_TOKEN=$("$AUTH_SCRIPT" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    # No valid token - keep existing art if present
    if [ -f "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
    fi
    exit 0
fi

# Get currently playing track from Spotify API (with timeout to prevent freezing)
API_RESPONSE=$(curl -s --max-time 2 --connect-timeout 1 -X GET "https://api.spotify.com/v1/me/player/currently-playing" \
    -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null)
CURL_EXIT=$?

# Check if curl failed or returned empty (timeout or network error)
if [ $CURL_EXIT -ne 0 ] || [ -z "$API_RESPONSE" ]; then
    # Keep existing art if present
    if [ -f "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
    fi
    exit 0
fi

# Check for rate limiting or non-JSON responses (like "Too many requests")
if echo "$API_RESPONSE" | timeout 0.5 jq . >/dev/null 2>&1; then
    # Valid JSON - continue processing
    :
else
    # Not valid JSON (likely rate limiting or error message) - try playerctl as fallback
    ALBUM_ART_URL=$(playerctl -p spotify metadata mpris:artUrl 2>/dev/null || echo "")
    if [ -n "$ALBUM_ART_URL" ] && [ "$ALBUM_ART_URL" != "" ]; then
        # Download album art if file doesn't exist or is older than 10 seconds
        if [ ! -f "$ALBUM_ART_PATH" ] || [ "$(stat -c %Y "$ALBUM_ART_PATH" 2>/dev/null || echo 0)" -lt $(($(date +%s) - 10)) ]; then
            curl -s --max-time 3 --connect-timeout 1 -L "$ALBUM_ART_URL" -o "$ALBUM_ART_PATH" 2>/dev/null
        fi
        # Output path if file exists and is valid
        if [ -f "$ALBUM_ART_PATH" ] && [ -s "$ALBUM_ART_PATH" ]; then
            echo "$ALBUM_ART_PATH"
        fi
    else
        # Keep existing art if present
        if [ -f "$ALBUM_ART_PATH" ]; then
            echo "$ALBUM_ART_PATH"
        fi
    fi
    exit 0
fi

# Check if we got a valid response (with timeout on jq to prevent freezing)
if echo "$API_RESPONSE" | timeout 0.5 jq -e '.error' >/dev/null 2>&1; then
    # No track playing or error - keep existing art if present
    if [ -f "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
    fi
    exit 0
fi

# Check if response indicates no track playing
if echo "$API_RESPONSE" | timeout 0.5 jq -e '.item == null' >/dev/null 2>&1; then
    if [ -f "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
    fi
    exit 0
fi

# Extract album art URL (use the largest available image, with timeout to prevent freezing)
ALBUM_ART_URL=$(echo "$API_RESPONSE" | timeout 0.5 jq -r '.item.album.images[0].url // .item.album.images[1].url // .item.album.images[2].url // ""' 2>/dev/null || echo "")

# Download album art if URL exists
if [ -n "$ALBUM_ART_URL" ] && [ "$ALBUM_ART_URL" != "null" ]; then
    # Check if we need to update (download if file doesn't exist or is older than 10 seconds)
    if [ ! -f "$ALBUM_ART_PATH" ] || [ "$(stat -c %Y "$ALBUM_ART_PATH" 2>/dev/null || echo 0)" -lt $(($(date +%s) - 10)) ]; then
        curl -s --max-time 3 --connect-timeout 1 -L "$ALBUM_ART_URL" -o "$ALBUM_ART_PATH" 2>/dev/null
    fi
    
    # Output path if file exists and is valid
    if [ -f "$ALBUM_ART_PATH" ] && [ -s "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
    fi
else
    # No album art URL - keep existing art if present (don't remove it)
    if [ -f "$ALBUM_ART_PATH" ]; then
        echo "$ALBUM_ART_PATH"
fi
fi

# Always exit cleanly
exit 0
