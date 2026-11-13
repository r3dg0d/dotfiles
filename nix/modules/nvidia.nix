# RTX 4090 (Ada Lovelace / AD102): proprietary driver with open-source kernel
# module (NVIDIA's recommended path for Turing+). Setting videoDrivers to
# "nvidia" also makes NixOS auto-blacklist nouveau, which was previously
# bound to the GPU (dmesg showed nouveau driving the AD102 before this).
{ config, lib, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;   # required for Wayland/niri
    open = true;
    nvidiaSettings = true;
    powerManagement.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
