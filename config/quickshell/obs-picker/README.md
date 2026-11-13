# obs-picker — Quickshell screencast chooser for xdg-desktop-portal-wlr

Used as xdpw's chooser (chooser_type=dmenu). xdpw feeds exact labels on
stdin ("Monitor: DP-1 <description>", "Window: <title> (<id>)"); `chooser`
shows them in the Quickshell overlay (shell.qml) and prints the chosen line
verbatim to stdout. Esc/click-outside = no output, exit 1 (cancelled).

Files:
- shell.qml  — the picker UI (layer-shell overlay, mouse + ↑/↓/Enter/Esc)
- chooser    — python wrapper: stdin labels -> items.json -> quickshell ->
               result file -> stdout. Uses absolute /run/current-system/sw/bin
               paths because the xdpw user service has a restricted PATH.
Test hooks: OBS_PICKER_TEST=first (auto-select first) / =cancel.
