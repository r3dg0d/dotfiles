#!/usr/bin/env bash

# Monitor DBus for Spotify MPRIS service and signal waybar to update
# This runs in the background and triggers waybar updates when Spotify becomes available

DBUS_DEST="org.mpris.MediaPlayer2.spotify"
SPOTIFY_AVAILABLE=false

# Function to signal waybar to update
signal_waybar() {
    # Always get fresh PID in case waybar restarted
    local pid=$(pgrep -x waybar)
    if [ -n "$pid" ]; then
        # Send SIGRTMIN+8 to waybar to trigger update (signal 8)
        kill -SIGRTMIN+8 "$pid" 2>/dev/null || true
    fi
}

# Wait for waybar to start (with timeout)
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 30 ]; do
    if pgrep -x waybar >/dev/null; then
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Monitor for Spotify MPRIS service
while true; do
    # Check if Spotify DBus service exists
    if dbus-send --print-reply --dest="$DBUS_DEST" \
        /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:'org.mpris.MediaPlayer2.Player' \
        string:'Metadata' >/dev/null 2>&1; then
        # Spotify is available
        if [ "$SPOTIFY_AVAILABLE" = false ]; then
            # First time Spotify becomes available - signal immediately
            SPOTIFY_AVAILABLE=true
            signal_waybar
            # Signal again after a short delay to ensure waybar picks it up
            sleep 1
            signal_waybar
        fi
        # Once detected, check periodically for changes
        sleep 5
    else
        # Spotify not available yet
        SPOTIFY_AVAILABLE=false
        # Check more frequently when waiting for Spotify
        sleep 2
    fi
done

