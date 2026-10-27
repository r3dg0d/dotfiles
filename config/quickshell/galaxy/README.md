# Galaxy media

Requires Quickshell 0.3+, CAVA, playerctl and Python 3. Start with:

    bash ~/.config/quickshell/galaxy/start.sh

The player lives at the center of the screen above application windows.
It selects only Kopuz's MPRIS service, including when another player is active.
Click album art to open lyrics. Drag the lyrics header to move the window;
click × to close. Click the art again to reopen.

CAVA reads the default output monitor through PipeWire's PulseAudio service:
this visualizes the system mix, including other apps. It stops when Kopuz is
paused. Empty bars indicate silence; they are never randomly animated.

Lyrics requests happen only when lyrics are opened or the song changes while
open. Song title, artist, album and duration are sent to LRCLIB for timed lyrics; Genius is the plain-text fallback. No API token is needed.
Genius may reject requests or change its markup; the window offers Retry and
Open Genius. Timed lyrics highlight and auto-scroll using Kopuz’s MPRIS playback position, including pause and seek. Songs without timing display plain text with a clear source label. No downloaded lyrics are stored on disk.

NixOS persistent installation: add `quickshell cava python3 playerctl` to your active
`environment.systemPackages`, then rebuild. This checkout's nix/rice.nix
already includes them, but /etc/nixos may import a separate copy of the repo.
For a temporary session, run:

    nix-shell -p quickshell cava python3 playerctl --run 'bash ~/.config/quickshell/galaxy/start.sh'

The Niri configuration includes autostart, a legacy floating rule for Galaxy Lyrics,
and Mod+Shift+M to launch the widget. Quickshell avoids duplicate instances for
the same config. Changes can be removed by deleting the galaxy-media startup,
Galaxy Lyrics rule and Mod+Shift+M binding from Niri, then removing this folder.

Waybar includes a Kopuz pill beside the clock. Click to open the music player, right-click
to play/pause, and scroll to skip tracks. Reload Waybar after installing with
`pkill -SIGUSR2 -x waybar`.

On this machine, runtime/bin links the already available Nix store binaries
so the launcher works without a rebuild. These links are local bootstrap
paths; install the packages persistently before running Nix garbage collection.
The launcher uses --no-duplicate to avoid multiple player widgets.

Lyrics now use a draggable overlay panel above the player. The player uses
the top layer; the lyrics use the overlay layer. Sync requires Kopuz to
expose MPRIS position and a matching timed record in LRCLIB.

Drag the ORBIT header to move the player. The card tilts with horizontal
motion and settles with a spring animation on release. The top-right ×
hides the player and stops its visualizer without stopping music or Waybar.
Use Mod+Shift+M to reopen it. Lyrics remain independently closable.

Drag the bottom-right ◢ grip to resize the player. Content scales to fit;
minimum size is 320 × 400 when the screen has room. Resizing stays within
the current screen and preserves the top-left position.
