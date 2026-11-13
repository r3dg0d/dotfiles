# Quickshell (git.outfoxxed.me/quickshell/quickshell): Qt6/QML desktop widget
# shell. Not in nixpkgs, so pulled directly from its own flake and pinned to
# a release tag (not master) for reproducibility.
{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = [
    (builtins.getFlake
      "git+https://git.outfoxxed.me/quickshell/quickshell?ref=refs/tags/v0.3.2"
    ).packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
