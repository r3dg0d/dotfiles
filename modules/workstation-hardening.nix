{ lib, pkgs, ... }:
{
  networking.firewall = { enable = true; checkReversePath = "loose"; };
  services.openssh.enable = false;
  security.sudo = { wheelNeedsPassword = true; execWheelOnly = true; };
  boot.loader.systemd-boot.editor = false;
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
  };
  services.journald.settings.Journal = { Storage = "persistent"; SystemMaxUse = "1G"; RuntimeMaxUse = "256M"; MaxRetentionSec = "30day"; };
  nix.settings = { require-sigs = true; trusted-users = [ "root" ]; };
  nix.optimise.automatic = true;
  environment.systemPackages = [ pkgs.lynis ];
  # Preserve unprivileged user namespaces, IPv6 autoconfiguration, VPN routing,
  # executable build directories and existing LSMs for desktop/development.
}
