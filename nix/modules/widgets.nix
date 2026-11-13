# Tools/services used by the galaxy-hub quickshell widgets and the VM Construct suite.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    speedtest-cli   # network panel speedtest (falls back to `nix shell nixpkgs#speedtest-cli` without this)
    playerctl       # waybar Kopuz module (galaxy/runtime/bin has a private copy today)
    dnsutils        # dig, for the DNS check
    blueman         # optional GUI for pairing new Bluetooth devices
  ];
  services.blueman.enable = true;

  # Updater panel: firmware section (fwupdmgr get-updates)
  services.fwupd.enable = true;

  # VM Construct (windowsvm / linuxvm / androidvm): vmtools doctor wants these
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  users.users.r3dg0d.extraGroups = [ "libvirtd" "kvm" ];
}
