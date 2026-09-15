{
  config,
  pkgs,
  lib,
  ...
}:
let
  entries = {
    "nm-connection-editor" = "Advanced Network Configuration";
    "blueman-adapters" = "Bluetooth Adapters";
    "blueman-manager" = "Bluetooth Manager";
    "gvim" = "GVim";
    "org.pulseaudio.pavucontrol" = "Volume Control";
  };
  overrides = lib.mapAttrsToList (
    id: name:
    let
      file = pkgs.writeText "${id}.desktop" ''
        [Desktop Entry]
        Type=Application
        Name=${name}
        NoDisplay=true
        Hidden=true
      '';
    in
    "L+ ${config.workstation.homeDirectory}/.local/share/applications/${id}.desktop - ${config.workstation.username} users - ${file}"
  ) entries;
in
{
  # No Home Manager is in use. Manage these specific files through NixOS tmpfiles.
  systemd.tmpfiles.rules =
    (map
      (path: "d ${config.workstation.homeDirectory}/${path} 0755 ${config.workstation.username} users -")
      [
        ".config"
        ".config/hypr"
        ".local"
        ".local/share"
        ".local/share/icons"
        ".local/share/icons/hicolor"
        ".local/share/icons/hicolor/scalable"
      ]
    )
    ++ [
      "d ${config.workstation.homeDirectory}/.config/rmpc 0755 ${config.workstation.username} users -"
      "L+ ${config.workstation.homeDirectory}/.config/rmpc/config.ron - ${config.workstation.username} users - ${../config/rmpc.ron}"
      "d ${config.workstation.homeDirectory}/.local/share/applications 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/.config/ambxst/config 0755 ${config.workstation.username} users -"
      "L+ ${config.workstation.homeDirectory}/.config/hypr/hyprland.lua - ${config.workstation.username} users - ${../config/hyprland.lua}"
      "d ${config.workstation.homeDirectory}/Pictures 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/Pictures/Wallpapers 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/Pictures/Screenshots 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/Videos 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/Videos/Recordings 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/.config/ghostty 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/.config/ghostty/shaders 0755 ${config.workstation.username} users -"
      "L+ ${config.workstation.homeDirectory}/.config/ghostty/config.ghostty - ${config.workstation.username} users - ${../config/ghostty/config.ghostty}"
      "L+ ${config.workstation.homeDirectory}/.config/ghostty/shaders/green-crt.glsl - ${config.workstation.username} users - ${../config/ghostty/shaders/green-crt.glsl}"
      "d ${config.workstation.homeDirectory}/.config/gtk-3.0 0755 ${config.workstation.username} users -"
      "d ${config.workstation.homeDirectory}/.config/gtk-4.0 0755 ${config.workstation.username} users -"
      "L+ ${config.workstation.homeDirectory}/.config/gtk-3.0/settings.ini - ${config.workstation.username} users - ${../config/gtk-settings.ini}"
      "L+ ${config.workstation.homeDirectory}/.config/gtk-4.0/settings.ini - ${config.workstation.username} users - ${../config/gtk-settings.ini}"
      # rmpc's shipped .desktop has no Icon= key; this is the same-basename
      # user override XDG already prefers over the system one, with only
      # Icon= added — every other key copied verbatim.
      "L+ ${config.workstation.homeDirectory}/.local/share/applications/rmpc.desktop - ${config.workstation.username} users - ${../config/rmpc.desktop}"
      "d ${config.workstation.homeDirectory}/.local/share/icons/hicolor/scalable/apps 0755 ${config.workstation.username} users -"
    ]
    ++ overrides;
  # Copy once with tmpfiles C: existing preferences are preserved, and the UI can save.
  systemd.user.tmpfiles.rules =
    (map (name: "C %h/.config/ambxst/config/${name} - - - - ${../config/ambxst/config}/${name}") (
      builtins.attrNames (builtins.readDir ../config/ambxst/config)
    ))
    ++ [
      "C %h/.config/ambxst/binds.json - - - - ${../config/ambxst/binds.json}"
      "C %h/.config/gtk-3.0/gtk.css - - - - ${../config/theme-seeds/gtk-3.0/gtk.css}"
      "C %h/.config/gtk-4.0/gtk.css - - - - ${../config/theme-seeds/gtk-4.0/gtk.css}"
      "d %h/.config/qt5ct/colors 0755 - - -"
      "d %h/.config/qt6ct/colors 0755 - - -"
      "C %h/.config/qt5ct/colors/ambxst.colors - - - - ${../config/theme-seeds/qt5ct/colors/ambxst.colors}"
      "C %h/.config/qt6ct/colors/ambxst.colors - - - - ${../config/theme-seeds/qt6ct/colors/ambxst.colors}"
    ];
}
