#!/usr/bin/env bash

# Script to toggle loop status: None -> Playlist -> Track -> None

PLAYER="spotify"

# Check if Spotify is running
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    exit 1
fi

# Get current loop status
CURRENT_LOOP=$(playerctl -p "$PLAYER" loop 2>/dev/null)

# Toggle: None -> Playlist -> Track -> None
case "$CURRENT_LOOP" in
    "None")
        playerctl -p "$PLAYER" loop Playlist
        ;;
    "Playlist")
        playerctl -p "$PLAYER" loop Track
        ;;
    "Track")
        playerctl -p "$PLAYER" loop None
        ;;
    *)
        playerctl -p "$PLAYER" loop Playlist
        ;;
esac

