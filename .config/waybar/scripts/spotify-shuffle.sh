#!/usr/bin/env bash

# Script to toggle shuffle status

PLAYER="spotify"

# Check if Spotify is running
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    exit 1
fi

# Get current shuffle status
CURRENT_SHUFFLE=$(playerctl -p "$PLAYER" shuffle 2>/dev/null)

# Toggle shuffle
if [ "$CURRENT_SHUFFLE" = "On" ]; then
    playerctl -p "$PLAYER" shuffle Off
else
    playerctl -p "$PLAYER" shuffle On
fi

# Send signal to waybar to update modules
pkill -SIGRTMIN+8 waybar
