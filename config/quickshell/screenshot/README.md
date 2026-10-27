# Galaxy Screenshot

Print / Super+Shift+S select a region with slurp. Ctrl+Print captures the
focused monitor with grim. Alt+Print uses Niri's direct window capture and
opens the same editor; it bypasses the built-in screenshot interface.

The Quickshell window provides Copy, Save, Edit, and Upload. Edit enables pen,
arrow, rectangle and opaque redaction tools, four colors and Undo. Captures
are stored under ~/Pictures/Screenshots; exports use a separate -edited.png
file. Copy renders the current annotations before placing PNG on the clipboard.
Save and Copy leave the editor open. The X closes it.

Upload has no default service. Clicking it with no endpoint opens an HTTPS
endpoint field. Enter a service accepting a multipart POST with field `file`,
then click Upload to send the edited PNG. The server must return a plain URL,
or JSON with `url` or `data.url`. The resulting URL is copied to the clipboard.
Authentication-specific services need an adapter; the current endpoint field
is for compatible servers. Nothing uploads automatically. Endpoint settings
last for the editor session only. A configured upload was not live-tested.

Dependencies: Quickshell 0.3+, grim, slurp, wl-copy, curl, Python 3 and Pillow.
The local export helper can use the existing Python 3.13 Pillow package in the
Nix store; nix/rice.nix declares a persistent Python environment with Pillow.
The launcher uses the installed Quickshell or the galaxy runtime binary.

Manual capture:
    python3 ~/.config/quickshell/screenshot/capture.py region

Niri captures and clipboard access need the actual desktop session. Capture
cancellation leaves the editor closed and produces no file.

The guns.lol preset imports a dashboard JSON/SXCU uploader config through
Host settings. Enter the downloaded config path and click Import guns.lol.
Keys stay in ~/.config/galaxyshot/uploader.json (0600), outside the repo.
Upload uses those settings only when clicked. No live account upload was tested.
