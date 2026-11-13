#!/usr/bin/env bash
set -euo pipefail
galaxy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$galaxy_dir/runtime/bin:$PATH"
for program in quickshell cava python3; do
    if ! command -v "$program" >/dev/null; then
        echo "Galaxy media needs $program. See ~/.config/quickshell/galaxy/README.md" >&2
        exit 1
    fi
done
export QT_QUICK_CONTROLS_STYLE=Basic
export QT_QUICK_CONTROLS_BASIC_ACCENT='#b46bff'
export QT_QUICK_CONTROLS_BASIC_BACKGROUND='#1a1630'
export QT_QUICK_CONTROLS_BASIC_FOREGROUND='#f2f0ff'
# Older running Waybar instances still pass "lyrics"; keep their click
# command compatible while routing all tray launches to the music player.
if [ "${1:-}" = lyrics ]; then shift; fi
if quickshell ipc -c galaxy call galaxy showMedia 2>/dev/null; then exit 0; fi
exec quickshell -c galaxy --no-duplicate "$@"
