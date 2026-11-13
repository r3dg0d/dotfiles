# Kernel 7.3 line (nixos-26.05: 7.2.10, binary-cached) for the RTX 4090.
#
# The channel's nvidia-open 595.71.05 does NOT build on 7.2: Linux 7.2 removed
# strncpy() (os-interface.c:764 "implicit declaration of function 'strncpy'"), and
# once that is patched nvidia-drm also breaks on the 7.2 drm_atomic_state API.
# NVIDIA 595.104.02 (what nixos-unstable ships as stable) handles both; it was
# test-built against linux 7.2.10 on this machine (module, nvidia-x11, settings,
# persistenced). Hashes copied from nixos-unstable 26.11.1109063 nvidia-x11/default.nix.
#
# systemd-boot keeps the last 10 generations, so the 6.18 / 595.71.05 generation stays in the menu.
{ config, lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_7_3;

  hardware.nvidia.package = lib.mkForce (config.boot.kernelPackages.nvidiaPackages.mkDriver {
    version = "595.104.02";
    sha256_64bit = "sha256-5CHCAuTHn1jDx/MWG75xRU67PYiTb4ggWg4yfNBMWco=";
    sha256_aarch64 = "sha256-PafStmwNMufeDp3VtpTGGCoW+53Gor/mieO1m1pI7gI=";
    openSha256 = "sha256-FWk5ra2yjz8VAxAA8GXrSoeBj/XC1BKvsKsBKR09joE=";
    settingsSha256 = "sha256-4Kxro6tvI5aX4nu2RspgyBsW+Jq3/VYjSAS5UGdzTCU=";
    persistencedSha256 = "sha256-JsMLPqJuZwAtHngsQODMsmgO7F2tVkQ2arc7fYa2bwo=";
  });
}
