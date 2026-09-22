{ config, ... }:

let
  user = config.workstation.username;
in
{
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  users.users.${user}.extraGroups = [ "gamemode" ];
  programs.gamescope.enable = true;
  # Steam manages Proton; existing 32-bit graphics/audio and XWayland are retained.
}
