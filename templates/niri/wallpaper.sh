#!/bin/sh
# deep-space wallpaper for niri: live (mpvpaper) when available, else the still (swaybg).
#   wallpaper.sh          live if possible
#   wallpaper.sh static   always the still image
# Looks in ~/.local/share/wallpapers first, then the system copy installed by nix/rice.nix.
mode="${1:-${DEEP_SPACE_WALLPAPER:-live}}"
find_wp() {
  for d in "${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers" /run/current-system/sw/share/wallpapers; do
    [ -f "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}
pkill -x mpvpaper 2>/dev/null; pkill -x swaybg 2>/dev/null
if [ "$mode" != static ] && command -v mpvpaper >/dev/null 2>&1 && vid="$(find_wp deep-space-live.mp4)"; then
  # -p: pause while hidden by fullscreen windows; '*' = every output
  exec mpvpaper -p -o "no-audio loop hwdec=auto panscan=1.0 profile=fast vo=gpu" '*' "$vid"
fi
img="$(find_wp deep-space.png)" || { echo "deep-space wallpaper not found" >&2; exec swaybg -c '{{void}}'; }
exec swaybg -m fill -c '{{void}}' -i "$img"
