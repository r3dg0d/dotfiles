#!/usr/bin/env bash
# Galaxy "Update everything": runs every step even if one fails, then prints a summary.
# sudo is typed by you in this terminal; nothing stores a password.
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH   # setuid sudo lives in /run/wrappers/bin
P='\033[38;2;180;107;255m'; G='\033[38;2;125;255;168m'; R='\033[38;2;255;92;138m'; Y='\033[38;2;255;212;121m'; N='\033[0m'
names=(); results=(); times=(); fails=0
step() {  # step "Name" command...
  local name=$1; shift; local t0=$SECONDS
  printf "\n${P}━━ %s${N}\n${P}✦ %s${N}\n" "$name" "$*"
  if "$@"; then results+=("ok"); else local rc=$?; results+=("fail ($rc)"); fails=$((fails+1)); fi
  names+=("$name"); times+=("$((SECONDS-t0))s")
}
skip() { names+=("$1"); results+=("skipped: $2"); times+=("-"); }

step "Channel update"  sudo nix-channel --update
step "NixOS rebuild (switch)" sudo nixos-rebuild switch
step "User profile"    env NIXPKGS_ALLOW_UNFREE=1 nix profile upgrade --all --impure
if command -v flatpak >/dev/null; then
  step "Flatpak (user)"   flatpak update --user -y
  step "Flatpak (system)" sudo flatpak update --system -y
else skip "Flatpak" "not installed"; fi
if command -v fwupdmgr >/dev/null; then
  fwupdmgr refresh --force >/dev/null 2>&1
  step "Firmware" bash -c 'fwupdmgr update -y --no-reboot-check; rc=$?; [ $rc -eq 2 ] && { echo "no firmware updates"; exit 0; }; exit $rc'
else skip "Firmware" "fwupd not enabled"; fi

printf "\n${P}━━ Summary${N}\n"
for i in "${!names[@]}"; do
  case "${results[$i]}" in ok) c=$G; m="✓";; skipped*) c=$Y; m="–";; *) c=$R; m="✗";; esac
  printf "  ${c}%s %-24s %-22s${N} %s\n" "$m" "${names[$i]}" "${results[$i]}" "${times[$i]}"
done
mkdir -p ~/.cache/galaxy-hub
{ date '+%F %r'; for i in "${!names[@]}"; do echo "${names[$i]}: ${results[$i]}"; done; } > ~/.cache/galaxy-hub/last-update.txt
python3 ~/.config/quickshell/galaxy-hub/hub.py bar-refresh >/dev/null 2>&1 &
[ $fails -eq 0 ] && printf "\n${G}✓ all steps done${N}\n" || printf "\n${R}✗ %d step(s) failed — scroll up for details${N}\n" $fails
exit $fails
