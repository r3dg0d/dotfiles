#!/usr/bin/env bash
# toggle the Galaxy clipboard manager (starts the daemon and the single watcher on first use)
export QT_QUICK_CONTROLS_STYLE=Basic
here="$(cd "$(dirname "$0")" && pwd)"
# clip.py watch exits immediately if a watcher (ours or cliphist's) is already running
(setsid python3 "$here/clip.py" watch >/dev/null 2>&1 &)
[ "$1" = "--watch-only" ] && exit 0
if quickshell ipc -c galaxy-clip call clip toggle 2>/dev/null; then exit 0; fi
quickshell -c galaxy-clip --no-duplicate --daemonize
sleep 0.6; quickshell ipc -c galaxy-clip call clip open
