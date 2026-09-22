{ config, pkgs, ... }:

let
  user = config.workstation.username;
in
{
  # WinBoat, installed from nixpkgs rather than as a hand-run AppImage.
  #
  # The AppImage was launched through `appimage-run`, which sandboxes it with
  # bubblewrap in an unprivileged user namespace. That namespace can only map
  # the process's own uid/gid, so every supplementary group shows up as
  # `nogroup`: inside the sandbox `id -Gn` printed "users nogroup" even though
  # neo really is in the docker group. WinBoat's prerequisite check shells out
  # to `id -Gn` and greps for "docker", so it always reported
  # "User added to the docker group" as failing. Docker itself worked — the
  # kernel still applied the real supplementary GIDs to the socket — so this
  # was purely a false negative produced by the sandbox.
  #
  # pkgs.winboat runs Electron directly, with no bubblewrap layer, so the
  # check sees the real group list. It also puts freerdp, docker-compose and
  # usbutils on WinBoat's PATH via its own wrapper.
  environment.systemPackages = [ pkgs.winboat ];

  # WinBoat's documented NixOS prerequisites. Docker itself and neo's docker
  # group membership are declared in modules/development-services.nix; this
  # keeps the requirement visible from the WinBoat module too. NixOS merges
  # extraGroups lists across modules, so "docker" is not duplicated.
  virtualisation.docker.enable = true;
  users.users.${user}.extraGroups = [ "docker" ];

  # KVM acceleration (dockur/windows) is already provided: kvm_intel is loaded
  # by the running kernel and neo is in the kvm group via
  # modules/android-workstation.nix, so nothing further is declared here.
}
