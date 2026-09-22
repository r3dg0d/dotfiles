{ config, pkgs, ... }:
let
  user = config.workstation.username;
  mpdConfig = pkgs.writeText "neo-mpd.conf" ''
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
in {
  environment.systemPackages = [ pkgs.mpd pkgs.rmpc pkgs.mpc ];
  # User service uses neo's PipeWire/Pulse socket, without a competing system MPD.
  systemd.user.services.mpd = {
    description = "Music Player Daemon for neo";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = user;
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/Music %h/.local/state/mpd/playlists";
      ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon ${mpdConfig}";
      Restart = "on-failure";
    };
  };
}
