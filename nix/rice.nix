# NixOS module for the deep-space niri rice: packages, fonts and the SDDM theme.
# Import it from configuration.nix:  imports = [ /path/to/dotfiles/nix/rice.nix ];
# The per-user configs are applied separately with ./install.sh (into ~/.config).
{ config, lib, pkgs, ... }:
let
  sddmTheme = pkgs.callPackage ./sddm-theme.nix { };
  # wallpapers at /run/current-system/sw/share/wallpapers (fallback if ~/.local/share/wallpapers is missing)
  wallpapers = pkgs.runCommand "deep-space-wallpapers" { } ''
    mkdir -p $out/share/wallpapers
    cp ${../wallpaper/deep-space.png} $out/share/wallpapers/deep-space.png
    cp ${../wallpaper/deep-space-live.mp4} $out/share/wallpapers/deep-space-live.mp4
  '';
in
{
  programs.niri.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    ghostty waybar fuzzel mako swaybg mpvpaper swaylock swayidle xwayland-satellite
    fastfetch wl-clipboard grim slurp brightnessctl pavucontrol networkmanagerapplet
    papirus-icon-theme desktop-file-utils
    sddmTheme wallpapers
  ];

  # fuzzel and other launchers read .desktop files from XDG_DATA_DIRS (includes /run/current-system/sw/share)
  environment.pathsToLink = [ "/share/applications" "/share/icons" "/share/wallpapers" ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];

  services.displayManager.sddm = {
    theme = "deep-space";
    # The theme only imports QtQuick; listed explicitly so the greeter always has it.
    extraPackages = [ pkgs.kdePackages.qtdeclarative ];
  };
}
