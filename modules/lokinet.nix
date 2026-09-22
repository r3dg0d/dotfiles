{ pkgs, ... }:
{
  environment.systemPackages = [ (pkgs.callPackage ../packages/lokinet-gui.nix { }) ];
  services.lokinet = {
    enable = true;
    # The pinned nixpkgs source package is marked broken; use the official release.
    package = pkgs.callPackage ../packages/lokinet-bin.nix { };
    # Route only overlay names through Lokinet using systemd-resolved below.
    useLocally = false;
    settings = {
      dns.bind = "127.3.2.1:53";
      network.ifname = "lokinet0";
    };
  };
  services.resolved.enable = true;
  systemd.services.lokinet-dns = {
    description = "Route Lokinet DNS domains through the Lokinet interface";
    requires = [ "lokinet.service" "systemd-resolved.service" ];
    after = [ "lokinet.service" "systemd-resolved.service" ];
    partOf = [ "lokinet.service" ];
    wantedBy = [ "lokinet.service" ];
    path = [ pkgs.iproute2 pkgs.systemd pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
    script = ''
      for attempt in $(seq 1 60); do
        if ip link show lokinet0 >/dev/null 2>&1; then
          resolvectl dns lokinet0 127.3.2.1
          resolvectl domain lokinet0 '~loki' '~snode'
          resolvectl default-route lokinet0 no
          exit 0
        fi
        sleep 1
      done
      echo "Lokinet interface did not appear" >&2
      exit 1
    '';
  };
}
