{ config, pkgs, ... }:

let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
in
{
  # Jellyfin media server — web UI at http://localhost:8096
  # openFirewall exposes 8096/8920 TCP and 1900/7359 UDP (discovery) to the LAN.
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # GPU access for NVENC transcoding (enable it in Dashboard → Playback → Transcoding).
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # ${home} is 0700, so the server can't read it. Keep libraries in
  # /srv/media instead: owned by neo, group jellyfin, setgid so new files
  # inherit the group.
  users.users.${user}.extraGroups = [ "jellyfin" ];
  systemd.tmpfiles.rules = [
    "d /srv/media 2775 ${user} jellyfin -"
    "d /srv/media/movies 2775 ${user} jellyfin -"
    "d /srv/media/shows 2775 ${user} jellyfin -"
    "d /srv/media/music 2775 ${user} jellyfin -"
  ];

  # Expose ~/Videos to Jellyfin without opening up ${home}: read-only bind
  # mount. Files must stay world-readable (default umask 022 does this).
  fileSystems."/srv/media/videos" = {
    device = "${home}/Videos";
    fsType = "none";
    options = [ "bind" "ro" "nofail" ];
  };

  environment.systemPackages = with pkgs; [
    jellyfin-desktop # desktop client (formerly jellyfin-media-player)
  ];
}
