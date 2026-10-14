#!/usr/bin/env bash
# Apply the deep-space rice to the current user's ~/.config.
#
#   ./install.sh            copy configs (default)
#   ./install.sh --link     symlink configs to this checkout instead (edits flow back here)
#   ./install.sh --dry-run  show what would change
#
# Existing files that differ are moved to ~/.config/.dotfiles-backup/<timestamp>/ first.
# Re-running is safe: files that already match are left alone.
set -euo pipefail

MODE=copy
DRY=no
for a in "$@"; do
  case "$a" in
    --link) MODE="link" ;;
    --copy) MODE="copy" ;;
    --dry-run) DRY=yes ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
backup="$cfg/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
changed=0 same=0 backed=0

act() { if [ "$DRY" = yes ]; then echo "  would: $*"; else "$@"; fi; }

place() { # place SRC DEST
  local src="$1" dst="$2"
  if [ "$MODE" = link ] && [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then same=$((same+1)); return; fi
  if [ "$MODE" = copy ] && [ -f "$dst" ] && [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then same=$((same+1)); return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local rel="${dst#"$HOME"/}"
    act mkdir -p "$(dirname "$backup/$rel")"
    act mv "$dst" "$backup/$rel"
    backed=$((backed+1))
  fi
  act mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = link ]; then act ln -s "$src" "$dst"; else act cp "$src" "$dst"; fi
  echo "  $MODE ${dst/#$HOME/\~}"
  changed=$((changed+1))
}

echo "deep-space rice -> $cfg ($MODE)"
while IFS= read -r -d '' f; do
  rel="${f#"$here"/config/}"
  case "$rel" in sddm/*) continue ;; esac   # the SDDM theme is installed system-wide (nix/rice.nix)
  place "$f" "$cfg/$rel"
done < <(find "$here/config" -type f -print0 | sort -z)

place "$here/wallpaper/deep-space.png" "$data/wallpapers/deep-space.png"
place "$here/wallpaper/deep-space-live.mp4" "$data/wallpapers/deep-space-live.mp4"
[ "$DRY" = yes ] || chmod +x "$cfg/niri/wallpaper.sh" 2>/dev/null || true
act mkdir -p "$HOME/Pictures/Screenshots"

msg="done: $changed updated, $same already up to date"
[ "$backed" -gt 0 ] && msg="$msg, $backed backed up to ${backup/#$HOME/\~}"
echo "$msg"
