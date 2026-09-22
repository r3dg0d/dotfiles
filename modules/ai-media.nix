{ config, config, lib, pkgs, ... }:
let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
  aiRoot = "${home}/ai";
  comfyDir = "${aiRoot}/ComfyUI";

  # Libraries needed by pip-installed CUDA wheels (torch, triton, av) running
  # on Nix's Python, plus the NVIDIA driver libraries from /run/opengl-driver.
  runtimeLibs = with pkgs; [ stdenv.cc.cc.lib zlib libGL glib ];
in {
  environment.systemPackages = [ pkgs.krita ];

  # Triton (used by PyTorch) executes prebuilt generic-Linux helper binaries
  # such as `ptxas`; nix-ld provides the dynamic loader they expect.
  programs.nix-ld = {
    enable = true;
    libraries = runtimeLibs;
  };

  # GPU access for Docker containers via CDI (`--device=nvidia.com/gpu=all`).
  hardware.nvidia-container-toolkit.enable = true;

  # ComfyUI (manual NVIDIA install in ${comfyDir}/.venv, PyTorch cu130).
  # Serves the native YuE2/SheetSage2 nodes used by the yue2-music MCP server.
  systemd.services.comfyui = {
    description = "ComfyUI (localhost:8188)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig = {
      ConditionPathExists = "${comfyDir}/.venv/bin/python";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    # gcc: Triton compiles small CUDA driver shims at runtime.
    path = with pkgs; [ gcc ffmpeg-headless git ];
    environment = {
      HOME = "${home}";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}";
      TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      User = user;
      Group = "users";
      WorkingDirectory = comfyDir;
      ExecStart = "${comfyDir}/.venv/bin/python main.py --listen 127.0.0.1 --port 8188";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # AllTalk TTS v2 (official erew123/alltalk_tts XTTS image).
  # API on localhost:7851 (used by alltalk-tts-mcp), Gradio UI on localhost:7852.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.alltalk = {
    image = "erew123/alltalk_tts:latest-xtts";
    ports = [ "127.0.0.1:7851:7851" "127.0.0.1:7852:7852" ];
    environment = {
      ALLTALK_ENABLE_MULTI_ENGINE_MANAGER = "false";
      ALLTALK_GRADIO_INTERFACE = "true";
      ALLTALK_LAUNCH_GRADIO = "true";
      ALLTALK_AUTO_CLEANUP = "false";
    };
    volumes = [
      "${aiRoot}/alltalk/outputs:/home/alltalk/outputs"
      "${aiRoot}/alltalk/voices:/home/alltalk/voices"
      "${aiRoot}/alltalk/rvc_voices:/home/alltalk/models/rvc_voices"
    ];
    extraOptions = [ "--device=nvidia.com/gpu=all" ];
  };

  systemd.services.docker-alltalk = {
    after = [ "nvidia-container-toolkit-cdi-generator.service" ];
    wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
    unitConfig.ConditionPathIsDirectory = "${aiRoot}/alltalk/voices";
  };
}
