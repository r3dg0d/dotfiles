{ config, pkgs, ... }:
let
  mpdConfig = pkgs.writeText "${config.workstation.username}-mpd.conf" ''
    music_directory "~/Music"
    playlist_directory "~/.local/state/mpd/playlists"
    db_file "~/.local/state/mpd/database"
    state_file "~/.local/state/mpd/state"
    sticker_file "~/.local/state/mpd/sticker.sql"
    bind_to_address "127.0.0.1"
    port "6600"
    auto_update "yes"
    audio_output {
      type "pulse"
      name "PipeWire"
    }
  '';
in
{
  environment.systemPackages = [
    pkgs.mpd
    pkgs.rmpc
    pkgs.mpc
  ];
  # User service uses ${config.workstation.username}'s PipeWire/Pulse socket, without a competing system MPD.
  systemd.user.services.mpd = {
    description = "Music Player Daemon for ${config.workstation.username}";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "${config.workstation.username}";
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/Music %h/.local/state/mpd/playlists";
      ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon ${mpdConfig}";
      Restart = "on-failure";
    };
  };
}
