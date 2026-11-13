#!/usr/bin/env bash
# Galaxy updater: `nix flake update` for EVERY flake the updater tracks (hub.py find_flakes():
# ~/Projects, ~/.config incl. ~/.config/nix-flakes/*, /etc/nixos, ~/nixos, ~/.dotfiles, config.json "updater.flakes").
# Directories you can't write (e.g. a root-owned /etc/nixos flake) are updated with sudo.
# Keeps going if one fails; exits non-zero if any did. --user-only skips the sudo ones (no password prompt).
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
dry=${GALAXY_DRY_RUN:-0}; user_only=0; [ "${1:-}" = "--user-only" ] && user_only=1
fails=0; n=0
mapfile -t dirs < <(python3 ~/.config/quickshell/galaxy-hub/hub.py flakes)
if [ ${#dirs[@]} -eq 0 ]; then echo "no flakes found"; exit 0; fi
for d in "${dirs[@]}"; do
  n=$((n+1)); printf '\n\033[38;2;180;107;255m━━ nix flake update · %s\033[0m\n' "$d"
  if [ "$dry" = 1 ]; then echo "(dry run) would update $d"; continue; fi
  if [ -w "$d" ] && { [ ! -e "$d/flake.lock" ] || [ -w "$d/flake.lock" ]; }; then
    ( cd "$d" && nix flake update ) || { echo "✗ failed: $d"; fails=$((fails+1)); continue; }
    ( cd "$d" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git --no-pager diff --stat -- flake.lock )
  elif [ $user_only -eq 1 ]; then
    echo "– skipped (needs sudo): $d"
  else
    sudo nix flake update --flake "$d" || { echo "✗ failed: $d"; fails=$((fails+1)); }
  fi
done
echo; echo "flakes processed: $n, failed: $fails"
rm -f ~/.cache/galaxy-hub/updater.json
exit $fails
