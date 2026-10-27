#!/usr/bin/env bash
# galaxy-power action runner. Dry run: GALAXY_POWER_DRY=1, --dry-run, or ~/.cache/galaxy-power.dry exists.
dry=${GALAXY_POWER_DRY:-0}; [ "${1:-}" = --dry-run ] && { dry=1; shift; }; [ -e "$HOME/.cache/galaxy-power.dry" ] && dry=1
act=${1:-}; arg=${2:-}
case "$act" in
  lock)      cmd=(swaylock -f -c 07060d --inside-color 120c24 --ring-color b46bff --key-hl-color d4b8ff --line-color 00000000 --separator-color 00000000 --text-color f2f0ff --inside-ver-color 1a1630 --ring-ver-color 6bd0ff --inside-wrong-color 2a0f1e --ring-wrong-color ff8fb1 --font Cellforge) ;;
  logout)    cmd=(niri msg action quit --skip-confirmation) ;;
  suspend)   cmd=(systemctl suspend) ;;
  hibernate) cmd=(systemctl hibernate) ;;
  reboot)    cmd=(systemctl reboot) ;;
  shutdown)  cmd=(systemctl poweroff) ;;
  firmware)  cmd=(systemctl reboot --firmware-setup) ;;
  entry)     cmd=(systemctl reboot "--boot-loader-entry=$arg") ;;
  entries)   busctl --json=short get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager BootLoaderEntries; exit ;;
  caps)      for m in CanSuspend CanHibernate CanRebootToFirmwareSetup CanRebootToBootLoaderEntry; do
               printf '%s=%s\n' "$m" "$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $m 2>/dev/null | cut -d'"' -f2)"; done; exit ;;
  *) echo "usage: power.sh [--dry-run] lock|logout|suspend|hibernate|reboot|shutdown|firmware|entry <id>|entries|caps" >&2; exit 2 ;;
esac
if [ "$dry" = 1 ]; then echo "$(date '+%F %r') DRY-RUN: ${cmd[*]}" | tee -a "$HOME/.cache/galaxy-power.log"; exit 0; fi
exec "${cmd[@]}"
