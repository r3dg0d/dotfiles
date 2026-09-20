# fuzzel as the SUPER + SPACE application launcher.
#
# On the source machine the pieces of this live in two larger modules (the
# package alongside the other desktop utilities, the config link with the rest
# of the linked dotfiles). Here they are kept together, because this is one
# feature and nothing else in this repository needs fuzzel.
#
# The same binary also serves the "Open With" picker on the source machine, so
# one config styles both surfaces.
{
  config,
  pkgs,
  ...
}:
let
  # A wrapper rather than a bare `fuzzel` in the keybind: fuzzel has no
  # single-instance guard of its own, so a second press would stack a second
  # launcher on top of the first.
  appLauncher = pkgs.writeShellApplication {
    name = "app-launcher";
    runtimeInputs = [
      pkgs.procps
      pkgs.fuzzel
    ];
    text = ''
      if pgrep -x fuzzel >/dev/null 2>&1; then
        exit 0
      fi
      exec fuzzel "$@"
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.fuzzel
    appLauncher
  ];

  systemd.tmpfiles.rules = [
    "d ${config.workstation.homeDirectory}/.config/fuzzel 0755 ${config.workstation.username} users -"
    "L+ ${config.workstation.homeDirectory}/.config/fuzzel/fuzzel.ini - ${config.workstation.username} users - ${../config/fuzzel.ini}"
  ];
}
