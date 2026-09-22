# SDDM with the Matrix Code Rain theme.
#
# This replaces ly, which was the greeter here until now: services.
# displayManager.ly.enable is gone rather than set to false, so nothing in this
# tree enables a second display manager. Both greeters drive the same
# services.displayManager.generic.execCmd, so having both enabled would be an
# evaluation conflict, not a silent race -- there is exactly one active display
# manager after this change.
#
# Like ly's, SDDM's display-manager.service conflicts with autovt@tty1.service,
# which stops the getty carrying a live tty1 session. Apply this with
# `nixos-rebuild boot` and a deliberate reboot rather than `switch` from that
# session.
{ pkgs, ... }:
let
  matrixCodeRain = pkgs.callPackage ../packages/sddm/matrix-code-rain.nix { };
in
{
  services.displayManager.sddm = {
    enable = true;

    # Theme.Current. Matches the directory the package installs and the
    # Theme-Id in its metadata.desktop.
    theme = "matrix-code-rain";

    # The greeter needs a display server of its own, and this machine has no
    # X11 at all: services.xserver.enable is false, Hyprland is a Wayland
    # compositor, and only the NVIDIA driver entry lives under services.
    # xserver. Enabling X purely to draw a login screen would add an X server
    # to a system that otherwise has none, so the greeter runs on SDDM's own
    # Wayland path instead.
    #
    # The compositor is the module's default, Weston in kiosk mode -- a much
    # smaller dependency than the kwin alternative, and the upstream default.
    # The greeter being Wayland says nothing about the session: the session is
    # whatever its .desktop file starts, and Hyprland's own entry is unchanged.
    #
    # If the greeter ever fails to come up, the other VTs are untouched:
    # Ctrl+Alt+F2, log in, and `start-hyprland` still works.
    wayland.enable = true;
  };

  # programs.hyprland.enable (configuration.nix) registers the Wayland session
  # file SDDM lists; this makes it the pre-selected one. Not the uwsm-managed
  # variant: nothing in this configuration is set up for UWSM, and
  # modules/desktop-integration.nix's hyprland-session target assumes the
  # plain start-hyprland session.
  services.displayManager.defaultSession = "hyprland";

  # Installs $out/share/sddm/themes/matrix-code-rain, which is exactly where
  # the SDDM module's ThemeDir points.
  environment.systemPackages = [ matrixCodeRain ];
}
