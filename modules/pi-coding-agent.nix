{ config, pkgs, ... }:

let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
in
{
  environment.systemPackages = [ pkgs.pi-coding-agent ];
  environment.etc."pi/models.json".source = ../ai/pi/models.json;
  # One Nix-managed model catalog for neo and root. Writable settings are
  # seeded once; auth/tokens stay in each user's private files (never in Nix).
  systemd.tmpfiles.rules = [
    "d ${home}/.pi 0700 ${user} users -"
    "d ${home}/.pi/agent 0700 ${user} users -"
    "L+ ${home}/.pi/agent/models.json - ${user} users - /etc/pi/models.json"
    "C ${home}/.pi/agent/settings.json 0600 ${user} users - ${../ai/pi/settings.json}"

    "d /root/.pi 0700 root root -"
    "d /root/.pi/agent 0700 root root -"
    "L+ /root/.pi/agent/models.json - root root - /etc/pi/models.json"
    "C /root/.pi/agent/settings.json 0600 root root - ${../ai/pi/settings.json}"
  ];
}
