# NixOS module for the deep-space niri rice: packages, fonts and the SDDM theme.
# Import it from configuration.nix:  imports = [ /path/to/dotfiles/nix/rice.nix ];
# The per-user configs are applied separately with ./install.sh (into ~/.config).
{ config, lib, pkgs, ... }:
let
  sddmTheme = pkgs.callPackage ./sddm-theme.nix { };
in
{
  programs.niri.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    ghostty waybar fuzzel mako swaybg swaylock swayidle xwayland-satellite
    fastfetch wl-clipboard grim slurp brightnessctl pavucontrol networkmanagerapplet
    sddmTheme
  ];

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
