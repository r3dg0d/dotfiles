# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ../../modules/identity.nix
    ../../modules/security-tools.nix
    ../../modules/development.nix
    ../../modules/gaming.nix
    ../../modules/desktop.nix
    ../../modules/ambxst.nix
    ../../modules/music.nix
    ../../modules/user-desktop.nix
    ../../modules/cursor.nix
    # The display manager's service Conflicts=autovt@tty1.service, which
    # stops the getty carrying a live tty1 session — apply with
    # `rebuild boot` + reboot rather than `switch` from that session.
    ../../modules/login-manager.nix
    ../../modules/shell-greeting.nix
    ../../modules/flatpak.nix
    ../../modules/desktop-integration.nix
    ../../modules/screen-recorder.nix
  ];

  # Graphics Card (NVIDIA RTX 4090) Drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  nixpkgs.config.allowUnfree = true; # Allows NVIDIA drivers to install

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;

    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Preserve the installed Linux 7.2 kernel family.
  boot.kernelPackages = pkgs.linuxPackages_7_2;

  # Networking
  networking.hostName = lib.mkDefault "workstation"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Nix
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # User
  users.users.${config.workstation.username} = {
    isNormalUser = true;
    description = config.workstation.username;

    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # Hyprland
  programs.hyprland.enable = true;

  # Basic packages
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    nano
    vim
    ghostty
    firefox
    nautilus
  ];

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # File manager support
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # XDG Portals
  xdg.portal.enable = true;

  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
  ];

  # Audio
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;

  # Input
  services.libinput.enable = true;

  # NixOS Version Number
  system.stateVersion = "26.05"; # Did you read the comment?

}
