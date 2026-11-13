#!/usr/bin/env bash
# Smoke-check the Galaxy popups: QML loads without warnings, IPC works, and (when a Wayland session with
# wl-clipboard is available) emoji and clipboard entries really arrive on the clipboard byte for byte.
#   QT_QPA_PLATFORM=offscreen tools/qs-harness/check.sh
# Uses throwaway XDG state unless KEEP_STATE=1. Needs PySide6; see README.md for what this cannot check.
set -u
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
[ "${KEEP_STATE:-0}" = 1 ] || export XDG_STATE_HOME="$tmp/state"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }
h()   { python3 tools/qs-harness/run.py "$@" 2>&1; }
for w in galaxy-emoji galaxy-clip galaxy-ai-media galaxy-power; do
  out="$(h "$w" --wait 0.6 | tail -1)"
  case "$out" in *'"warnings": []'*) ok "$w loads with no QML warnings";; *) bad "$w: $out";; esac
done
if command -v wl-copy >/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  want() { got="$(wl-paste -n | python3 -c 'import sys; print("-".join("%X" % ord(c) for c in sys.stdin.buffer.read().decode()))')"
           [ "$got" = "$2" ] && ok "emoji: $1 -> $2" || bad "emoji: $1 gave $got, wanted $2"; }
  e()    { printf x | wl-copy; name="$1"; expect="$2"; shift 2; h galaxy-emoji --wait 0.6 --call emoji.open "$@" --call emoji.press:Return >/dev/null; want "$name" "$expect"; }
  e "ASCII search 'rocket'"        1F680 --call emoji.type:rocket
  e "flag"                         1F1F5-1F1F9 --call "emoji.type:flag portugal"
  e "skin tone"                    1F44B-1F3FE --call emoji.setTone:4 --call "emoji.type:waving hand"
  e "family (ZWJ)"                 1F468-200D-1F469-200D-1F467-200D-1F466 --call "emoji.type:family man woman girl boy"
  e "multi-person, two tones"      1F9D1-1F3FC-200D-1F91D-200D-1F9D1-1F3FF --call "emoji.type:people holding hands" --call emoji.press:Variants --call emoji.press:Down
  e "variation selector + ZWJ"     1F3F3-FE0F-200D-1F308 --call "emoji.type:rainbow flag"
  printf keep | wl-copy; h galaxy-emoji --wait 0.5 --call emoji.open --call emoji.type:cat --call emoji.press:Escape >/dev/null
  [ "$(wl-paste -n)" = keep ] && ok "emoji: Escape closes without touching the clipboard" || bad "emoji: Escape changed the clipboard"

  clip="python3 config/quickshell/galaxy-clip/clip.py"
  if pgrep -x wl-paste >/dev/null; then ok "clipboard: a watcher is already running (not starting another)"; own=0
  else (setsid $clip watch >/dev/null 2>&1 &); sleep 0.6; own=1; fi
  $clip watch 2>&1 | grep -q "already running" && ok "clipboard: second watcher refuses to start" || bad "clipboard: duplicate watcher"
  printf 'one\ntwo\n\tthree' | wl-copy; sleep 0.4; printf 'Ünï 日本語 🧑🏼‍🤝‍🧑🏿' | wl-copy; sleep 0.4; printf 'one\ntwo\n\tthree' | wl-copy; sleep 0.4
  n="$($clip list --query two | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["entries"]))')"
  [ "$n" = 1 ] && ok "clipboard: duplicate capture kept once" || bad "clipboard: duplicate stored $n times"
  h galaxy-clip --wait 0.7 --call clip.open --call clip.type:日本 --call clip.press:Return >/dev/null; sleep 0.3
  [ "$(wl-paste -n)" = 'Ünï 日本語 🧑🏼‍🤝‍🧑🏿' ] && ok "clipboard: search + Enter restores Unicode text exactly" || bad "clipboard: restore mismatch"
  [ "$own" = 1 ] && pkill -x wl-paste
else
  echo "  skip  clipboard round trips (no WAYLAND_DISPLAY or wl-copy)"
fi
exit $fail
