#!/usr/bin/env bash

# Script to display control icons for Spotify (prev, next, loop, shuffle)
# Usage: spotify-control.sh [prev|next|loop|shuffle]

PLAYER="spotify"
ACTION="$1"

# Check if Spotify is running
if ! playerctl -l 2>/dev/null | grep -q "$PLAYER"; then
    echo ""
    exit 0
fi

# Get status
STATUS=$(playerctl -p "$PLAYER" status 2>/dev/null)
if [ "$STATUS" != "Playing" ] && [ "$STATUS" != "Paused" ]; then
    echo ""
    exit 0
fi

case "$ACTION" in
    "prev")
        # Previous icon always shows
        echo "󰒮"
        ;;
    "next")
        # Next icon always shows
        echo "󰒭"
        ;;
    "loop")
        # Show loop icon based on loop status
        # Note: playerctl status is shifted - we need to map it correctly to match Spotify UI
        LOOP_STATUS=$(playerctl -p "$PLAYER" loop 2>/dev/null || echo "None")
        case "$LOOP_STATUS" in
            "None")
                echo "󰑗"  # Shows as normal loop in Spotify (Playlist)
                ;;
            "Playlist")
                echo "󰑖"  # Shows as loop 1 in Spotify (Track)
                ;;
            "Track")
                echo "󰑘"  # Shows as no loop in Spotify (None)
                ;;
            *)
                echo "󰑘"  # Default to no loop
                ;;
        esac
        ;;
    "shuffle")
        # Show shuffle icon based on shuffle status
        SHUFFLE_STATUS=$(playerctl -p "$PLAYER" shuffle 2>/dev/null || echo "Off")
        if [ "$SHUFFLE_STATUS" = "On" ]; then
            echo "󰒝"  # Shuffle on
        else
            echo "󰒞"  # Shuffle off
        fi
        ;;
    *)
        exit 1
        ;;
esac

