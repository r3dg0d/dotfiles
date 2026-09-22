{ config, pkgs, lib, ... }:
let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
  # KytyPS5 is built from source with the upstream dev shell (nix/devshell.nix)
  # and installed to this tree. Upstream documents that a sandboxed `nix build`
  # is not possible: the CMake configure step downloads the pinned FFmpeg
  # prebuilts and the xbyak/zydis sources. So the binaries live outside the
  # store; everything around them (wrapper, icon, launcher entry) is declarative.
  installDir = "${home}/.local/opt/kytyps5";

  # Mirrors runtimeLibs in the upstream nix/devshell.nix, so the emulator no
  # longer depends on an ephemeral `nix develop` shell.
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    qt6.qtbase
    vulkan-loader
    libglvnd
    alsa-lib
    libpulseaudio
    libX11
    libXcursor
    libXext
    libXfixes
    libXi
    libXrandr
    libXScrnSaver
    libxkbcommon
    wayland
    libdecor
    systemd
    dbus
  ];

  kytyps5 = pkgs.writeShellApplication {
    name = "kytyps5";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
            install_dir=${lib.escapeShellArg installDir}
            launcher="$install_dir/launcher"

            usage() {
              cat <<'USAGE'
      kytyps5 — KytyPS5, an experimental PlayStation 5 emulator

      Usage:
        kytyps5 [OPTIONS] [-- LAUNCHER ARGS...]

      Options:
        -h, --help       Show this help and exit
            --version    Show the built commit and exit
            --where      Print the installation directory and exit

      Any other arguments are passed straight through to the KytyPS5 launcher.

      Notes:
        The launcher manages emulator configurations; select a game from within it.
        KytyPS5 needs a Vulkan 1.3 driver, provided here by hardware.graphics.enable.
        This build is installed in ${installDir}
        and rebuilt from https://github.com/KytyPS5/KytyPS5 with its own dev shell.
      USAGE
            }

            case "''${1:-}" in
              -h|--help) usage; exit 0 ;;
              --version)
                if [ -r "$install_dir/BUILD-INFO.txt" ]; then
                  cat "$install_dir/BUILD-INFO.txt"
                else
                  echo "kytyps5: no build information recorded in $install_dir" >&2
                  exit 1
                fi
                exit 0 ;;
              --where) printf '%s\n' "$install_dir"; exit 0 ;;
              --) shift ;;
            esac

            if [ ! -x "$launcher" ]; then
              cat >&2 <<ERR
      kytyps5: the KytyPS5 launcher is not installed at
        $launcher

      Rebuild it from a checkout of https://github.com/KytyPS5/KytyPS5:

        nix-shell
        cmake -S . -B _Build/linux -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
        cmake --build _Build/linux --target launcher --parallel
        cmake --install _Build/linux --prefix _Build/linux/install

      then copy _Build/linux/install/{launcher,kyty_emulator} into
        $install_dir
      ERR
              exit 127
            fi

            # The NVIDIA driver libraries come from /run/opengl-driver/lib; the rest
            # match the upstream dev shell's runtime library set.
            export LD_LIBRARY_PATH="/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export QT_PLUGIN_PATH="${pkgs.qt6.qtbase}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"

            cd "$install_dir"
            exec ./launcher "$@"
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "kytyps5";
    desktopName = "KytyPS5";
    comment = "PlayStation 5 emulator";
    exec = "${kytyps5}/bin/kytyps5";
    icon = "kytyps5";
    terminal = false;
    startupNotify = true;
    categories = [
      "Game"
      "Emulator"
    ];
    keywords = [
      "PS5"
      "PlayStation"
      "Emulator"
      "Kyty"
    ];
  };

  icon = pkgs.runCommand "kytyps5-icon" { } ''
    install -Dm444 ${../user/kytyps5.svg} \
      "$out/share/icons/hicolor/scalable/apps/kytyps5.svg"
  '';
in
{
  environment.systemPackages = [
    kytyps5
    desktopItem
    icon
  ];
}
