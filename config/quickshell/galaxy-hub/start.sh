#!/usr/bin/env bash
# galaxy-hub launcher: start.sh [weather|storage|updater|network]  (toggles that panel)
set -u
export QT_QUICK_CONTROLS_STYLE=Basic
page="${1:-weather}"
if quickshell ipc -c galaxy-hub call hub toggle "$page" 2>/dev/null; then exit 0; fi
quickshell -c galaxy-hub --no-duplicate --daemonize >/dev/null 2>&1
for _ in $(seq 1 30); do
  quickshell ipc -c galaxy-hub call hub toggle "$page" 2>/dev/null && exit 0
  sleep 0.1
done
