{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.thunderbird
    pkgs.qbittorrent
    pkgs.dino # XMPP/Jabber client; no account pre-configured
    pkgs.yt-dlp
    pkgs.ffmpeg # needed by yt-dlp for merging separate audio/video streams
    pkgs.mpv
  ];
  services.flatpak.enable = true;
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "127.0.0.1";
    port = 11434;
  };

  # Mullvad: daemon (pkgs.mullvad) + GUI (pkgs.mullvad-vpn, no longer bundled
  # with the daemon package itself). No account details, no autostart/
  # auto-connect; sign in from the GUI. The setuid mullvad-exclude wrapper
  # is opt-in upstream and left disabled here to avoid an unrequested
  # setuid binary on a security workstation.
  services.mullvad-vpn = {
    enable = true;
    enableExcludeWrapper = false;
    gui.enable = true;
  };
}
