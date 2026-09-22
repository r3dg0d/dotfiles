{ config, pkgs, inputs, lib, ... }:

let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
in
let custom = import ../packages/python-tools.nix { inherit pkgs; };
  mcpLauncher = pkgs.writeShellScriptBin "obsidian-mcp" ''
    set -euo pipefail
    set -a
    source ${home}/.config/obsidian-mcp/environment
    set +a
    exec ${custom.mcp-obsidian}/bin/mcp-obsidian "$@"
  '';
in {
  environment.systemPackages = with pkgs; [
    inputs.boo.packages.x86_64-linux.default
    inputs.durdraw.packages.x86_64-linux.default
    mcpLauncher
    custom.yesitsme custom.traxosint custom.mcp-obsidian
    obsidian matcha holehe
    ffmpegthumbnailer libgsf gnome-epub-thumbnailer poppler-utils
    ripgrep fd jq yq-go fzf bat eza tmux lsof
    ttyper
    mission-center
    persepolis
  ];
  environment.pathsToLink = [ "/share/thumbnailers" ];
}
