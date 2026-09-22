{ pkgs, ... }:
let
  # Steam writes ~/.local/share/applications/<Game>.desktop with
  # Icon=steam_icon_<appid>, but frequently never drops a matching icon
  # file, so the entry renders as a missing texture in Ambxst's launcher.
  # This backfills one from Steam's own local artwork cache — never from
  # the network — and falls back to Steam's own generic icon so an entry
  # is never blank. Also doubles as the general "a desktop entry or icon
  # changed" cache refresher (e.g. for modules/user-desktop.nix's rmpc
  # override, or newly installed Flatpaks).
  desktopCacheRefresh = pkgs.writeShellApplication {
    name = "desktop-cache-refresh";
    runtimeInputs = with pkgs; [ ffmpeg gnugrep findutils gtk3 desktop-file-utils coreutils ];
    text = ''
      apps_dir="$HOME/.local/share/applications"
      icon_root="$HOME/.local/share/icons/hicolor"
      steam_cache="$HOME/.local/share/Steam/appcache/librarycache"
      fallback_icon="/run/current-system/sw/share/icons/hicolor/256x256/apps/steam.png"
      size=128
      dim="$size"x"$size"

      mkdir -p "$apps_dir" "$icon_root"

      shopt -s nullglob
      for desktop_file in "$apps_dir"/*.desktop; do
        appid=$(grep -oP '^Icon=steam_icon_\K[0-9]+' "$desktop_file" || true)
        if [ -z "$appid" ]; then
          continue
        fi

        target="$icon_root/$dim/apps/steam_icon_$appid.png"
        if [ -f "$target" ]; then
          continue
        fi

        src=""
        app_cache="$steam_cache/$appid"
        if [ -d "$app_cache" ]; then
          # Prefer a loose file directly under the appid dir: on current
          # Steam this is the small square icon (everything else — hero,
          # header, capsule, logo — lives one level deeper in a
          # content-hash subdirectory).
          src=$(find "$app_cache" -maxdepth 1 -type f | head -n1)
          if [ -z "$src" ]; then
            src=$(find "$app_cache" -iname "logo.png" | head -n1)
          fi
          if [ -z "$src" ]; then
            src=$(find "$app_cache" -type f | head -n1)
          fi
        fi
        if [ -z "$src" ]; then
          src="$fallback_icon"
        fi

        mkdir -p "$(dirname "$target")"
        ffmpeg -y -loglevel error -i "$src" \
          -vf "scale=$size:$size:force_original_aspect_ratio=decrease,pad=$size:$size:(ow-iw)/2:(oh-ih)/2:color=0x00000000" \
          "$target"
      done

      gtk-update-icon-cache -f -t "$icon_root" >/dev/null 2>&1 || true
      update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    '';
  };
in {
  # The ly/start-hyprland session is not managed by UWSM. Hyprland's Lua
  # startup/shutdown hooks own this target, which keeps portals available.
  systemd.user.targets.hyprland-session = {
    description = "Hyprland graphical session";
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" "xdg-desktop-portal.service" ];
    after = [ "graphical-session-pre.target" ];
  };

  xdg.portal.config.hyprland = {
    default = [ "hyprland" "kde" "gtk" ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    "org.freedesktop.impl.portal.AppChooser" = [ "kde" ];
    "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
    "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
  };

  # Also runnable by hand: `desktop-cache-refresh`.
  environment.systemPackages = [ desktopCacheRefresh ];

  systemd.user.services.desktop-cache-refresh = {
    description = "Backfill missing Steam game icons and refresh XDG desktop/icon caches";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${desktopCacheRefresh}/bin/desktop-cache-refresh";
    };
    wantedBy = [ "default.target" ];
  };

  systemd.user.paths.desktop-cache-refresh = {
    description = "Watch for new or changed desktop entries and icons";
    wantedBy = [ "default.target" ];
    pathConfig = {
      PathModified = [
        "%h/.local/share/applications"
        "%h/.local/share/icons"
      ];
      Unit = "desktop-cache-refresh.service";
    };
  };
}
