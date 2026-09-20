# SDDM with the Matrix Code Rain theme.
#
# This replaces ly, which was the greeter here previously: the ly option is
# gone rather than set to false, so nothing in this tree enables a second
# display manager. Both greeters drive the same
# services.displayManager.generic.execCmd, so enabling both would be an
# evaluation conflict rather than a silent race -- there is exactly one active
# display manager.
#
# Like ly's, SDDM's display-manager.service conflicts with autovt@tty1.service,
# which stops the getty carrying a live tty1 session. Apply this with
# `nixos-rebuild boot` and a deliberate reboot rather than `switch` from that
# session. (The unit is marked X-RestartIfChanged=false, so a switch does not
# restart a greeter that is already running; the change takes effect at the
# next boot either way.)
{ pkgs, ... }:
let
  matrixCodeRain = pkgs.callPackage ../packages/sddm-matrix-code-rain.nix { };
in
{
  services.displayManager.sddm = {
    enable = true;

    # Theme.Current. Matches the directory the package installs and the
    # Theme-Id in the theme's metadata.desktop.
    theme = "matrix-code-rain";

    # The greeter needs a display server of its own, and this configuration has
    # no X11 at all: services.xserver.enable is false, Hyprland is a Wayland
    # compositor, and only the NVIDIA driver entry lives under
    # services.xserver. Enabling X purely to draw a login screen would add an X
    # server to a system that otherwise has none, so the greeter runs on SDDM's
    # own Wayland path.
    #
    # The compositor is the module default, Weston in kiosk mode: the upstream
    # default and a much smaller dependency than the kwin alternative. A
    # Wayland greeter says nothing about the session -- the session is whatever
    # its .desktop file starts.
    #
    # If the greeter ever fails to start, the other VTs are untouched:
    # Ctrl+Alt+F2, log in, and `start-hyprland` still works.
    wayland.enable = true;
  };

  # programs.hyprland.enable registers the Wayland session file SDDM lists;
  # this makes it the pre-selected one. Not the uwsm-managed variant: nothing
  # here is set up for UWSM, and modules/desktop-integration.nix's
  # hyprland-session target assumes the plain start-hyprland session.
  services.displayManager.defaultSession = "hyprland";

  # Installs $out/share/sddm/themes/matrix-code-rain, which is where the SDDM
  # module's ThemeDir points.
  environment.systemPackages = [ matrixCodeRain ];
}
