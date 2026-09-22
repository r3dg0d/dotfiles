{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    zed-editor

    # Useful for Zed AI agent sandboxing.
    bubblewrap
  ];
}
