#!/usr/bin/env bash
# toggle the Galaxy emoji picker (starts the daemon on first use)
export QT_QUICK_CONTROLS_STYLE=Basic
if quickshell ipc -c galaxy-emoji call emoji toggle 2>/dev/null; then exit 0; fi
quickshell -c galaxy-emoji --no-duplicate --daemonize
sleep 0.6; quickshell ipc -c galaxy-emoji call emoji open
