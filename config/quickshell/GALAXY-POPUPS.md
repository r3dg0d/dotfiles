# Galaxy popups: emoji picker, clipboard history, AI Media

Three Quickshell configs in the Purple Galaxy style. Each is a layer-shell overlay that takes exclusive
keyboard focus only while it is open; closing it unmaps the surface and the compositor gives focus back to
the window you were in. Each runs as its own `quickshell -c NAME` instance and is driven over IPC, like the
power menu.

| Config | IPC target | Launcher | niri bind (this repo) |
| ------ | ---------- | -------- | --------------------- |
| `galaxy-emoji` | `emoji` | `~/.config/quickshell/galaxy-emoji/start.sh` | `Mod+Shift+Period` (see below for `Mod+Period`) |
| `galaxy-clip` | `clip` | `~/.config/quickshell/galaxy-clip/start.sh` | `Mod+E` |
| `galaxy-ai-media` | `aimedia` | `~/.config/quickshell/galaxy-ai-media/start.sh [models\|run\|compare\|chat\|jobs]` | `Mod+Alt+I` |

Quickshell 0.3 IPC: `quickshell ipc -c galaxy-emoji call emoji toggle` (also `open`, `close`).

## Key bindings and collisions

**niri (`config/niri/config.kdl`, the config on `main`).** Checked against the tracked binds:

* `Mod+E` was free. It now opens clipboard history.
* `Mod+Period` is **already bound** to `expel-window-from-column` (a niri default). It was left alone; the
  emoji picker is on `Mod+Shift+Period`, which was free. To move it to `Mod+Period`, delete the
  `Mod+Period { expel-window-from-column; }` line, uncomment the prepared `Mod+Period` line next to the emoji
  bind and remove the `Mod+Shift+Period` line. `Mod+BracketRight` (`consume-or-expel-window-right`) covers most
  of what the old bind did.
* `Mod+Alt+I` was free. It opens AI Media.

**Hyprland (`config/hyprland.lua` on the `nixos-workstation-archive` branch).** Not changed by this work,
because that branch is archived and `main` is niri. Checked against that file:

* `SUPER + E` is free.
* `SUPER + PERIOD` is **already bound** to `ambxst run emoji`, and `SUPER + V` to `ambxst run clipboard`.

If Hyprland is what you run, these are the lines in that file's own format (replace the existing
`SUPER + PERIOD` line rather than adding a second one):

```lua
hl.bind(mainMod .. " + PERIOD", hl.dsp.exec_cmd("bash ~/.config/quickshell/galaxy-emoji/start.sh"))   -- replaces: ambxst run emoji
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("bash ~/.config/quickshell/galaxy-clip/start.sh"))
hl.exec_cmd("bash ~/.config/quickshell/galaxy-clip/start.sh --watch-only")                             -- with the other startup lines
```

These were written from the archived config, not run: there was no Hyprland session available. Confirm with
`hyprctl binds | grep -i -A3 period` after reloading.

## Emoji picker

* Search by Unicode name or keyword (several words narrow the result). `←→↑↓` move, `Enter` copies and closes,
  `Esc` closes, `Tab` / `Shift+Tab` change category, `Alt+0…5` set the skin tone, `Ctrl+Enter` (or right click)
  lists every skin-tone variant of the selected emoji, including two-tone multi-person ones.
* The whole sequence is copied: regional-indicator pairs, tag sequences, ZWJ sequences, variation selectors
  and modifiers. It goes to the Wayland clipboard with `wl-copy`.
* Recents (40) live in `~/.local/state/galaxy-emoji/recents.json`.
* Artwork is Twemoji 15.0.0. It is not in this repo: the picker's **Get Twemoji art** button (or
  `python3 ~/.config/quickshell/galaxy-emoji/emoji.py assets`) downloads the pinned npm tarball once, checks
  its sha512 and unpacks only the SVGs to `~/.local/share/galaxy-emoji/twemoji-15.0.0/`. Until then, and for
  the 54 newer emoji Twemoji 15.0.0 has no art for, the system emoji font is used. See `galaxy-emoji/ATTRIBUTION.md`.
* There is no direct insertion into the focused app. Nothing in this rice provides a dependable way to type
  into another client (no `wtype`, no input-method setup), so the picker copies and you paste.

## Clipboard history

* One watcher: `wl-paste --watch clip.py store`, started by `start.sh --watch-only` at login and held by a
  lock file, so a second one cannot start. If a `wl-paste --watch cliphist store` process is already running,
  no watcher is started and the popup reads and edits cliphist's history instead.
* Text (searchable, full text not just the preview) and images (PNG/JPEG/WebP/BMP/GIF, with previews).
  Copying the same thing again moves it to the top; it is never stored twice.
* `↑↓` move, `Enter` restores and closes, `Delete` removes, `Ctrl+P` pauses or resumes capture,
  `Ctrl+Shift+Delete` twice clears everything, `Esc` closes.
* Bounded: 300 entries, 14 days, 1 MB per text, 16 MB per image, 256 MB of images.
* Store: `~/.local/state/galaxy-clip/` (directory 0700, database and images 0600). Clearing also compacts the
  database so deleted text does not linger in the file.
* Never stored: selections carrying `x-kde-passwordManagerHint = secret` (KeePassXC and others set this),
  anything wl-clipboard flags `CLIPBOARD_STATE=sensitive`, and anything copied while paused.
* Nothing is logged and nothing is sent anywhere.

## AI Media

Front end to the `ai-media` hub from [ai-media-cli](https://github.com/r3dg0d/ai-media-cli) (`ai-media` must be
on `PATH`, or set `AI_MEDIA_BIN`). Browse and filter the catalog by capability, installed, GPU fit and
benchmarks; see why a model cannot run and how to fix it; fill in a model's parameters and run it; follow,
cancel and open jobs; compare up to three models; chat with a local LLM with streamed output and temperature,
max-token, context and GPU-layer controls.

Jobs belong to the hub, not the widget: closing or restarting the popup loses nothing, and jobs started from
the CLI or MCP show up here.

## Reload and rollback

Apply after `./install.sh`:

```bash
niri validate && niri msg action load-config-file
```

```bash
for c in galaxy-emoji galaxy-clip galaxy-ai-media; do quickshell kill -c $c 2>/dev/null; QT_QUICK_CONTROLS_STYLE=Basic quickshell -c $c --no-duplicate --daemonize; done
```

```bash
bash ~/.config/quickshell/galaxy-clip/start.sh --watch-only
```

Roll back (install.sh keeps the previous files under its backup directory; or from the checkout):

```bash
git -C ~/src/dotfiles checkout main -- config/niri/config.kdl templates/niri/config.kdl && ~/src/dotfiles/install.sh
```

```bash
for c in galaxy-emoji galaxy-clip galaxy-ai-media; do quickshell kill -c $c; done; pkill -f 'galaxy-clip/clip.py store'
```

```bash
rm -rf ~/.config/quickshell/galaxy-{emoji,clip,ai-media} ~/.local/state/galaxy-{emoji,clip} ~/.local/share/galaxy-emoji ~/.local/bin/galaxy-{emoji,clip,ai-media}
```

## Checking it

`tools/qs-harness/check.sh` loads all three configs against a stand-in for Quickshell, drives them through
their IPC functions and, inside a Wayland session, verifies emoji and clipboard entries on the real clipboard.
`python3 -m pytest tests/` covers the backends. Neither can check layer-shell placement, focus handover or the
compositor binds; do that once on the desktop.
