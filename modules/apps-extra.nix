{ config, pkgs, ... }:
let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
  # fuzzel-based "Open With": lists apps whose desktop entry handles the
  # file's MIME type (then every other app), launches the pick via gio.
  openWith = pkgs.writers.writePython3Bin "fuzzel-open-with" { flakeIgnore = [ "E501" ]; } ''
    import os
    import subprocess
    import sys
    from configparser import ConfigParser

    files = sys.argv[1:]
    if not files:
        sys.exit("usage: fuzzel-open-with FILE...")
    mime = subprocess.run(["${pkgs.xdg-utils}/bin/xdg-mime", "query", "filetype", files[0]],
                          capture_output=True, text=True).stdout.strip()
    dirs = [os.path.expanduser("~/.local/share")] + os.environ.get(
        "XDG_DATA_DIRS", "/run/current-system/sw/share").split(":")
    apps, seen = [], set()
    for d in dirs:
        appdir = os.path.join(d, "applications")
        if not os.path.isdir(appdir):
            continue
        for f in sorted(os.listdir(appdir)):
            if not f.endswith(".desktop") or f in seen:
                continue
            seen.add(f)
            cp = ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(os.path.join(appdir, f), encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            if e.get("NoDisplay") == "true" or e.get("Type") != "Application" or "Exec" not in e:
                continue
            match = mime and mime in e.get("MimeType", "").split(";")
            apps.append((not match, e.get("Name", f), os.path.join(appdir, f), e.get("Icon", "")))
    apps.sort()
    lines = "".join(f"{n}{'  ★' if not other else '''}\0icon\x1f{i}\n" for other, n, _, i in apps)
    r = subprocess.run(["${pkgs.fuzzel}/bin/fuzzel", "--dmenu", "--index", "--prompt", f"Open with ({mime}): "],
                       input=lines, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(0)
    path = apps[int(r.stdout.strip())][2]
    subprocess.Popen(["${pkgs.glib}/bin/gio", "launch", path, *files], start_new_session=True)
  '';
  # SUPER + SPACE (user/hyprland.lua). A wrapper rather than a bare `fuzzel` in
  # the keybind: fuzzel has no single-instance guard of its own, so a second
  # press would stack a second launcher on top of the first. Its appearance
  # comes from user/fuzzel.ini, linked by modules/user-desktop.nix.
  appLauncher = pkgs.writeShellApplication {
    name = "app-launcher";
    runtimeInputs = [
      pkgs.procps
      pkgs.fuzzel
    ];
    text = ''
      if pgrep -x fuzzel >/dev/null 2>&1; then
        exit 0
      fi
      exec fuzzel "$@"
    '';
  };

  chatgpt = pkgs.chatgpt.overrideAttrs (o: { meta = o.meta // { platforms = pkgs.lib.platforms.all; }; });
  # The package's binary is macOS-only, so the launcher entry opens
  # chatgpt.com as a Helium app window, using the package's icon.
  chatgptLauncher = pkgs.makeDesktopItem {
    name = "chatgpt";
    desktopName = "ChatGPT";
    exec = "helium --app=https://chatgpt.com";
    icon = "${chatgpt}/Applications/ChatGPT.app/Contents/Resources/icon-chatgpt.png";
    categories = [ "Network" "Chat" ];
  };

  # Matching Helium --app webapps (same pattern as ChatGPT). Icons use
  # simple themed names; Helium provides chrome-class windowing. No
  # passwords/cookies/tokens are embedded.
  mkHeliumApp = { name, desktopName, url, icon ? "helium", categories ? [ "Network" ] }:
    pkgs.makeDesktopItem {
      inherit name desktopName icon categories;
      exec = "helium --app=${url}";
    };

  xLauncher = mkHeliumApp {
    name = "x-twitter";
    desktopName = "X";
    url = "https://x.com/";
    icon = "helium";
    categories = [ "Network" ];
  };
  grokLauncher = mkHeliumApp {
    name = "grok";
    desktopName = "Grok";
    url = "https://grok.com/";
    icon = "helium";
    categories = [ "Network" "Chat" ];
  };
  claudeLauncher = mkHeliumApp {
    name = "claude";
    desktopName = "Claude";
    url = "https://claude.ai/";
    icon = "helium";
    categories = [ "Network" "Chat" ];
  };
  geminiLauncher = mkHeliumApp {
    name = "gemini";
    desktopName = "Gemini";
    url = "https://gemini.google.com/";
    icon = "helium";
    categories = [ "Network" "Chat" ];
  };
in {
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = [ pkgs.fuzzel openWith appLauncher
    chatgpt chatgptLauncher
    xLauncher grokLauncher claudeLauncher geminiLauncher ];
  programs.obs-studio.enable = true;
  # Nautilus right-click > Scripts > Open With (fuzzel)
  systemd.tmpfiles.rules = [
    "d ${home}/.local/share/nautilus/scripts 0755 ${user} users -"
    "L+ \"${home}/.local/share/nautilus/scripts/Open With (fuzzel)\" - - - - ${pkgs.writeShellScript "nautilus-open-with" ''
      IFS=$'\n'; exec ${openWith}/bin/fuzzel-open-with $NAUTILUS_SCRIPT_SELECTED_FILE_PATHS
    ''}"
  ];
}
