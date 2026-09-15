{ config, ... }:
{
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  users.users.${config.workstation.username}.extraGroups = [ "gamemode" ];
  programs.gamescope.enable = true;
  # Steam manages Proton; existing 32-bit graphics/audio and XWayland are retained.
}
