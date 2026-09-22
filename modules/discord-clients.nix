{ pkgs, inputs, lib, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  oxicordPkg = inputs.oxicord.packages.${system}.default;
in {
  nixpkgs.config.allowUnfree = true;

  # Equibop: Equicord Discord client (nixpkgs). Unofficial — Discord ToS risk.
  # Oxicord: Discord TUI from github:linuxmobile/oxicord (flake input). Auth
  # interactively; never put tokens in Nix, Git, or Obsidian.
  environment.systemPackages = [
    pkgs.equibop
    oxicordPkg
  ];
}
