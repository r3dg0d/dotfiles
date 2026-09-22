{ config, pkgs, lib, ... }:

let
  user = config.workstation.username;
in
{
  # Hardware / monitoring / editor / capture / emulation tooling for neo's daily driver.
  # gpu-screen-recorder remains owned by modules/screen-recorder.nix (wrapped for NVENC).
  environment.systemPackages = with pkgs; [
    dmidecode
    config.boot.kernelPackages.turbostat
    stress-ng
    fastfetch
    lm_sensors
    neovim
    ripgrep
    tree-sitter
    asciinema
    gnome-text-editor
    grim
    slurp
    # wl-clipboard already pulled transitively; keep explicit for clarity
    wl-clipboard
    imv
    # rpcs3: removed temporarily — nixpkgs build ICE in wolfssl (GCC segfault) on this pin
    lmstudio
    # build tools NvChad / Treesitter may need (gcc/gnumake already in development.nix;
    # listed here only if missing — development.nix already has them)
  ];

  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # Preserve JetBrainsMono Nerd Font (already in configuration.nix fonts.packages).

  # KeystrokeNoise reads /dev/input/event* without being root. Narrow privilege:
  # seat/group access only — the daemon itself never runs as root.
  users.users.${user}.extraGroups = [ "input" ];
}

