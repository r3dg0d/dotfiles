# NixOS Updater + Storage Optimizer: Rust backends, Quickshell/QML frontends,
# launchers and desktop entries. Replaces the former Ambxst mods
# com.zionsec.nixos-updater / com.zionsec.storage-optimizer.
{
  lib,
  rustPlatform,
  runCommand,
  writeShellApplication,
  makeDesktopItem,
  symlinkJoin,
  quickshell,
  curl,
  git,
  coreutils,
  libnotify,
  glib,
  dbus,
}:
let
  version = "1.0.0";

  # Tools the helpers call. Baked into the binaries at build time (TOOLS_PATH),
  # so the privileged half never depends on the caller's PATH. System tools
  # (nix, nixos-rebuild, flatpak, ambxst, journalctl) come from the running
  # system via /run/current-system/sw/bin.
  toolsPath = lib.makeBinPath [
    curl
    git
    coreutils
    libnotify
    glib # gio trash
    dbus
  ];

  helpers = rustPlatform.buildRustPackage {
    pname = "zionsec-desktop-tools-helpers";
    inherit version;
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./Cargo.toml
        ./Cargo.lock
        ./crates
      ];
    };
    cargoLock.lockFile = ./Cargo.lock;
    env.TOOLS_PATH = toolsPath;
    doCheck = false;
    meta = {
      description = "Backends for NixOS Updater and Storage Optimizer";
      license = lib.licenses.mit;
      mainProgram = "nixos-updater-helper";
    };
  };

  qml = runCommand "zionsec-desktop-tools-qml" { } ''
    mkdir -p $out/share/zionsec-tools
    cp -r ${./qml} $out/share/zionsec-tools/qml
  '';
  qmlDir = "${qml}/share/zionsec-tools/qml";

  envExports = ''
    export NIXOS_UPDATER_HELPER=${helpers}/bin/nixos-updater-helper
    export STORAGE_OPTIMIZER_HELPER=${helpers}/bin/storage-optimizer-helper
  '';

  # Single instance: if the app is already open, ask it (Quickshell IPC) to
  # show the requested page and focus its window; otherwise start it.
  mkLauncher =
    {
      name,
      file,
      title,
    }:
    writeShellApplication {
      inherit name;
      runtimeInputs = [ quickshell ];
      text = ''
        ${envExports}
        cfg=${qmlDir}/${file}
        page="''${1:-}"
        if quickshell ipc -p "$cfg" call app open "$page" >/dev/null 2>&1; then
          # hyprctl from the running system (matches the compositor version).
          command -v hyprctl >/dev/null && hyprctl dispatch 'hl.dsp.focus({ window = "title:^(${title})$" })' >/dev/null 2>&1 || true
          exit 0
        fi
        ZS_START_PAGE="$page" exec quickshell --no-duplicate -p "$cfg"
      '';
    };

  updaterLauncher = mkLauncher {
    name = "nixos-updater";
    file = "updater-app.qml";
    title = "NixOS Updater";
  };
  storageLauncher = mkLauncher {
    name = "storage-optimizer";
    file = "storage-app.qml";
    title = "Storage Optimizer";
  };

  widgets = writeShellApplication {
    name = "zionsec-tools-widgets";
    runtimeInputs = [ quickshell ];
    text = ''
      ${envExports}
      export NIXOS_UPDATER_LAUNCHER=${updaterLauncher}/bin/nixos-updater
      export STORAGE_OPTIMIZER_LAUNCHER=${storageLauncher}/bin/storage-optimizer
      # User units get a minimal PATH; popups call xdg-open / dbus-send.
      export PATH="$PATH:/run/wrappers/bin:/etc/profiles/per-user/''${USER:-neo}/bin:/run/current-system/sw/bin"
      exec quickshell --no-duplicate -p ${qmlDir}/widgets.qml
    '';
  };

  updaterDesktop = makeDesktopItem {
    name = "nixos-updater";
    desktopName = "NixOS Updater";
    genericName = "System Updates";
    comment = "Check and apply NixOS, flake, kernel, Flatpak and Ambxst updates";
    exec = "nixos-updater";
    icon = "system-software-update";
    terminal = false;
    startupNotify = false;
    categories = [
      "System"
      "Settings"
    ];
    keywords = [
      "update"
      "upgrade"
      "nixos"
      "flake"
      "rebuild"
      "flatpak"
      "kernel"
    ];
  };
  storageDesktop = makeDesktopItem {
    name = "storage-optimizer";
    desktopName = "Storage Optimizer";
    genericName = "Disk Usage Analyzer";
    comment = "Analyze disk usage and safely clean Nix generations, caches and more";
    exec = "storage-optimizer";
    icon = "drive-harddisk";
    terminal = false;
    startupNotify = false;
    categories = [
      "System"
      "Filesystem"
    ];
    keywords = [
      "disk"
      "storage"
      "cleanup"
      "space"
      "garbage"
      "analyzer"
    ];
  };
in
symlinkJoin {
  name = "zionsec-desktop-tools-${version}";
  paths = [
    helpers
    qml
    updaterLauncher
    storageLauncher
    widgets
    updaterDesktop
    storageDesktop
  ];
  passthru = {
    inherit helpers qml qmlDir;
    widgetsExe = "${widgets}/bin/zionsec-tools-widgets";
    updaterHelper = "${helpers}/bin/nixos-updater-helper";
    storageHelper = "${helpers}/bin/storage-optimizer-helper";
  };
  meta.description = "NixOS Updater and Storage Optimizer desktop tools";
}
