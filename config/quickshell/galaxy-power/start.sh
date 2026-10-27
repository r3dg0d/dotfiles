#!/usr/bin/env bash
# toggle the galaxy power menu (starts the daemon on first use)
export QT_QUICK_CONTROLS_STYLE=Basic
if quickshell ipc -c galaxy-power call power toggle 2>/dev/null; then exit 0; fi
quickshell -c galaxy-power --no-duplicate --daemonize
sleep 0.6; quickshell ipc -c galaxy-power call power open
