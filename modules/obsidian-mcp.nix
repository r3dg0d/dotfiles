{ config, pkgs, ... }:
let
  # Obsidian's Local REST API plugin runs inside the Obsidian process itself
  # (there is no standalone daemon to package separately - see
  # https://github.com/coddingtonbear/obsidian-local-rest-api). This unit
  # keeps Obsidian itself running persistently for ${config.workstation.username}'s graphical session so
  # the plugin's HTTPS API on 127.0.0.1:27124 stays available to mcp-obsidian.
  healthcheck = pkgs.writeShellApplication {
    name = "obsidian-rest-api-healthcheck";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      env_file="$HOME/.config/obsidian-mcp/environment"
      ca_file="$HOME/.config/obsidian-mcp/ca.pem"
      if [ ! -r "$env_file" ]; then
        echo "obsidian-rest-api-healthcheck: $env_file not readable" >&2
        exit 1
      fi
      set -a
      # shellcheck source=/dev/null
      source "$env_file"
      set +a
      # Documented unauthenticated status endpoint (README "Quick start"):
      # https://127.0.0.1:27124/ - confirms the server is up and returns
      # {"authenticated": ...}; no vault data or API key is transmitted.
      if curl -fsS --max-time 5 --cacert "$ca_file" \
          "https://''${OBSIDIAN_HOST:-127.0.0.1}:''${OBSIDIAN_PORT:-27124}/" >/dev/null; then
        echo "obsidian-rest-api-healthcheck: reachable"
      else
        echo "obsidian-rest-api-healthcheck: UNREACHABLE" >&2
        exit 1
      fi
    '';
  };
in
{
  environment.systemPackages = [ healthcheck ];

  # Persistent replacement for the ad-hoc `systemd-run obsidian` used during
  # the prior session: starts with the graphical session, restarts on crash
  # (bounded, no restart loop), and keeps a clean journal trail.
  systemd.user.services.obsidian = {
    description = "Obsidian (hosts the Local REST API plugin used by mcp-obsidian)";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig = {
      StartLimitIntervalSec = 120;
      StartLimitBurst = 3;
    };
    serviceConfig = {
      ExecStart = "${pkgs.obsidian}/bin/obsidian --ozone-platform=wayland";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = 30;
    };
  };

  # Watchdog: does not reimplement the REST API, only confirms Obsidian's
  # plugin is actually answering on schedule and after each login. Hardened
  # since it only needs outbound loopback HTTPS and to read the (read-only
  # to it) credential/cert files - no vault or home write access required.
  systemd.user.services.obsidian-rest-api-healthcheck = {
    description = "Check that the Obsidian Local REST API is reachable";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${healthcheck}/bin/obsidian-rest-api-healthcheck";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.user.timers.obsidian-rest-api-healthcheck = {
    description = "Periodically check the Obsidian Local REST API";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "1min";
      OnUnitActiveSec = "5min";
      Unit = "obsidian-rest-api-healthcheck.service";
    };
  };
}
