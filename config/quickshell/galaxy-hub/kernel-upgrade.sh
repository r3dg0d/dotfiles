#!/usr/bin/env bash
# Galaxy kernel upgrade:  kernel-upgrade.sh X.Y [--check-only]
# 1. makes sure nixpkgs has linuxPackages_X_Y   2. builds that kernel + the pinned NVIDIA open modules
# 3. only then edits /etc/nixos/r3dg0d-kernel.nix (backup first) and runs `nixos-rebuild boot` (never switch).
# Any rebuild failure restores the file. Old generations stay in the boot menu. sudo is typed by you.
set -u
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH
P='\033[38;2;180;107;255m'; G='\033[38;2;125;255;168m'; R='\033[38;2;255;92;138m'; Y='\033[38;2;255;212;121m'; N='\033[0m'
say() { printf "${P}✦ %s${N}\n" "$*"; }; ok() { printf "${G}✓ %s${N}\n" "$*"; }
warn() { printf "${Y}! %s${N}\n" "$*"; }; die() { printf "${R}✗ %s${N}\n" "$*"; exit 1; }
SERIES=${1:-}; MODE=${2:-}
[[ $SERIES =~ ^[0-9]+\.[0-9]+$ ]] || die "usage: kernel-upgrade.sh X.Y [--check-only]"
ATTR=${SERIES//./_}; KF=${KERNEL_NIX_FILE:-/etc/nixos/r3dg0d-kernel.nix}; HERE=$(dirname "$(readlink -f "$0")")
CHECK=$HOME/.local/share/galaxy-hub/kernel-check.nix; CACHE=$HOME/.cache/galaxy-hub; mkdir -p "$CACHE"
[ -r "$KF" ] || die "cannot read $KF"
grep -qE 'boot\.kernelPackages *= *.*linuxPackages_[0-9]+_[0-9]+' "$KF" || die "$KF has no 'boot.kernelPackages = ... linuxPackages_X_Y' line to switch"
CUR=$(grep -oE 'linuxPackages_[0-9]+_[0-9]+' "$KF" | head -1); say "selection file: $KF (now $CUR → linuxPackages_$ATTR)"

has_attr() { nix-instantiate --eval --expr "with import <nixpkgs> {}; pkgs.linuxPackages_$ATTR.kernel.version" 2>/dev/null; }
V=$(has_attr | tr -d '"')
if [ -z "$V" ]; then
  warn "linuxPackages_$ATTR is not in the installed nixpkgs channel yet."
  read -rp "Run 'sudo nix-channel --update' to look for it? [y/N] " a
  [[ $a == [yY]* ]] || die "stopped; nothing changed"
  sudo nix-channel --update || die "channel update failed"
  V=$(has_attr | tr -d '"'); [ -n "$V" ] || die "linuxPackages_$ATTR still missing after the update; nixpkgs has not packaged $SERIES for this channel (try again later)"
fi
ok "nixpkgs has linux $V"

# stage the edited selection and prove it builds (no root, nothing installed yet)
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
sed -E "/boot\.kernelPackages/ s/linuxPackages_[0-9]+_[0-9]+/linuxPackages_$ATTR/; s/^# Kernel [0-9]+\.[0-9]+ line/# Kernel $SERIES line/" "$KF" > "$STAGE/r3dg0d-kernel.nix"
NV=$(grep -oE 'version *= *"[0-9.]+"' "$KF" | head -1 | grep -oE '[0-9.]+')
say "building linux $V + NVIDIA open $NV modules against it (cached parts download, the module compiles)"
LOG=$CACHE/kernel-check-$ATTR.log
nix-build "$CHECK" --arg kfile "$STAGE/r3dg0d-kernel.nix" -o "$CACHE/kernel-check-$ATTR" > "$LOG" 2>&1 &
BP=$!; while kill -0 $BP 2>/dev/null; do printf "\r${P}  … %s${N}\033[K" "$(tail -n1 "$LOG" | cut -c1-70)"; sleep 2; done; printf "\r\033[K"
if ! wait $BP; then
  printf '{"series":"%s","ok":false,"nvidia":"%s","at":"%s","log":"%s"}\n' "$SERIES" "$NV" "$(date '+%a %-I:%M %p')" "$LOG" > "$CACHE/kernel-check.json"
  rm -f "$CACHE/updater.json"
  printf "\n${R}✗ NVIDIA %s (or the kernel) does NOT build on linux %s. Nothing was changed.${N}\n" "$NV" "$V"; tail -n 30 "$LOG"; exit 1
fi
printf '{"series":"%s","ok":true,"nvidia":"%s","kernel_version":"%s","at":"%s","log":"%s"}\n' "$SERIES" "$NV" "$V" "$(date '+%a %-I:%M %p')" "$LOG" > "$CACHE/kernel-check.json"
rm -f "$CACHE/updater.json"
ok "NVIDIA $NV builds against linux $V (nvidia.ko, nvidia-drm, nvidia-modeset, nvidia-uvm)"
[ "$MODE" = "--check-only" ] && { ok "check only: no files touched"; exit 0; }

echo; warn "This will: back up $KF, point it at linux $V, then run: sudo nixos-rebuild boot"
warn "It never runs 'switch': the running kernel stays until you reboot; the old generation stays in the boot menu."
read -rp "Type yes to continue: " a; [ "$a" = yes ] || die "stopped; nothing changed"
BAK=$KF.bak-kernel-$(date +%Y%m%d%H%M%S)
sudo cp -a "$KF" "$BAK" || die "backup failed"; ok "backup: $BAK"
sudo install -m 644 -o root -g root "$STAGE/r3dg0d-kernel.nix" "$KF" || die "could not write $KF"
say "sudo nixos-rebuild boot"
if sudo nixos-rebuild boot; then
  echo; ok "linux $V is staged as the next boot entry (not switched)."
  printf "${P}  New generation: %s${N}\n" "$(readlink /nix/var/nix/profiles/system)"
  printf "${P}  Reboot to use it; pick the previous generation in the boot menu to go back.${N}\n"
  printf "${P}  Backup of the old selection: %s${N}\n" "$BAK"
else
  s=$?; echo; sudo cp -a "$BAK" "$KF" && warn "rebuild failed (exit $s): restored $KF from $BAK" || printf "${R}✗ rebuild failed AND restore failed: copy %s over %s${N}\n" "$BAK" "$KF"
  exit "$s"
fi
