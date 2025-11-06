#!/usr/bin/env bash

# Script to fetch and save Spotify album art for waybar image module

PLAYER="spotify"
ALBUM_ART_PATH="/tmp/spotify_album_art.jpg"
ALBUM_ART_URL=$(playerctl -p "$PLAYER" metadata mpris:artUrl 2>/dev/null)

# Check if Spotify is running and playing
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    # Remove old album art if Spotify is not running
    [ -f "$ALBUM_ART_PATH" ] && rm -f "$ALBUM_ART_PATH"
    exit 0
fi

STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null)
if [ "$STATUS" != "Playing" ] && [ "$STATUS" != "Paused" ]; then
    exit 0
fi

# Download album art if URL exists and is different
if [ -n "$ALBUM_ART_URL" ]; then
    # Check if we need to update (compare URL or check if file exists)
    if [ ! -f "$ALBUM_ART_PATH" ] || [ "$(stat -c %Y "$ALBUM_ART_PATH" 2>/dev/null || echo 0)" -lt $(($(date +%s) - 10)) ]; then
        curl -s -L "$ALBUM_ART_URL" -o "$ALBUM_ART_PATH" 2>/dev/null
    fi
    echo "$ALBUM_ART_PATH"
else
    [ -f "$ALBUM_ART_PATH" ] && rm -f "$ALBUM_ART_PATH"
fi

