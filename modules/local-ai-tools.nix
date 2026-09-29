{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.workstation.homeDirectory;
  # user unused after LLaDA removal; keep home for aiwm path
  py = pkgs.python3Packages;

  # Same set as modules/ai-media.nix: the libraries pip-installed CUDA wheels
  # (torch, triton, opencv) expect from a normal FHS distribution, plus the
  # NVIDIA driver libraries from /run/opengl-driver.
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    libGL
    glib
  ];
  ldPath = "/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}";

  # ---------------------------------------------------------------- aiwm ---
  # The heavy upstream stack (torch + diffusers + onnxruntime + CUDA wheels)
  # lives in a pip virtualenv, as ComfyUI already does on this machine. Only
  # the wrapper is a Nix package, so `aiwmremover` is a normal global command.
  aiwmVenv = "${home}/.local/share/aiwmremover/venv";

  aiwmremover = py.buildPythonApplication {
    pname = "aiwmremover";
    version = "1.0.0";
    pyproject = true;
    src = ../packages/aiwmremover;
    build-system = [ py.hatchling ];
    dependencies = [ py.rich ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    doCheck = false;
    postFixup = ''
      wrapProgram $out/bin/aiwmremover \
        --set-default AIWMREMOVER_UPSTREAM ${aiwmVenv}/bin/remove-ai-watermarks \
        --prefix LD_LIBRARY_PATH : ${ldPath} \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.ffmpeg
            config.hardware.nvidia.package.bin
          ]
        }
    '';
    meta = {
      description = "Convenience front end for the remove-ai-watermarks CLI";
      mainProgram = "aiwmremover";
    };
  };
in
{
  environment.systemPackages = [
    aiwmremover
  ];

  # LLaDA (llada-cli / text2img / img2img / llada-image + systemd user unit)
  # removed 2026-09-29 — replaced by Qwen wrappers in ~/.local/bin.
}
