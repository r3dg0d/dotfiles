{ pkgs, lib, ... }:
let
  # Verified live on this machine: the installed NVIDIA driver (595.99.02)
  # only exposes NVENC API 13.0, but gpu-screen-recorder 6.1.1's bundled
  # NVENC headers require 13.1 ("your nvidia driver only supports nvenc
  # api version 13.0, but the FFmpeg version that GPU Screen Recorder uses
  # requires nvenc api version 13.1"). That's a genuine upstream version
  # skew, not a misconfiguration — fixing it for real means either a
  # driver bump (a much bigger, riskier change than this task, and not
  # done here) or a different gpu-screen-recorder build. `-fallback-cpu-
  # encoding yes` is gpu-screen-recorder's own documented answer to
  # exactly this situation: try GPU encoding first, transparently fall
  # back to libx264 on CPU only when GPU encoding isn't usable — so this
  # keeps working as-is if a future driver update fixes NVENC, and costs
  # nothing when GPU encoding *is* available.
  #
  # This wrapper covers direct CLI calls. Ambxst prepends its own bundled
  # recorder, so modules/ambxst.nix separately patches its backend arguments.
  gpuScreenRecorderWithFallback = pkgs.symlinkJoin {
    name = "gpu-screen-recorder-with-fallback";
    paths = [ pkgs.gpu-screen-recorder ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f $out/bin/gpu-screen-recorder
      makeWrapper ${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder $out/bin/gpu-screen-recorder \
        --add-flags "-fallback-cpu-encoding yes"
    '';
  };
in
{
  # programs.gpu-screen-recorder still does the real work: installs the
  # plain pkgs.gpu-screen-recorder and generates the gsr-kms-server
  # security wrapper KMS capture needs. This is a Linux-capability
  # wrapper (cap_sys_admin, cap_setpcap), not a setuid-root binary: it
  # lets gsr-kms-server read DRM/KMS framebuffers without running the
  # whole recorder as root.
  #
  # The overlay UI (programs.gpu-screen-recorder.ui.enable) is
  # deliberately left off: Ambxst drives the plain CLI and has its own
  # start/stop/status UI, so the overlay would be an unused second control
  # surface, and it adds a *second*, more sensitive wrapper of its own
  # (gsr-global-hotkeys, cap_setuid) purely for a global-hotkey daemon
  # nothing here needs.
  programs.gpu-screen-recorder.enable = true;

  # Installed at higher priority so it wins the bin/gpu-screen-recorder
  # collision against programs.gpu-screen-recorder's own (unwrapped)
  # environment.systemPackages entry above — same pattern modules/
  # ambxst.nix already uses for its own bundled-tool collisions.
  environment.systemPackages = [ (lib.hiPrio gpuScreenRecorderWithFallback) ];
}
