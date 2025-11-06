#!/usr/bin/env bash

# Monitor DBus for Spotify MPRIS service and signal waybar to update
# This runs in the background and triggers waybar updates when Spotify becomes available

DBUS_DEST="org.mpris.MediaPlayer2.spotify"
WAYBAR_PID=$(pgrep -x waybar)

# Function to signal waybar to update
signal_waybar() {
    local pid=$(pgrep -x waybar)
    if [ -n "$pid" ]; then
        # Send SIGRTMIN+8 to waybar to trigger update (signal 8)
        kill -SIGRTMIN+8 "$pid" 2>/dev/null || true
    fi
}

# Monitor for Spotify MPRIS service
while true; do
    # Check if Spotify DBus service exists
    if dbus-send --print-reply --dest="$DBUS_DEST" \
        /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        string:'org.mpris.MediaPlayer2.Player' \
        string:'Metadata' >/dev/null 2>&1; then
        # Spotify is available, signal waybar
        signal_waybar
        # Once detected, check periodically for changes
        sleep 5
    else
        # Spotify not available yet, check more frequently
        sleep 2
    fi
done

