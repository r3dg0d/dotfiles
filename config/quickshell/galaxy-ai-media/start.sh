#!/usr/bin/env bash
# toggle the Galaxy AI Media widget (starts the daemon on first use); optional page: models|run|compare|chat|jobs
export QT_QUICK_CONTROLS_STYLE=Basic
export PATH="$HOME/.local/bin:$PATH"
page="${1:-}"
if [ -n "$page" ]; then
  quickshell ipc -c galaxy-ai-media call aimedia show "$page" 2>/dev/null && exit 0
else
  quickshell ipc -c galaxy-ai-media call aimedia toggle 2>/dev/null && exit 0
fi
quickshell -c galaxy-ai-media --no-duplicate --daemonize
sleep 0.7; quickshell ipc -c galaxy-ai-media call aimedia show "${page:-models}"
