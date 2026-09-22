{ config, pkgs, lib, ... }:
let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
  entries = {
    "nm-connection-editor" = "Advanced Network Configuration";
    "blueman-adapters" = "Bluetooth Adapters";
    "blueman-manager" = "Bluetooth Manager";
    "gvim" = "GVim";
    "org.pulseaudio.pavucontrol" = "Volume Control";
  };
  overrides = lib.mapAttrsToList (id: name:
    let file = pkgs.writeText "${id}.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=${name}
      NoDisplay=true
      Hidden=true
    '';
    in "L+ ${home}/.local/share/applications/${id}.desktop - ${user} users - ${file}"
  ) entries;
in {
  # No Home Manager is in use. Manage these specific files through NixOS tmpfiles.
  systemd.tmpfiles.rules = [
    "L+ ${home}/.config/user-dirs.dirs - ${user} users - ${../user/user-dirs.dirs}"
    "d ${home}/Desktop 0755 ${user} users -"
    "d ${home}/Downloads 0755 ${user} users -"
    "d ${home}/Templates 0755 ${user} users -"
    "d ${home}/Public 0755 ${user} users -"
    "d ${home}/Documents 0755 ${user} users -"
    "d ${home}/Music 0755 ${user} users -"
    "d ${home}/.config/rmpc 0755 ${user} users -"
    "L+ ${home}/.config/rmpc/config.ron - ${user} users - ${../user/rmpc.ron}"
    "d ${home}/.local/share/applications 0755 ${user} users -"
    "d ${home}/.config/ambxst/config 0755 ${user} users -"
    "L+ ${home}/.config/ambxst/config/general.json - ${user} users - ${../user/general.json}"
    "L+ ${home}/.config/hypr/hyprland.lua - ${user} users - ${../user/hyprland.lua}"
    "d ${home}/Pictures 0755 ${user} users -"
    "d ${home}/Pictures/Wallpapers 0755 ${user} users -"
    "d ${home}/Pictures/Screenshots 0755 ${user} users -"
    "d ${home}/Videos 0755 ${user} users -"
    "d ${home}/Videos/Recordings 0755 ${user} users -"
    "d ${home}/.config/ghostty 0755 ${user} users -"
    "d ${home}/.config/ghostty/shaders 0755 ${user} users -"
    "L+ ${home}/.config/ghostty/config.ghostty - ${user} users - ${../user/ghostty/config.ghostty}"
    "L+ ${home}/.config/ghostty/shaders/green-crt.glsl - ${user} users - ${../user/ghostty/shaders/green-crt.glsl}"
    # fuzzel is the SUPER + SPACE application launcher (user/hyprland.lua) and
    # the "Open With" picker (modules/apps-extra.nix); one config styles both.
    "d ${home}/.config/fuzzel 0755 ${user} users -"
    "L+ ${home}/.config/fuzzel/fuzzel.ini - ${user} users - ${../user/fuzzel.ini}"
    "d ${home}/.config/gtk-3.0 0755 ${user} users -"
    "d ${home}/.config/gtk-4.0 0755 ${user} users -"
    "L+ ${home}/.config/gtk-3.0/settings.ini - ${user} users - ${../user/gtk-settings.ini}"
    "L+ ${home}/.config/gtk-4.0/settings.ini - ${user} users - ${../user/gtk-settings.ini}"
    # rmpc's shipped .desktop has no Icon= key; this is the same-basename
    # user override XDG already prefers over the system one, with only
    # Icon= added — every other key copied verbatim.
    "L+ ${home}/.local/share/applications/rmpc.desktop - ${user} users - ${../user/rmpc.desktop}"
    "d ${home}/.local/share/icons/hicolor/scalable/apps 0755 ${user} users -"
    "L+ ${home}/.local/share/icons/hicolor/scalable/apps/rmpc.svg - ${user} users - ${../user/rmpc.svg}"
  ] ++ overrides;
}
