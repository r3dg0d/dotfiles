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
bindir="$HOME/.local/bin"
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

# Launchers (~/.local/bin)
if [ -d "$here/bin" ]; then
  while IFS= read -r -d '' f; do
    place "$f" "$bindir/$(basename "$f")"
  done < <(find "$here/bin" -type f -print0 | sort -z)
fi

# Desktop entries: @HOME@ is rewritten to the installing user's home (desktop files don't expand $HOME)
if [ -d "$here/share/applications" ]; then
  tmpdir=""
  [ "$DRY" = yes ] || tmpdir=$(mktemp -d)
  while IFS= read -r -d '' f; do
    name=$(basename "$f")
    if [ "$DRY" = yes ]; then
      echo "  would: install desktop $name (HOME=$HOME)"
    else
      # Always copy: @HOME@ is rewritten, so a symlink to the template would be wrong.
      sed "s|@HOME@|$HOME|g" "$f" > "$tmpdir/$name"
      MODE=copy place "$tmpdir/$name" "$data/applications/$name"
    fi
  done < <(find "$here/share/applications" -name '*.desktop' -print0 | sort -z)
  [ -n "$tmpdir" ] && rm -rf "$tmpdir"
fi

# Icons
if [ -d "$here/share/icons" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$here"/share/icons/}"
    place "$f" "$data/icons/$rel"
  done < <(find "$here/share/icons" -type f -print0 | sort -z)
fi

# Executable bits on scripts (copies only; --link follows the checkout's modes)
if [ "$DRY" != yes ]; then
  chmod +x "$cfg/niri/wallpaper.sh" 2>/dev/null || true
  find "$cfg/quickshell" -type f \( -name '*.sh' -o -name '*.py' -o -name 'chooser' \) -exec chmod +x {} + 2>/dev/null || true
  chmod +x "$bindir/galaxy-disk" 2>/dev/null || true
fi
act mkdir -p "$HOME/Pictures/Screenshots"

msg="done: $changed updated, $same already up to date"
[ "$backed" -gt 0 ] && msg="$msg, $backed backed up to ${backup/#$HOME/\~}"
echo "$msg"
