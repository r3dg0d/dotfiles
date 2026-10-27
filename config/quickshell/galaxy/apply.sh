#!/usr/bin/env bash
# Run from the desktop session to load both Waybar and the desktop player.
set -euo pipefail
galaxy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 -x waybar
else
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/galaxy"
    waybar -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" > "${XDG_CACHE_HOME:-$HOME/.cache}/galaxy/waybar.log" 2>&1 &
fi
bash "$galaxy_dir/start.sh" --daemonize
