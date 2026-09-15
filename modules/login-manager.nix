{ ... }:
{
  # ly replaces the previous "manual TTY login, then type start-hyprland /
  # ambxst by hand" flow. There was no other display manager, greeter, or
  # getty-autologin configured anywhere in this tree (checked: no
  # services.xserver.displayManager.*, no services.greetd, no
  # services.displayManager.autoLogin, no exec-Hyprland in a shell rc) —
  # so this is additive, not a replacement of a competing mechanism.
  # UWSM is not used anywhere in this config either, so there's no
  # ly/UWSM session-wrapping friction to account for.
  services.displayManager.ly.enable = true;

  # programs.hyprland.enable (configuration.nix) already registers a
  # Wayland session file ly can list; just make it the highlighted default.
  services.displayManager.defaultSession = "hyprland";
}
