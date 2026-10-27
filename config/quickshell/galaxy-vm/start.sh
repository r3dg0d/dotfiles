#!/usr/bin/env bash
# open a Construct app: start.sh all|android|windows|linux|ios|macos  (starts the daemon on first use)
export QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_CONTROLS_BASIC_ACCENT='#b46bff'
k="${1:-all}"
quickshell ipc -c galaxy-vm call vm open "$k" 2>/dev/null && exit 0
quickshell -c galaxy-vm --no-duplicate --daemonize
for _ in $(seq 20); do sleep 0.25; quickshell ipc -c galaxy-vm call vm open "$k" 2>/dev/null && exit 0; done
