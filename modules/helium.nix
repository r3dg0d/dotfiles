{ pkgs, ... }:
{
  environment.systemPackages = [ (pkgs.callPackage ../packages/helium-bin.nix { }) ];
  # The official Helium binary uses Chromium's Linux policy directory.
  # Delegate DNS to systemd-resolved, whose .loki/.snode routes use Lokinet.
  environment.etc."chromium/policies/managed/lokinet-dns.json".text = builtins.toJSON {
    DnsOverHttpsMode = "off";
    BuiltInDnsClientEnabled = false;
  };
}
