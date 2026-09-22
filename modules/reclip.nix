{ pkgs, lib, ... }:
let
  reclip = import ../packages/reclip.nix { inherit pkgs; };
  port = 8899;
  url = "http://localhost:${toString port}";

  reclipCli = pkgs.writeShellApplication {
    name = "reclip";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      systemd
      xdg-utils
      ncurses
    ];
    text = ''
            PORT=${toString port}
            URL=${lib.escapeShellArg url}
            UNIT=reclip.service

            if [ -t 1 ] && [ -z "''${NO_COLOR:-}" ]; then
              B=$(tput bold || true); D=$(tput dim || true); R=$(tput sgr0 || true)
              G=$(tput setaf 2 || true); Y=$(tput setaf 3 || true); RD=$(tput setaf 1 || true)
            else
              B=""; D=""; R=""; G=""; Y=""; RD=""
            fi

            ok()   { printf ' %s✓%s %s\n' "$G" "$R" "$1"; }
            info() { printf ' %s→%s %s\n' "$Y" "$R" "$1"; }
            err()  { printf ' %s✘%s %s\n' "$RD" "$R" "$1" >&2; }
            head() { printf '\n %s%s%s\n %s──────────────────────────────%s\n' "$B" "$1" "$R" "$D" "$R"; }

            spin_pid=""
            cleanup() {
              # Only rewrite the current line when a spinner actually drew on it.
              if [ -n "$spin_pid" ]; then
                kill "$spin_pid" 2>/dev/null || true
                spin_pid=""
                printf '\r\033[K'
              fi
            }
            trap 'cleanup; printf "\n"; exit 130' INT TERM
            trap cleanup EXIT

            spinner_start() {
              [ -t 1 ] || return 0
              local msg=$1
              ( frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; i=0
                while :; do
                  i=$(( (i + 1) % 10 ))
                  printf '\r %s%s%s %s' "$Y" "''${frames:$i:1}" "$R" "$msg"
                  sleep 0.1
                done ) &
              spin_pid=$!
            }
            spinner_stop() {
              if [ -n "$spin_pid" ]; then
                kill "$spin_pid" 2>/dev/null || true
                wait "$spin_pid" 2>/dev/null || true
                spin_pid=""
                printf '\r\033[K'
              fi
            }

            responding() { curl -fsS --max-time 2 -o /dev/null "$URL/" 2>/dev/null; }

            usage() {
              cat <<USAGE
      reclip — self-hosted video and audio downloader (web UI on $URL)

      Usage:
        reclip [OPTIONS]          Start the server if needed, then open the web UI
        reclip start              Start the server without opening a browser
        reclip stop               Stop the server
        reclip restart            Restart the server
        reclip status             Show whether the server is running
        reclip logs [-f]          Show the server log

      Options:
        -n, --no-browser          Start the server but do not open a browser
        -h, --help                Show this help and exit

      The server is a systemd user service ($UNIT). It listens on
      127.0.0.1:$PORT only and is never exposed to the network.
      Finished files are staged under \''${XDG_CACHE_HOME:-~/.cache}/reclip/downloads
      and are saved through the browser's own download prompt.

      Download only media you have the rights to download.
      USAGE
            }

            wait_ready() {
              local waited=0
              spinner_start "Waiting for the server to come up..."
              while ! responding; do
                if ! systemctl --user is-active --quiet "$UNIT"; then
                  spinner_stop
                  err "the ReClip service stopped while starting up"
                  printf '\n%s\n' "$(systemctl --user status --no-pager --lines=15 "$UNIT" 2>&1 || true)" >&2
                  return 1
                fi
                if [ "$waited" -ge 300 ]; then
                  spinner_stop
                  err "timed out after 30s waiting for $URL"
                  return 1
                fi
                sleep 0.1; waited=$((waited + 1))
              done
              spinner_stop
              return 0
            }

            open_browser=1
            action=open
            case "''${1:-}" in
              -h|--help) usage; exit 0 ;;
              -n|--no-browser) open_browser=0 ;;
              start)   action=start; open_browser=0 ;;
              stop)    action=stop ;;
              restart) action=restart ;;
              status)  action=status ;;
              logs)    shift; exec journalctl --user -u "$UNIT" --no-pager "$@" ;;
              "")      : ;;
              *) err "unknown argument: $1"; printf '\n'; usage >&2; exit 2 ;;
            esac

            case "$action" in
              stop)
                head "ReClip"
                if systemctl --user is-active --quiet "$UNIT"; then
                  systemctl --user stop "$UNIT" && ok "Server stopped"
                else
                  info "Server was not running"
                fi
                printf '\n'; exit 0 ;;
              status)
                head "ReClip"
                if systemctl --user is-active --quiet "$UNIT"; then
                  ok "Service active"
                  if responding; then ok "Listening on $URL"; else err "Not responding on $URL"; fi
                else
                  info "Server is not running (start it with: reclip start)"
                fi
                printf '\n'; exit 0 ;;
              restart)
                head "ReClip"
                systemctl --user restart "$UNIT"
                ok "Server restarted"
                wait_ready || exit 1
                ok "Listening on $URL"
                printf '\n'; exit 0 ;;
            esac

            head "ReClip"

            if [ ! -x ${reclip}/bin/reclip-server ]; then
              err "reclip-server is missing from the system profile"; exit 1
            fi
            ok "Dependencies ready"

            if responding; then
              ok "Server already running"
            else
              # `systemctl start` on an active unit is a no-op, so repeated
              # invocations cannot produce a second server process.
              if ! systemctl --user start "$UNIT"; then
                err "could not start $UNIT"
                printf '\n%s\n' "$(systemctl --user status --no-pager --lines=15 "$UNIT" 2>&1 || true)" >&2
                exit 1
              fi
              ok "Server started"
              wait_ready || exit 1
            fi

            ok "Listening on $URL"

            if [ "$open_browser" -eq 1 ]; then
              info "Opening browser..."
              xdg-open "$URL" >/dev/null 2>&1 || {
                err "could not open a browser; visit $URL"
                printf '\n'; exit 1
              }
            fi
            printf '\n'
    '';
  };

  # Launcher entry target. The `reclip` CLI is built for a terminal (headings,
  # spinner, errors on stderr); from the application launcher there is no
  # terminal to read any of that, and a truncated stdout can even kill it with
  # SIGPIPE. This variant does exactly what the entry promises -- bring the
  # server up, then hand the URL to the default browser -- and reports problems
  # as a desktop notification instead of to a console nobody is watching.
  reclipOpen = pkgs.writeShellApplication {
    name = "reclip-open";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      systemd
      xdg-utils
      libnotify
    ];
    text = ''
      URL=${lib.escapeShellArg url}
      UNIT=reclip.service

      die() {
        notify-send --app-name=ReClip --icon=reclip --urgency=critical \
          "ReClip" "$1" 2>/dev/null || true
        echo "reclip-open: $1" >&2
        exit 1
      }

      responding() { curl -fsS --max-time 2 -o /dev/null "$URL/" 2>/dev/null; }

      if ! responding; then
        # A no-op if the unit is already running, so double-clicking the
        # launcher entry cannot start a second server.
        systemctl --user start "$UNIT" \
          || die "Could not start $UNIT. Try: systemctl --user status $UNIT"

        waited=0
        until responding; do
          if ! systemctl --user is-active --quiet "$UNIT"; then
            die "The ReClip service stopped while starting. Try: journalctl --user -u $UNIT -n 40"
          fi
          if [ "$waited" -ge 300 ]; then
            die "Timed out waiting for $URL"
          fi
          sleep 0.1
          waited=$((waited + 1))
        done
      fi

      exec xdg-open "$URL"
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "reclip";
    desktopName = "ReClip";
    comment = "Download video and audio from supported websites";
    exec = "${reclipOpen}/bin/reclip-open";
    icon = "reclip";
    terminal = false;
    startupNotify = true;
    categories = [
      "AudioVideo"
      "Network"
    ];
    keywords = [
      "download"
      "video"
      "audio"
      "youtube"
      "yt-dlp"
    ];
  };
in
{
  environment.systemPackages = [
    reclip
    reclipCli
    reclipOpen
    desktopItem
  ];

  # Started on demand by the `reclip` CLI and the launcher entry; deliberately
  # not wantedBy default.target, so it uses no resources until it is asked for.
  systemd.user.services.reclip = {
    description = "ReClip media downloader (127.0.0.1:${toString port})";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${reclip}/bin/reclip-server";
      Restart = "on-failure";
      RestartSec = 3;
      # app.py binds HOST:PORT; keep it on loopback only.
      Environment = [
        "HOST=127.0.0.1"
        "PORT=${toString port}"
        "PYTHONUNBUFFERED=1"
      ];
    };
  };
}
