{ pkgs, lib, ... }:
let
  # NVIDIA driver NVENC API 13.0 vs gsr's expectation of 13.1 — keep
  # `-fallback-cpu-encoding yes` for real capture so Ambxst (which cannot
  # pass the flag itself) still works. Meta commands (--list-*, --help,
  # --version) must NOT get that flag prepended: gsr treats unknown leading
  # args as fatal and prints usage, which poisoned MatrixShot's audio
  # device discovery (it took the usage blurb as `-a`).
  gsrReal = "${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder";
  gpuScreenRecorderWithFallback = pkgs.writeShellScriptBin "gpu-screen-recorder" ''
    case "''${1-}" in
      --list-*|-h|--help|--version)
        exec ${gsrReal} "$@"
        ;;
      *)
        exec ${gsrReal} -fallback-cpu-encoding yes "$@"
        ;;
    esac
  '';
in {
  programs.gpu-screen-recorder.enable = true;

  # hiPrio so this wrapper wins PATH over programs.gpu-screen-recorder's plain binary.
  environment.systemPackages = [ (lib.hiPrio gpuScreenRecorderWithFallback) ];
}
