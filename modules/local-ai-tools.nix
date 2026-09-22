{ config,
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
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

  # --------------------------------------------------------------- llada ---
  lladaRoot = "${home}/.local/share/llada-image";
  lladaVenv = "${lladaRoot}/venv";
  lladaRepo = "${lladaRoot}/LLaDA-Image";

  # The resident inference server. It runs on the virtualenv's interpreter
  # because that is where torch/diffusers live; the source itself is in the
  # store, so it is versioned with the system.
  lladaDaemon = ../packages/llada-cli/daemon/llada_imaged.py;

  lladaCli = py.buildPythonApplication {
    pname = "llada-cli";
    version = "1.0.0";
    pyproject = true;
    src = ../packages/llada-cli;
    build-system = [ py.hatchling ];
    dependencies = [ py.rich ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    doCheck = false;
    postFixup = ''
      for prog in text2img img2img llada-image; do
        wrapProgram $out/bin/$prog \
          --prefix PATH : ${lib.makeBinPath [ pkgs.systemd ]}
      done
    '';
    meta.description = "text2img / img2img / llada-image front ends for LLaDA-Image Turbo";
  };
in
{
  environment.systemPackages = [
    aiwmremover
    lladaCli
  ];

  # Resident LLaDA-Image inference service.
  #
  # Checkpoint selection (logged by the daemon on every load):
  #
  # The official FP8 Turbo checkpoint cannot be used here. Its component
  # configs declare quantization_config.quant_method = "fp8", which no released
  # diffusers understands (0.39.0 and 0.40.0 both accept only bitsandbytes,
  # gguf, quanto, torchao, modelopt, auto-round and friends), and the official
  # LLaDA-Image repository contains no FP8 loading code at all. Loading it
  # raises "Unknown quantization type, got fp8". The FP8 repos target other
  # runtimes, such as the third-party ComfyUI nodes upstream links to.
  #
  # So the BF16 Turbo checkpoint is selected: it is the official checkpoint the
  # official Diffusers pipeline is written for, and no ad-hoc quantization is
  # performed. Measured component sizes are text_encoder 32.65 GB, transformer
  # 13.08 GB, sigvq 2.59 GB, text_projection 0.65 GB, vae 0.17 GB, queryformer
  # 0.10 GB -- 49.24 GB in total, against a 24 GB card.
  #
  # It fits because of the daemon's "split" placement (LLADA_OFFLOAD below):
  # the 16.6 GB denoising stack stays resident on the GPU, and the 32.65 GB
  # text encoder is dispatched with transformers' device_map="auto" across
  # whatever VRAM is left, then RAM, then disk. That works where the stock
  # diffusers offload modes do not, because this pipeline positions its own
  # inputs with `x.to(self.<component>.device)`: device_map leaves `.device`
  # reporting a real device, whereas whole-model offload parks parameters on
  # `meta` and the same call dies with "Cannot copy out of meta tensor".
  #
  # Measured on this machine: ~31 s to load, ~15 s per 1024x1024 4-step
  # generation once warm, with the text encoder running from CPU+disk.
  #
  # The GPU must actually be free -- the denoising stack needs ~16.6 GB, so
  # ollama has to have unloaded its model first. The daemon's pre-flight says
  # so explicitly rather than failing with a bare CUDA OOM.
  #
  # Started on demand by text2img / img2img; never wantedBy default.target, so
  # it holds no VRAM until it is asked for, and it unloads the model again
  # after LLADA_IDLE_TIMEOUT seconds of inactivity.
  systemd.user.services.llada-image = {
    description = "LLaDA-Image Turbo inference service (local Unix socket)";
    unitConfig.ConditionPathExists = "${lladaVenv}/bin/python";
    environment = {
      HOME = "${home}";
      LD_LIBRARY_PATH = ldPath;
      TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
      PYTHONUNBUFFERED = "1";
      LLADA_REPO = lladaRepo;
      LLADA_MODEL_ID = "inclusionAI/LLaDA-Image-Turbo";
      LLADA_PRECISION = "bfloat16";
      LLADA_OFFLOAD = "split";
      # Unload the model after 10 minutes idle so it does not hold VRAM
      # during gaming or other GPU work.
      LLADA_IDLE_TIMEOUT = "600";
    };
    path = [ pkgs.gcc ];
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = lladaRepo;
      ExecStart = "${lladaVenv}/bin/python ${lladaDaemon}";
      Restart = "on-failure";
      RestartSec = 5;
      # The socket lives in $XDG_RUNTIME_DIR and is mode 0600; no TCP port is
      # opened, so the service is not reachable from the network.
      KillSignal = "SIGINT";
      TimeoutStopSec = 60;
      # This machine has 31 GB of RAM and no swap, and the checkpoint is much
      # larger than that. Cap the service so a large load reclaims its own
      # page cache instead of letting the kernel OOM-kill the desktop session.
      MemoryHigh = "20G";
      MemoryMax = "26G";
      OOMPolicy = "stop";
    };
  };
}
